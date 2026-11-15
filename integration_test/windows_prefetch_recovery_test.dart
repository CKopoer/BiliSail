import 'dart:convert';
import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/native_player_properties.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/material.dart';
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

  for (final silentRead in [false, true]) {
    testWidgets(
      'network restoration refills DASH before cache runs out; silent=$silentRead',
      (tester) async {
        initializePlayerBackend();
        final directory = Platform.environment['BILI_TEST_BUFFER_DIR'];
        expect(
          directory,
          isNotNull,
          reason: 'Use tool/test-windows-buffer.ps1',
        );
        final media = {
          '/video.mp4': await File('$directory/video.mp4').readAsBytes(),
          '/audio.m4a': await File('$directory/audio.m4a').readAsBytes(),
        };
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final sockets = <Socket>{};
        var offline = false, interrupted = false;
        var probes = 0;
        final serving = server.listen((request) async {
          if (offline) {
            request.response.statusCode = 503;
            await request.response.close();
            return;
          }
          final bytes = media[request.uri.path];
          if (bytes == null) {
            request.response.statusCode = 404;
            await request.response.close();
            return;
          }
          final match = RegExp(r'^bytes=(\d+)-(\d*)$')
              .firstMatch(request.headers.value('range') ?? '');
          final start = int.tryParse(match?[1] ?? '') ?? 0;
          final end = (int.tryParse(match?[2] ?? '') ?? bytes.length - 1).clamp(
            start,
            bytes.length - 1,
          );
          if (start >= bytes.length) {
            request.response.statusCode = 416;
            await request.response.close();
            return;
          }
          final response = request.response;
          response.headers.set('Accept-Ranges', 'bytes');
          response.contentLength = end - start + 1;
          if (match != null) {
            response.statusCode = 206;
            response.headers.set(
              'Content-Range',
              'bytes $start-$end/${bytes.length}',
            );
          }
          final probe = start == 0 && end == 0;
          if (probe) probes++;
          final socket = await response.detachSocket();
          sockets.add(socket);
          try {
            // Enough packets to keep playing throughout native reconnect exhaustion,
            // but not the whole file. Leave this response open until fault injection.
            final stop = !interrupted && !probe
                ? (bytes.length ~/ 5).clamp(start, end + 1)
                : end + 1;
            socket.add(bytes.sublist(start, stop));
            await socket.flush();
            if (stop == end + 1) {
              await socket.close();
              sockets.remove(socket);
            }
          } on IOException {
            sockets.remove(socket);
            socket.destroy();
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
        final engine = MediaKitEngine(
          onDiagnostic: (event) {
            if (event.nativeError case final error?) {
              debugPrint(
                'prefetch native: ${error.cause}, positionMs=${event.snapshot.position.inMilliseconds}, bufferedMs=${event.snapshot.buffered.inMilliseconds}',
              );
            }
          },
        );
        final failures = <Duration>[];
        final subscription = engine.failures.listen((_) {
          failures.add(
            engine.currentSnapshot.buffered - engine.currentSnapshot.position,
          );
        });
        final session =
            PlaybackSession(
              engine: engine,
              repository: _Repository(source),
              progress: _Progress(),
              accountScope: () => 'guest',
            )..configureSettings(
              AppSettings(autoPlay: true, resumePlayback: false),
            );
        try {
          await tester.pumpWidget(
            MaterialApp(home: VideoSurface(engine: engine)),
          );
          await _frames(tester, session.open(_detail, _part, volume: 0));
          await _until(
            tester,
            () =>
                engine.currentSnapshot.buffered -
                    engine.currentSnapshot.position >
                const Duration(seconds: 35),
          );
          final generation = engine.currentSnapshot.generation;
          final before = engine.currentSnapshot.position;
          interrupted = offline = true;
          if (!silentRead) {
            for (final socket in sockets.toList()) {
              socket.destroy();
            }
            sockets.clear();
            // Confirmed HTTP errors use the existing immediate, bounded retry
            // policy. Only a silent read hang waits for origin probes.
            await _until(tester, () => session.error != null);
            expect(failures, hasLength(3));
            expect(failures.every((ahead) => ahead > Duration.zero), true);
            await tester.pump(const Duration(seconds: 2));
            expect(
              failures,
              hasLength(3),
              reason: 'No unbounded offline retries',
            );
            offline = false;
            await _frames(tester, session.retry());
            await _until(
              tester,
              () =>
                  engine.currentSnapshot.position >
                  before + const Duration(seconds: 2),
            );
            expect(session.error, isNull);
            expect(engine.currentSnapshot.desiredPlaying, true);
            expect(engine.inspectDiagnostics().hasDecodedAudio, true);
            expect(engine.inspectDiagnostics().hasDecodedVideo, true);
            expect(tester.takeException(), isNull);
            return;
          }
          // mpv's default HTTP retry waits are 0, 1, 3 and 7 seconds. The gap
          // must remain recoverable after that native read has already given up.
          await tester.pump(const Duration(seconds: 16));
          expect(engine.currentSnapshot.generation, generation);
          expect(
            engine.currentSnapshot.position,
            greaterThan(before + const Duration(seconds: 10)),
          );
          expect(engine.currentSnapshot.isBuffering, false);
          expect(
            failures,
            isEmpty,
            reason: 'Offline probes must not retire playable cache',
          );
          final oldEnd = engine.currentSnapshot.buffered;
          debugPrint(
            'prefetch offline: positionMs=${engine.currentSnapshot.position.inMilliseconds}, endMs=${oldEnd.inMilliseconds}, probes=$probes',
          );
          offline = false;
          await _until(
            tester,
            () =>
                engine.currentSnapshot.buffered >
                oldEnd + const Duration(seconds: 10),
          );
          expect(
            probes,
            greaterThanOrEqualTo(2),
            reason: 'Check both actual DASH origins',
          );
          expect(failures, hasLength(1));
          expect(failures.single, greaterThan(const Duration(seconds: 5)));
          expect(
            engine.currentSnapshot.position,
            greaterThan(before + const Duration(seconds: 10)),
          );
          expect(engine.currentSnapshot.desiredPlaying, true);
          expect(engine.inspectDiagnostics().hasDecodedAudio, true);
          expect(engine.inspectDiagnostics().hasDecodedVideo, true);
          expect(session.error, isNull);
          debugPrint(
            'prefetchRecovery: remainingMs=${failures.single.inMilliseconds}, probes=$probes, bufferedMs=${engine.currentSnapshot.buffered.inMilliseconds}',
          );
          expect(tester.takeException(), isNull);
        } finally {
          debugPrint(
            'prefetch final: positionMs=${engine.currentSnapshot.position.inMilliseconds}, endMs=${engine.currentSnapshot.buffered.inMilliseconds}, probes=$probes, failures=${failures.length}, error=${session.error}',
          );
          await subscription.cancel();
          await _frames(tester, session.close());
          await tester.pumpWidget(const SizedBox.shrink());
          for (final socket in sockets) {
            socket.destroy();
          }
          await serving.cancel();
          await server.close(force: true);
        }
      },
    );
  }

  for (final tlsError in [false, true]) {
    testWidgets(
      'media read failure restores DASH before cache drains; tls=$tlsError',
      (tester) => _runReadFailure(tester, tlsError: tlsError),
    );
  }
}

Future<void> _runReadFailure(
  WidgetTester tester, {
  required bool tlsError,
}) async {
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
          engine.currentSnapshot.position > const Duration(milliseconds: 300) &&
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
    final oldEnd = engine.currentSnapshot.buffered;
    await _frames(tester, engine.setRate(2));
    if (tlsError) {
      // Exercise the SDK error stream separately from its log stream.
      // ignore: invalid_use_of_protected_member
      player.native.errorController.add(
        'TLS certificate verification failed '
        'https://private.test/?token=synthetic-secret',
      );
    } else {
      // Reproduce the early error signal from the incident through the pinned
      // SDK route, after real HTTP DASH decoding/cache readiness. This does not
      // claim that every truncated input emits an early native error.
      // ignore: invalid_use_of_protected_member
      player.native.logController.add(
        mk.PlayerLog(
          prefix: 'ffmpeg/demuxer',
          level: 'error',
          text:
              'stream 0, offset 0x1234: partial file '
              'https://private.test/?pts=10&token=synthetic-secret',
        ),
      );
    }
    await _until(
      tester,
      () =>
          failures.isNotEmpty &&
          engine.currentSnapshot.generation > generation &&
          engine.currentSnapshot.phase == PlaybackPhase.playing &&
          !session.isRecovering &&
          engine.currentSnapshot.position >
              before + const Duration(milliseconds: 300) &&
          engine.currentSnapshot.buffered >
              oldEnd + const Duration(seconds: 10),
    );
    expect(failures, hasLength(1));
    expect(failures.single, greaterThan(const Duration(seconds: 10)));
    expect(
      events.where(
        (e) => e.stallReason == PlaybackStallReason.prefetchReadError,
      ),
      hasLength(1),
    );
    expect(
      events.any(
        (e) => tlsError
            ? e.nativeError?.cause == NativeErrorCause.tls
            : e.nativeError?.detail == NativeErrorDetail.prematureRead &&
                  e.nativeError?.cause == NativeErrorCause.inputOutput,
      ),
      true,
    );
    expect(
      events.any((e) => e.stallReason == PlaybackStallReason.audioDecodeError),
      false,
    );
    expect(
      jsonEncode(events.map((e) => e.toJson()).toList()),
      isNot(contains('synthetic-secret')),
    );
    expect(engine.currentSnapshot.desiredPlaying, true);
    expect(engine.inspectDiagnostics().hasDecodedAudio, true);
    expect(engine.inspectDiagnostics().hasDecodedVideo, true);
    expect(session.error, isNull);
    expect(tester.takeException(), isNull);
    debugPrint(
      'READ_FAILURE_RECOVERY tls=$tlsError '
      'remainingMs=${failures.single.inMilliseconds} '
      'positionMs=${engine.currentSnapshot.position.inMilliseconds} '
      'bufferedMs=${engine.currentSnapshot.buffered.inMilliseconds}',
    );
  } finally {
    debugPrint(
      'READ_FAILURE_FINAL tls=$tlsError '
      'positionMs=${engine.currentSnapshot.position.inMilliseconds} '
      'bufferedMs=${engine.currentSnapshot.buffered.inMilliseconds} '
      'phase=${engine.currentSnapshot.phase} failures=${failures.length} '
      'error=${session.error != null}',
    );
    await subscription.cancel();
    await _frames(tester, session.close());
    await tester.pumpWidget(const SizedBox.shrink());
    await serving.cancel();
    await server.close(force: true);
  }
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

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition() && watch.elapsed < const Duration(seconds: 15)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(condition(), true, reason: 'Prefetch did not recover in time');
}
