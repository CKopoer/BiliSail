import 'dart:async';
import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/core/platform/macos_application_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'apple_joc_playback.dart';

const _hdrChannel = MethodChannel('bilisail/hdr_video');
const _inlineSize = Size(320, 180);

/// A standalone Apple Runner entry point, including the production macOS
/// window bootstrap. HTTPS fixtures also work on a physical iPhone.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initializePlayerBackend();
  final engine = MediaKitEngine(
    onDiagnostic: (event) => stdout.writeln('APPLE_MEDIA ${event.toJson()}'),
  );
  final viewport = ValueNotifier(_inlineSize);
  final viewportKey = GlobalKey();
  var success = false;
  try {
    final window = await MacOSApplicationWindow.create();
    await window?.prepare();
    final mounted = Completer<int>();
    final surface = Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: ValueListenableBuilder<Size>(
          valueListenable: viewport,
          builder: (context, size, _) {
            if (!mounted.isCompleted) {
              mounted.complete(View.of(context).viewId);
            }
            return SizedBox.fromSize(
              key: viewportKey,
              size: size,
              child: VideoSurface(engine: engine),
            );
          },
        ),
      ),
    );
    if (window == null) {
      runApp(surface);
    } else {
      window.present(surface);
    }
    final view = await mounted.future.timeout(const Duration(seconds: 15));
    final transfer = await _hdrChannel.invokeMethod<String>('supported', {
      'view': view,
    });
    if (transfer != 'pq' && transfer != 'srgb') {
      throw StateError('No Apple display');
    }
    if (const bool.fromEnvironment('APPLE_REQUIRE_HDR') && transfer != 'pq') {
      throw StateError('This display has no EDR headroom');
    }

    const samples = {
      'p5': String.fromEnvironment('APPLE_P5'),
      'p8': String.fromEnvironment('APPLE_P8'),
      'hdr10': String.fromEnvironment('APPLE_HDR10'),
      'hlg': String.fromEnvironment('APPLE_HLG'),
    };
    const jocBase = String.fromEnvironment('APPLE_JOC_BASE');
    if (jocBase.isEmpty && samples.values.every((uri) => uri.isEmpty)) {
      throw ArgumentError('No test source');
    }
    final policy = MediaRequestPolicy();
    const audio = String.fromEnvironment('APPLE_COMPANION_AUDIO');
    success = true;
    if (jocBase.isNotEmpty) {
      await verifyAppleJoc(engine, Uri.parse(jocBase));
    }
    for (final entry in samples.entries.where(
      (value) => value.value.isNotEmpty,
    )) {
      try {
        stdout.writeln('APPLE_MEDIA opening=${entry.key} display=$transfer');
        final video = MediaTrack(
          uri: Uri.parse(entry.value),
          requestPolicy: policy,
        );
        final source = audio.isEmpty || entry.key == 'p5'
            ? ProgressiveSource(video)
            : DashPairSource(
                video: video,
                audio: MediaTrack(uri: Uri.parse(audio), requestPolicy: policy),
              );
        await engine.open(source, const OpenOptions(play: false, volume: 0));
        final config = await engine.inspectNativeOutputConfiguration();
        stdout.writeln('APPLE_MEDIA output=$config');
        if (config['videoOutput'] != 'gpu-next' ||
            config['nativeHdrSurface'] != (transfer == 'pq') ||
            config['targetTransfer'] != transfer) {
          throw StateError('Unverified Metal output');
        }
        if ((entry.key == 'p5' || entry.key == 'p8') &&
            config['videoOutputMatrix'] != 'dolbyvision') {
          throw StateError('Missing Dolby Vision renderer input');
        }
        await engine.seek(const Duration(seconds: 1));
        if (engine.currentSnapshot.desiredPlaying) {
          throw StateError('Seek resumed a paused source');
        }
        if (entry.key == 'p5' || entry.key == 'p8') {
          final dimensions = engine.currentSnapshot.videoDimensions!;
          final source = Size(
            dimensions.width.toDouble(),
            dimensions.height.toDouble(),
          );
          for (final size in [_inlineSize, Size.infinite, _inlineSize]) {
            viewport.value = size;
            await WidgetsBinding.instance.endOfFrame;
            await _checkFraming(source, viewportKey.currentContext!.size!);
          }
        }
        await engine.play();
        final position = engine.currentSnapshot.position;
        for (
          var i = 0;
          i < 40 && engine.currentSnapshot.position <= position;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        if (engine.currentSnapshot.position <= position ||
            !engine.inspectDiagnostics().hasDecodedAudio) {
          throw StateError('Audio or timeline did not resume');
        }
        await engine.pause();
        stdout.writeln('APPLE_MEDIA_SAMPLE_PASSED ${entry.key}');
      } on Object catch (error, stack) {
        success = false;
        stderr.writeln('APPLE_MEDIA_SAMPLE_FAILED ${entry.key} $error\n$stack');
      }
    }
  } on Object catch (error, stack) {
    success = false;
    stderr.writeln('APPLE_MEDIA_FAILED $error\n$stack');
  } finally {
    viewport.dispose();
    await engine.dispose().timeout(const Duration(seconds: 15));
  }
  if (success) stdout.writeln('APPLE_MEDIA_PASSED');
  await stdout.flush();
  exit(success ? 0 : 1);
}

Future<void> _checkFraming(Size source, Size viewport) async {
  final fitted = applyBoxFit(BoxFit.contain, source, viewport).destination;
  Object? last;
  // Flutter layout can precede UIKit/AppKit platform-view composition.
  for (var attempt = 0; attempt < 50; attempt++) {
    final layers = await _hdrChannel.invokeListMethod<Object?>('geometry');
    final geometry = layers?.singleOrNull;
    last = geometry;
    if (geometry is Map<Object?, Object?>) {
      bool near(String name, List<double> expected) {
        final actual = geometry[name];
        if (actual is! List || actual.length != expected.length) return false;
        for (var i = 0; i < expected.length; i++) {
          final value = actual[i];
          if (value is! num ||
              !value.isFinite ||
              (value - expected[i]).abs() > 1) {
            return false;
          }
        }
        return true;
      }

      final pixels = [source.width, source.height];
      if (near('drawable', pixels) &&
          near('natural', pixels) &&
          near('host', [fitted.width, fitted.height]) &&
          near('frame', [0, 0, fitted.width, fitted.height])) {
        stdout.writeln('APPLE_MEDIA_FRAMING viewport=$viewport layer=$last');
        return;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
  throw StateError('Incomplete frame for $source in $viewport: $last');
}
