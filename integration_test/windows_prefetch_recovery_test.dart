import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/native_player_properties.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
// Native regressions inspect and inject the pinned SDK's existing error route.
// ignore: depend_on_referenced_packages
import 'package:media_kit_video/media_kit_video.dart' as mkv;
// ignore: depend_on_referenced_packages
import 'package:media_kit/media_kit.dart' as mk;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('cached DASH survives SDK network errors and decode logs', (
    tester,
  ) async {
    initializePlayerBackend();
    final directory = Platform.environment['BILI_TEST_BUFFER_DIR'];
    expect(directory, isNotNull, reason: 'Use tool/test-windows-buffer.ps1');
    final media = {
      '/video.mp4': await File('$directory/video.mp4').readAsBytes(),
      '/audio.m4a': await File('$directory/audio.m4a').readAsBytes(),
    };
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serving = server.listen((request) async {
      final bytes = media[request.uri.path];
      if (bytes == null) {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      final match = RegExp(r'^bytes=(\d+)-(\d*)$')
          .firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
      final start = int.tryParse(match?[1] ?? '') ?? 0;
      final response = request.response;
      if (start >= bytes.length) {
        response.statusCode = 416;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes */${bytes.length}',
        );
        await response.close();
        return;
      }
      final end = (int.tryParse(match?[2] ?? '') ?? bytes.length - 1).clamp(
        start,
        bytes.length - 1,
      );
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.contentLength = end - start + 1;
      if (match != null) {
        response.statusCode = 206;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${bytes.length}',
        );
      }
      try {
        response.add(bytes.sublist(start, end + 1));
        await response.close();
      } on IOException {
        // Recovery cancels the retired source's outstanding requests.
      }
    });
    MediaTrack track(String path) => MediaTrack(
      uri: Uri.parse('http://127.0.0.1:${server.port}$path'),
      requestPolicy: MediaRequestPolicy(),
    );
    final source = DashPairSource(
      video: track('/video.mp4'),
      audio: track('/audio.m4a'),
    );
    final events = <PlayerDiagnosticEvent>[];
    final failures = <Duration>[];
    final engine = MediaKitEngine(onDiagnostic: events.add);
    final subscription = engine.failures.listen((_) {
      failures.add(
        engine.currentSnapshot.buffered - engine.currentSnapshot.position,
      );
    });
    final session = PlaybackSession(
      engine: engine,
      repository: _Repository(source),
      progress: _Progress(),
      accountScope: () => 'guest',
    )..configureSettings(AppSettings(autoPlay: true, resumePlayback: false));
    try {
      await tester.pumpWidget(MaterialApp(home: VideoSurface(engine: engine)));
      await _frames(tester, session.open(_detail, _part, volume: 0));
      await _until(
        tester,
        () =>
            engine.currentSnapshot.position >
                const Duration(milliseconds: 300) &&
            engine.currentSnapshot.buffered - engine.currentSnapshot.position >
                const Duration(seconds: 10),
      );
      expect(failures, isEmpty);
      final generation = engine.currentSnapshot.generation;
      final before = engine.currentSnapshot.position;
      final player = tester
          .widget<mkv.Video>(find.byType(mkv.Video))
          .controller
          .player;
      expect(await player.getPropertyAsync('demuxer-max-bytes'), '4194304');
      expect(
        await player.getPropertyAsync('demuxer-max-back-bytes'),
        '4194304',
      );
      expect(double.parse(await player.getPropertyAsync('cache-secs')), 16);
      expect(
        double.parse(await player.getPropertyAsync('demuxer-hysteresis-secs')),
        closeTo(16 / 1.5, .001),
      );
      // Exercise the pinned SDK's actual streams while native packets can play.
      // ignore: invalid_use_of_protected_member
      player.native.errorController.add('tcp: ffurl_read returned 0xffffff99');
      // ignore: invalid_use_of_protected_member
      player.native.logController.add(
        mk.PlayerLog(
          prefix: 'vd',
          level: 'warn',
          text: 'Error while decoding frame (hardware decoding)!',
        ),
      );
      await tester.pump(const Duration(seconds: 4));
      expect(failures, isEmpty);
      expect(engine.currentSnapshot.generation, generation);
      expect(engine.currentSnapshot.position, greaterThan(before));
      expect(engine.inspectDiagnostics().hasDecodedAudio, true);
      expect(engine.inspectDiagnostics().hasDecodedVideo, true);
      expect(
        events.any((e) => e.kind == PlayerDiagnosticKind.nativeError),
        true,
      );
      expect(session.error, isNull);
    } finally {
      await subscription.cancel();
      await _frames(tester, session.close());
      await tester.pumpWidget(const SizedBox.shrink());
      await serving.cancel();
      await server.close(force: true);
    }
  });
}

const _part = VideoPart(
  cid: 'prefetch',
  page: 1,
  title: 'prefetch',
  duration: Duration(minutes: 12),
);
final _detail = VideoDetail(
  summary: VideoSummary(
    id: VideoId('BV1234567890'),
    title: 'prefetch',
    coverUrl: '',
    author: '',
    duration: _part.duration,
  ),
  description: '',
  parts: const [_part],
);

final class _Repository implements PlaybackRepository {
  _Repository(this.source);
  final DashPairSource source;
  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => PlaybackMedia(
    video: PlaybackTrack(
      urls: [source.video.uri],
      codec: 'avc1',
      bandwidth: 1000,
    ),
    audio: PlaybackTrack(
      urls: [source.audio!.uri],
      codec: 'mp4a',
      bandwidth: 128,
    ),
    quality: quality,
    qualities: [quality],
    duration: _part.duration,
    headers: const {},
  );
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

Future<void> _frames(WidgetTester tester, Future<void> operation) async {
  var done = false;
  final result = operation.whenComplete(() => done = true);
  while (!done) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await result;
}

Future<void> _until(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final watch = Stopwatch()..start();
  while (!condition() && watch.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(condition(), true, reason: 'Prefetch did not recover in time');
}
