import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  for (final useFvp in [false, true]) {
    _testBackend(useFvp);
  }
}

void _testBackend(bool useFvp) {
  testWidgets('${useFvp ? 'fvp' : 'media_kit'} rolling two-minute forward buffer', (
    tester,
  ) async {
    initializePlayerBackend();
    final fixturePath = Platform.environment['BILI_TEST_BUFFER_DIR'];
    expect(fixturePath, isNotNull, reason: 'Use tool/test-windows-buffer.ps1');
    final files = {
      '/video.mp4': await File('$fixturePath/video.mp4').readAsBytes(),
      '/audio.m4a': await File('$fixturePath/audio.m4a').readAsBytes(),
      '/short.mp4': await File('$fixturePath/short.mp4').readAsBytes(),
    };
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final rangeRequests = <String>{};
    server.listen((request) async {
      final bytes = files[request.uri.path];
      if (bytes == null) {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      final range = request.headers.value('range');
      final match = range == null
          ? null
          : RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
      final startText = match?.group(1);
      final start = startText == null ? 0 : int.parse(startText);
      final endText = match?.group(2);
      final end = endText == null || endText.isEmpty
          ? bytes.length - 1
          : int.parse(endText);
      request.response.headers.set('Accept-Ranges', 'bytes');
      request.response.headers.contentType = ContentType(
        request.uri.path == '/audio.m4a' ? 'audio' : 'video',
        'mp4',
      );
      if (start >= bytes.length || end < start) {
        request.response.statusCode = 416;
      } else {
        final safeEnd = end.clamp(start, bytes.length - 1);
        if (match != null) {
          rangeRequests.add(request.uri.path);
          request.response.statusCode = 206;
          request.response.headers.set(
            'Content-Range',
            'bytes $start-$safeEnd/${bytes.length}',
          );
        }
        request.response.contentLength = safeEnd - start + 1;
        request.response.add(bytes.sublist(start, safeEnd + 1));
      }
      try {
        await request.response.close();
      } on SocketException {
        // Replacing/stopping the source intentionally cancels native reads.
      } on HttpException {
        // Native buffering can stop reading before the response completes.
      }
    });
    final PlayerEngine engine = useFvp ? FvpEngine() : MediaKitEngine();
    addTearDown(() async {
      await engine.dispose();
      await server.close(force: true);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: VideoSurface(engine: engine)),
      ),
    );
    MediaTrack track(String path) => MediaTrack(
      uri: Uri.parse('http://127.0.0.1:${server.port}$path'),
      requestPolicy: MediaRequestPolicy(),
    );
    final source = DashPairSource(
      video: track('/video.mp4'),
      audio: track('/audio.m4a'),
    );
    await engine.open(source, const OpenOptions(play: true, volume: 0));
    if (engine case final MediaKitEngine native) {
      expect(native.inspectDiagnostics().hasDecodedAudio, isTrue);
    }
    expect(engine.currentSnapshot.videoDimensions, isNotNull);
    await _until(
      tester,
      () =>
          engine.currentSnapshot.position >= const Duration(milliseconds: 500),
    );
    await engine.pause();

    Future<Duration> checkWindow(String stage) async {
      final information = engine as PlayerInformationSource;
      double nativeSeconds = 0;
      final watch = Stopwatch()..start();
      while (watch.elapsed < const Duration(seconds: 15)) {
        nativeSeconds =
            (await information.inspectPlaybackInformation())?.cacheSeconds ?? 0;
        if (nativeSeconds >= 119) break;
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(nativeSeconds, greaterThanOrEqualTo(119));
      await tester.pump(const Duration(milliseconds: 600));
      nativeSeconds =
          (await information.inspectPlaybackInformation())?.cacheSeconds ?? 0;
      final snapshot = engine.currentSnapshot;
      final ahead = snapshot.buffered - snapshot.position;
      final nativeAhead = Duration(
        microseconds: (nativeSeconds * 1000000).round(),
      );
      // The timeline follows native demuxer time, without a byte-cache proxy
      // or MP4 index. mpv reports its main demuxer; MDK reports the paired min.
      expect(nativeAhead, greaterThanOrEqualTo(const Duration(seconds: 119)));
      expect(
        nativeAhead,
        lessThanOrEqualTo(const Duration(milliseconds: 120500)),
      );
      expect(ahead, greaterThanOrEqualTo(const Duration(seconds: 119)));
      expect(ahead, lessThanOrEqualTo(const Duration(milliseconds: 120500)));
      expect(
        ahead,
        lessThanOrEqualTo(nativeAhead + const Duration(milliseconds: 500)),
      );
      expect(snapshot.buffered, lessThan(snapshot.duration));
      debugPrint(
        'PLAYER_BUFFER backend=${useFvp ? 'fvp' : 'media_kit'} $stage positionMs=${snapshot.position.inMilliseconds} '
        'bufferedMs=${snapshot.buffered.inMilliseconds} aheadMs=${ahead.inMilliseconds} nativeAheadMs=${nativeAhead.inMilliseconds}',
      );
      return snapshot.position + nativeAhead;
    }

    final firstBuffer = await checkWindow('initial');
    await tester.pump(const Duration(seconds: 1));
    await checkWindow('paused');
    await engine.play();
    await _until(
      tester,
      () => engine.currentSnapshot.position >= const Duration(seconds: 4),
    );
    await engine.pause();
    final advancedBuffer = await checkWindow('advanced');
    expect(
      advancedBuffer,
      greaterThan(firstBuffer + const Duration(seconds: 2)),
    );
    await engine.seek(const Duration(seconds: 400));
    await engine.play();
    await _until(
      tester,
      () =>
          engine.currentSnapshot.position >=
          const Duration(milliseconds: 400400),
    );
    await engine.pause();
    await checkWindow('seek');
    if (engine case final MediaKitEngine native) {
      expect(native.inspectDiagnostics().hasDecodedVideo, isTrue);
    }
    if (engine case final MediaKitEngine native) {
      expect(native.inspectDiagnostics().hasDecodedAudio, isTrue);
    }
    expect(engine.currentSnapshot.videoDimensions, isNotNull);
    expect(rangeRequests, containsAll(['/video.mp4', '/audio.m4a']));

    await engine.open(
      DashPairSource(
        video: track('/short.mp4'),
        audio: null,
        isIntentionallySilent: true,
      ),
      const OpenOptions(volume: 0),
    );
    await _until(
      tester,
      () => engine.currentSnapshot.buffered >= const Duration(seconds: 58),
    );
    expect(
      engine.currentSnapshot.duration,
      lessThan(const Duration(minutes: 2)),
    );
    expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
    expect(tester.takeException(), isNull);
    // Release the real Video/Focus subtree before the integration binding
    // verifies that no semantics handles remain alive.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(condition(), isTrue, reason: 'Native buffer did not reach its window');
}
