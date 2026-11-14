import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('repeated DASH underruns switch to the healthy backup at 2x', (
    tester,
  ) async {
    initializePlayerBackend();
    final directory = Platform.environment['BILI_TEST_BUFFER_DIR'];
    expect(directory, isNotNull, reason: 'Use tool/test-windows-buffer.ps1');
    final root = Directory(directory!).uri;
    final files = <String, Uint8List>{};
    final stops = <String, List<int>>{};
    for (final name in ['video.mp4', 'audio.m4a']) {
      final file = File.fromUri(root.resolve(name));
      files[name] = await file.readAsBytes();
      final result = await Process.run('ffprobe', [
        '-v',
        'error',
        '-show_packets',
        '-show_entries',
        'packet=pts_time,pos,size',
        '-of',
        'json',
        file.path,
      ]);
      expect(result.exitCode, 0);
      final data = jsonDecode(result.stdout as String) as Map<String, Object?>;
      final packets = (data['packets'] as List<Object?>)
          .cast<Map<String, Object?>>();
      stops[name] = [
        for (final second in [4, 8])
          packets
              .where((p) => double.parse(p['pts_time'] as String) < second)
              .map(
                (p) =>
                    int.parse(p['pos'] as String) +
                    int.parse(p['size'] as String),
              )
              .reduce((a, b) => a > b ? a : b),
      ];
    }
    final burst = Completer<void>(), finish = Completer<void>();
    final sockets = <Socket>{};
    var badRequests = 0, goodRequests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serving = server.listen((request) async {
      final parts = request.uri.pathSegments;
      if (parts.length != 2 || !files.containsKey(parts.last)) {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      final bad = parts.first == 'bad';
      if (bad) {
        badRequests++;
      } else {
        goodRequests++;
      }
      final bytes = files[parts.last]!;
      final match = RegExp(r'^bytes=(\d+)-(\d*)$')
          .firstMatch(request.headers.value('range') ?? '');
      final start = int.tryParse(match?[1] ?? '') ?? 0;
      final end = (int.tryParse(match?[2] ?? '') ?? bytes.length - 1).clamp(
        start,
        bytes.length - 1,
      );
      final response = request.response;
      response.contentLength = end - start + 1;
      response.headers.set('Accept-Ranges', 'bytes');
      if (match != null) {
        response.statusCode = 206;
        response.headers.set(
          'Content-Range',
          'bytes $start-$end/${bytes.length}',
        );
      }
      final socket = await response.detachSocket();
      sockets.add(socket);
      try {
        var offset = start;
        if (bad && end > start) {
          final limits = stops[parts.last]!;
          final first = limits.first.clamp(offset, end + 1);
          socket.add(bytes.sublist(offset, first));
          await socket.flush();
          offset = first;
          await burst.future;
          final second = limits.last.clamp(offset, end + 1);
          socket.add(bytes.sublist(offset, second));
          await socket.flush();
          offset = second;
          await finish.future;
        }
        socket.add(bytes.sublist(offset, end + 1));
        await socket.flush();
        await socket.close();
      } on IOException {
        // Recovery/cleanup intentionally stops the previous native HTTP reader.
      } finally {
        sockets.remove(socket);
        socket.destroy();
      }
    });
    final repository = _Repository(server.port);
    final diagnostics = <PlayerDiagnosticEvent>[];
    final engine = MediaKitEngine(onDiagnostic: diagnostics.add);
    final session = PlaybackSession(
      engine: engine,
      repository: repository,
      progress: _Progress(),
      accountScope: () => 'guest',
    )..configureSettings(AppSettings(autoPlay: true, resumePlayback: false));
    try {
      await tester.pumpWidget(MaterialApp(home: VideoSurface(engine: engine)));
      await _frames(tester, session.open(_detail, _part, rate: 2, volume: 0));
      await _until(
        tester,
        () =>
            engine.currentSnapshot.isBuffering &&
            engine.currentSnapshot.position > const Duration(seconds: 1),
      );
      final firstPosition = engine.currentSnapshot.position;
      await tester.pump(const Duration(seconds: 7));
      expect(
        repository.resolutions,
        1,
        reason: 'One gap must keep its connection',
      );
      expect(
        diagnostics.any((e) => e.nativeState?.pausedForCache == true),
        true,
      );
      burst.complete();
      await _until(
        tester,
        () =>
            !engine.currentSnapshot.isBuffering &&
            engine.currentSnapshot.position > firstPosition,
      );
      await _until(
        tester,
        () =>
            engine.currentSnapshot.isBuffering &&
            engine.currentSnapshot.position >
                firstPosition + const Duration(seconds: 2),
      );
      final secondPosition = engine.currentSnapshot.position;
      await _until(
        tester,
        () =>
            repository.resolutions == 2 &&
            !engine.currentSnapshot.isBuffering &&
            engine.currentSnapshot.position >
                secondPosition + const Duration(seconds: 4),
      );
      expect(session.error, isNull);
      expect(engine.currentSnapshot.rate, 2);
      expect(engine.currentSnapshot.desiredPlaying, true);
      expect(engine.inspectDiagnostics().hasDecodedAudio, true);
      expect(engine.inspectDiagnostics().hasDecodedVideo, true);
      expect(
        diagnostics.where(
          (e) => e.stallReason == PlaybackStallReason.repeatedCacheUnderrun,
        ),
        hasLength(1),
      );
      expect(
        diagnostics.where((e) => e.kind == PlayerDiagnosticKind.failed),
        hasLength(1),
      );
      expect(badRequests, 2);
      expect(goodRequests, 2);
      debugPrint(
        'REBUFFER_RECOVERED firstMs=${firstPosition.inMilliseconds} '
        'secondMs=${secondPosition.inMilliseconds} '
        'resumedMs=${engine.currentSnapshot.position.inMilliseconds} '
        'bad=$badRequests good=$goodRequests resolves=${repository.resolutions}',
      );
      expect(tester.takeException(), isNull);
    } finally {
      if (!burst.isCompleted) burst.complete();
      if (!finish.isCompleted) finish.complete();
      await _frames(tester, session.close());
      await tester.pumpWidget(const SizedBox.shrink());
      for (final socket in sockets.toList()) {
        socket.destroy();
      }
      await serving.cancel();
      await server.close(force: true);
    }
  });
}

