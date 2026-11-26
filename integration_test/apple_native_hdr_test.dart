import 'package:bili_player/bili_player.dart';
import 'package:bilisail/core/platform/macos_application_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/native_hdr_display.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Apple presents color-managed video on the current screen', (
    tester,
  ) async {
    const samples = {
      'p5': String.fromEnvironment('APPLE_P5'),
      'p8': String.fromEnvironment('APPLE_P8'),
      'hdr10': String.fromEnvironment('APPLE_HDR10'),
      'hlg': String.fromEnvironment('APPLE_HLG'),
    };
    expect(samples.values.any((uri) => uri.isNotEmpty), isTrue);
    final engine = MediaKitEngine();
    final policy = MediaRequestPolicy();
    const audio = String.fromEnvironment('APPLE_COMPANION_AUDIO');
    final window = await MacOSApplicationWindow.create();
    try {
      await window?.prepare();
      final surface = Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 320,
            height: 180,
            child: VideoSurface(engine: engine),
          ),
        ),
      );
      await tester.pumpWidget(
        window?.wrap(surface) ?? surface,
        wrapWithView: window == null,
      );
      const channel = MethodChannel('bilisail/hdr_video');
      final transfer = await channel.invokeMethod<String>('supported', {
        'view': window?.window.viewId ?? tester.view.viewId,
      });
      expect(transfer, anyOf('srgb', 'pq'));
      if (const bool.fromEnvironment('APPLE_REQUIRE_HDR')) {
        expect(transfer, 'pq');
      }
      for (final entry in samples.entries.where(
        (sample) => sample.value.isNotEmpty,
      )) {
        final video = MediaTrack(
          uri: Uri.parse(entry.value),
          requestPolicy: policy,
        );
        final source = audio.isEmpty
            ? ProgressiveSource(video)
            : DashPairSource(
                video: video,
                audio: MediaTrack(uri: Uri.parse(audio), requestPolicy: policy),
              );
        await withVideoFrames(
          tester,
          engine.open(source, const OpenOptions(play: false, volume: 0)),
        );
        final config = await engine.inspectNativeOutputConfiguration();
        expect(config['videoOutput'], 'gpu-next', reason: entry.key);
        expect(config['nativeHdrSurface'], transfer == 'pq');
        expect(config['targetTransfer'], transfer);
        if (entry.key == 'p5' || entry.key == 'p8') {
          expect(
            config['videoOutputMatrix'],
            'dolbyvision',
            reason: 'RPU on ${entry.key}',
          );
        }
        await withVideoFrames(tester, engine.seek(const Duration(seconds: 1)));
        expect(engine.currentSnapshot.desiredPlaying, isFalse);
        await withVideoFrames(tester, engine.play());
        await tester.pump(const Duration(milliseconds: 450));
        expect(engine.currentSnapshot.position, greaterThan(Duration.zero));
        expect(engine.inspectDiagnostics().hasDecodedAudio, isTrue);
        await withVideoFrames(tester, engine.pause());
      }
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(
        window?.wrap(const SizedBox.shrink()) ?? const SizedBox.shrink(),
        wrapWithView: window == null,
      );
      await engine.dispose();
      if (window != null) {
        await window.window.prepareToClose();
        await tester.pumpWidget(
          const ViewCollection(views: []),
          wrapWithView: false,
        );
        window.window.dispose();
      }
    }
  });
}
