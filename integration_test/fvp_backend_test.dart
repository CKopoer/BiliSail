import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final liveDirectory = Platform.environment['BILI_FVP_LIVE_MEDIA_DIR'];

  testWidgets(
    'fvp live FLV and HLS render without seeking and retain headers',
    (tester) async {
      initializePlayerBackend();
      final server = await _FixtureServer.start(
        Platform.environment['BILI_TEST_MEDIA_DIR']!,
        liveDirectory: liveDirectory,
      );
      final engine = FvpEngine();
      MediaTrack track(String path) => MediaTrack(
        uri: Uri.parse('http://127.0.0.1:${server.port}/$path'),
        requestPolicy: MediaRequestPolicy(
          headers: {'Referer': 'https://www.bilibili.com/'},
        ),
      );
      try {
        await tester.pumpWidget(
          MaterialApp(home: VideoSurface(engine: engine)),
        );
        for (final source in [
          ProgressiveSource(track('live.flv'), isLive: true),
          ManifestSource(track('live.m3u8'), isLive: true),
        ]) {
          await engine.open(source, const OpenOptions(play: true, volume: 0));
          expect(engine.currentSnapshot.videoDimensions, isNotNull);
          expect(engine.currentSnapshot.duration, Duration.zero);
          await Future<void>.delayed(const Duration(seconds: 1));
          expect(engine.currentSnapshot.position, greaterThan(Duration.zero));
          expect(server.wrongHeaders, 0);
          await engine.pause();
          expect(engine.currentSnapshot.desiredPlaying, false);
        }
      } finally {
        await engine.dispose();
        await server.close();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
    skip: liveDirectory == null,
  );

  testWidgets('MDK native audio sanity', (tester) async {
    initializePlayerBackend();
    final file = File(
      '${Platform.environment['BILI_TEST_MEDIA_DIR']}/audio.m4a',
    );
    final source = ProgressiveSource(
      MediaTrack(uri: file.uri, requestPolicy: MediaRequestPolicy()),
      isAudioOnly: true,
    );
    final primary = MediaKitEngine();
    await primary.open(source, const OpenOptions(volume: 0));
    await primary.dispose();
    final engine = FvpEngine();
    try {
      await engine.open(
        source,
        const OpenOptions(
          play: true,
          volume: 0,
          openTimeout: Duration(seconds: 5),
        ),
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(engine.currentSnapshot.position, greaterThan(Duration.zero));
      final info = await engine.inspectPlaybackInformation();
      expect(info?.audioCodec, 'aac');
      expect(info?.diagnostics?.audioSampleRate, 48000);
      expect(info?.diagnostics?.audioChannels, greaterThan(0));
      expect(info?.diagnostics?.hasDecodedAudio, true);
      expect(info?.audioNominalBitrate, greaterThan(0));
      expect(info?.videoCodec, isNull);
    } finally {
      await engine.dispose();
    }
  });

  testWidgets(
    'native backend switching retains a single DASH clock, headers and surface',
    (tester) async {
      initializePlayerBackend();
      final fixtures = Platform.environment['BILI_TEST_MEDIA_DIR'];
      expect(fixtures, isNotNull);
      final server = await _FixtureServer.start(fixtures!);
      final requests = server.requests;
      var useFvp = false;
      final engine = ConfigurablePlayerEngine(
        createEngine: () async => useFvp ? FvpEngine() : MediaKitEngine(),
      );
      final failures = <PlayerFailure>[];
      final subscription = engine.failures.listen(failures.add);
      MediaTrack track(String path) => MediaTrack(
        uri: Uri.parse('http://127.0.0.1:${server.port}$path'),
        requestPolicy: MediaRequestPolicy(
          headers: {'Referer': 'https://www.bilibili.com/'},
        ),
      );
      final source = DashPairSource(
        video: track('/video.mp4'),
        audio: track('/audio.m4a'),
      );
      try {
        await tester.pumpWidget(
          MaterialApp(home: VideoSurface(engine: engine)),
        );
        for (final backend in [false, true, false, true]) {
          useFvp = backend;
          requests.clear();
          failures.clear();
          await engine.open(source, const OpenOptions(volume: 0));
          expect(engine.currentSnapshot.videoDimensions, isNotNull);
          expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
          expect(requests, containsAll(['/video.mp4', '/audio.m4a']));
          expect(server.wrongHeaders, 0);
          await engine.play();
          await tester.pump(const Duration(seconds: 1));
          await Future<void>.delayed(const Duration(milliseconds: 600));
          expect(engine.currentSnapshot.position, greaterThan(Duration.zero));
          if (useFvp) {
            final info = await engine.inspectPlaybackInformation();
            expect(info?.generation, engine.currentSnapshot.generation);
            expect(info?.videoCodec, 'h264');
            expect(info?.audioCodec, 'aac');
            expect(info?.hardwareDecoder, isNotNull);
            expect(info?.sourceFps, greaterThan(0));
            expect(info?.pixelFormat, isNotNull);
            expect(info?.diagnostics?.videoWidth, 320);
            expect(info?.diagnostics?.outputWidth, 320);
            expect(info?.diagnostics?.audioSampleRate, 48000);
            expect(info?.diagnostics?.hasDecodedVideo, true);
            expect(info?.diagnostics?.hasVideoOutput, true);
            expect(info?.diagnostics?.hasDecodedAudio, true);
            expect(info?.cacheSeconds, greaterThanOrEqualTo(0));
            expect(info?.audioNominalBitrate, greaterThan(0));
            expect(info?.avSyncSeconds, isNull);
            expect(info?.frameDrops, isNull);
          }
          await engine.setRate(2);
          await engine.pause();
          await engine.seek(const Duration(seconds: 3));
          expect(
            engine.currentSnapshot.position.inMilliseconds,
            closeTo(3000, 600),
          );
          expect(engine.currentSnapshot.desiredPlaying, false);
          expect(failures, isEmpty);
          // Move the same output into a new surface owner without reopening.
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: VideoSurface(key: UniqueKey(), engine: engine),
              ),
            ),
          );
          await tester.pump();
        }
        useFvp = true;
        for (final audio in ['/video.mp4', '/missing.m4a']) {
          await expectLater(
            engine.open(
              DashPairSource(video: source.video, audio: track(audio)),
              const OpenOptions(volume: 0, openTimeout: Duration(seconds: 8)),
            ),
            throwsA(isA<PlayerFailure>()),
          );
        }
        requests.clear();
        await engine.open(
          ProgressiveSource(track('/audio.m4a'), isAudioOnly: true),
          const OpenOptions(play: true, volume: 0),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(requests, isNot(contains('/video.mp4')));
        expect(engine.currentSnapshot.videoDimensions, isNull);
      } finally {
        await engine.dispose();
        await subscription.cancel();
        await server.close();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );
}

// Keep the fixture's HTTP loop independent of synchronous native FFI calls.
final class _FixtureServer {
  _FixtureServer(
    this.port,
    this._isolate,
    this._events,
    this._subscription,
    this.requests,
    this._wrongHeaders,
  );
  final int port;
  final Isolate _isolate;
  final ReceivePort _events;
  final StreamSubscription<Object?> _subscription;
  final List<String> requests;
  final List<bool> _wrongHeaders;
  int get wrongHeaders => _wrongHeaders.length;

  static Future<_FixtureServer> start(
    String fixtures, {
    String? liveDirectory,
  }) async {
    final events = ReceivePort();
    final started = Completer<int>();
    final requests = <String>[];
    final wrongHeaders = <bool>[];
    final subscription = events.listen((message) {
      if (message is int) {
        started.complete(message);
      } else if (message is String) {
        requests.add(message);
      } else if (message == false) {
        wrongHeaders.add(false);
      }
    });
    final isolate = await Isolate.spawn(_serveFixtures, (
      events.sendPort,
      fixtures,
      liveDirectory,
    ));
    return _FixtureServer(
      await started.future.timeout(const Duration(seconds: 5)),
      isolate,
      events,
      subscription,
      requests,
      wrongHeaders,
    );
  }

  Future<void> close() async {
    _isolate.kill(priority: Isolate.immediate);
    await _subscription.cancel();
    _events.close();
  }
}

Future<void> _serveFixtures((SendPort, String, String?) arguments) async {
  final (events, directory, liveDirectory) = arguments;
  final files = {
    '/video.mp4': await File('$directory/video.mp4').readAsBytes(),
    '/audio.m4a': await File('$directory/audio.m4a').readAsBytes(),
  };
  if (liveDirectory != null) {
    await for (final entry in Directory(liveDirectory).list()) {
      if (entry is File) {
        files['/${entry.uri.pathSegments.last}'] = await entry.readAsBytes();
      }
    }
  }
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  events.send(server.port);
  await for (final request in server) {
    events.send(request.uri.path);
    final bytes = files[request.uri.path];
    if (request.headers.value('referer') != 'https://www.bilibili.com/') {
      events.send(false);
      request.response.statusCode = 403;
    } else if (bytes == null) {
      request.response.statusCode = 404;
    } else {
      final range = RegExp(r'^bytes=(\d+)-(\d*)$')
          .firstMatch(request.headers.value('range') ?? '');
      final start = int.tryParse(range?.group(1) ?? '') ?? 0;
      final end = (int.tryParse(range?.group(2) ?? '') ?? bytes.length - 1)
          .clamp(0, bytes.length - 1);
      if (start > end) {
        request.response.statusCode = 416;
      } else {
        request.response.headers.set('Accept-Ranges', 'bytes');
        request.response.headers.contentType = switch (request.uri.path) {
          final path when path.endsWith('.m3u8') => ContentType(
            'application',
            'vnd.apple.mpegurl',
          ),
          final path when path.endsWith('.ts') => ContentType('video', 'mp2t'),
          final path when path.endsWith('.flv') => ContentType(
            'video',
            'x-flv',
          ),
          final path when path.endsWith('.m4a') => ContentType('audio', 'mp4'),
          _ => ContentType('video', 'mp4'),
        };
        if (range != null) {
          request.response.statusCode = 206;
          request.response.headers.set(
            'Content-Range',
            'bytes $start-$end/${bytes.length}',
          );
        }
        request.response.contentLength = end - start + 1;
        request.response.add(bytes.sublist(start, end + 1));
      }
    }
    await request.response.close();
  }
}