const _part = VideoPart(
  cid: 'rebuffer',
  page: 1,
  title: 'rebuffer',
  duration: Duration(minutes: 12),
);
final _detail = VideoDetail(
  summary: VideoSummary(
    id: VideoId('BV1234567890'),
    title: 'rebuffer',
    coverUrl: '',
    author: '',
    duration: _part.duration,
  ),
  description: '',
  parts: const [_part],
);

final class _Repository implements PlaybackRepository {
  _Repository(this.port);
  final int port;
  int resolutions = 0;
  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async {
    resolutions++;
    PlaybackTrack track(String name, String codec) => PlaybackTrack(
      urls: [
        for (final origin in ['bad', 'good'])
          Uri.parse('http://127.0.0.1:$port/$origin/$name'),
      ],
      codec: codec,
      bandwidth: 100000,
    );
    return PlaybackMedia(
      video: track('video.mp4', 'avc1'),
      audio: track('audio.m4a', 'mp4a'),
      quality: quality,
      qualities: [quality],
      duration: _part.duration,
      headers: const {},
    );
  }

  @override
  Future<List<TimedComment>> comments(
    String cid,
    int segment, {
    required RequestCancellation cancellation,
  }) async => [];
  @override
  Future<List<SubtitleTrack>> subtitles(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  }) async => [];
  @override
  Future<List<SubtitleCue>> subtitleCues(
    SubtitleTrack track, {
    required RequestCancellation cancellation,
  }) async => [];
}

final class _Progress implements PlaybackProgressStore {
  @override
  Future<Duration?> read(String scope, VideoId video, String cid) async => null;
  @override
  Future<void> write(
    String scope,
    VideoSummary video,
    VideoPart part,
    Duration position,
    Duration duration, {
    String? episodeId,
  }) async {}
}

Future<void> _frames(WidgetTester tester, Future<void> work) async {
  var done = false;
  final result = work.whenComplete(() => done = true);
  while (!done) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await result;
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final watch = Stopwatch()..start();
  while (!ready() && watch.elapsed < const Duration(seconds: 18)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(ready(), true, reason: 'Native DASH rebuffer loop did not recover');
}
