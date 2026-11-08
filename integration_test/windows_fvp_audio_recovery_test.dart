import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/fvp_native_player.dart';
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
  for (final audioFault in [false, true]) {
    for (final automatic in [false, true]) {
      testWidgets(
        'fvp mid-play ${audioFault ? 'audio' : 'video'} EOF; automatic=$automatic',
        (tester) async {
          final directory = Platform.environment['BILI_FVP_LIVE_MEDIA_DIR']!;
          MediaTrack track(String file) => MediaTrack(
            uri: File('$directory/$file').uri,
            requestPolicy: MediaRequestPolicy(),
          );
          final source = DashPairSource(
            video: track(audioFault ? 'long-video.mp4' : 'truncated-video.mp4'),
            audio: track(audioFault ? 'truncated-audio.m4a' : 'long-audio.m4a'),
          );
          final events = <PlayerDiagnosticEvent>[];
          final failures = <PlayerFailure>[];
          final ports = <FvpPlayerPort>[];
          final engine = FvpEngine(
            onDiagnostic: events.add,
            createPlayer: () async {
              final player = await createInProcessFvpNativePlayer();
              ports.add(player);
              return player;
            },
          );
          final subscription = engine.failures.listen(failures.add);
          final repository = _Repository(
            source,
            DashPairSource(
              video: track('long-video.mp4'),
              audio: track('long-audio.m4a'),
            ),
          );
          final session = automatic
              ? PlaybackSession(
                  engine: engine,
                  repository: repository,
                  progress: _Progress(),
                  accountScope: () => 'guest',
                )
              : null;
          session?.configureSettings(
            AppSettings(autoPlay: true, resumePlayback: false),
          );
          try {
            await tester.pumpWidget(
              MaterialApp(home: VideoSurface(engine: engine)),
            );
            await _withFrames(
              tester,
              session == null
                  ? engine.open(
                      source,
                      const OpenOptions(play: true, volume: 0),
                    )
                  : session.open(_detail, _part, volume: 0),
            );
            final first = ports.single as FvpAudioActivityPort;
            expect(
              first.decodedAudioFrames,
              greaterThan(0),
              reason: 'The actual external audio played before failing',
            );
            final initialFrames = first.decodedAudioFrames;
            await tester.pump(const Duration(seconds: 1));
            expect(first.decodedAudioFrames, greaterThan(initialFrames));
            final watch = Stopwatch()..start();
            while (failures.isEmpty &&
                watch.elapsed < const Duration(seconds: 20)) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            expect(
              failures,
              hasLength(1),
              reason: 'Surviving video must not conceal premature audio EOF',
            );
            final stall = events.singleWhere(
              (event) => event.kind == PlayerDiagnosticKind.playbackStalled,
            );
            expect(
              stall.stallReason,
              audioFault
                  ? PlaybackStallReason.audioClock
                  : isIn([
                      PlaybackStallReason.videoClock,
                      PlaybackStallReason.videoBuffer,
                      PlaybackStallReason.playbackClock,
                    ]),
            );
            expect(
              stall.snapshot.position,
              greaterThan(const Duration(seconds: 2)),
            );
            expect(
              stall.snapshot.position,
              lessThan(const Duration(seconds: 25)),
            );
            expect(stall.stalledFor!.inMilliseconds, inInclusiveRange(0, 2000));
            if (session != null) {
              watch.reset();
              while ((ports.length < 2 ||
                      engine.currentSnapshot.phase != PlaybackPhase.playing ||
                      engine.currentSnapshot.position <=
                          stall.snapshot.position +
                              const Duration(seconds: 1)) &&
                  watch.elapsed < const Duration(seconds: 12)) {
                await tester.pump(const Duration(milliseconds: 100));
              }
              expect(ports, hasLength(2));
              expect(repository.opens, 2);
              expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
              expect(engine.currentSnapshot.desiredPlaying, isTrue);
              expect(session.error, isNull);
              expect(
                engine.currentSnapshot.position,
                greaterThan(stall.snapshot.position),
              );
              final recovered = ports.last as FvpAudioActivityPort;
              final recoveredFrames = recovered.decodedAudioFrames;
              await tester.pump(const Duration(seconds: 1));
              expect(
                recovered.decodedAudioFrames,
                greaterThan(recoveredFrames),
                reason: 'The replacement audio pipeline really decodes again',
              );
              expect(failures, hasLength(1));
            } else {
              expect(engine.currentSnapshot.phase, PlaybackPhase.failed);
              expect(engine.currentSnapshot.desiredPlaying, isFalse);
              await tester.pump(const Duration(milliseconds: 300));
              final audioStopped = first.decodedAudioFrames;
              final stoppedAt = engine.currentSnapshot.position;
              await tester.pump(const Duration(milliseconds: 500));
              expect(first.decodedAudioFrames, audioStopped);
              expect(engine.currentSnapshot.position, stoppedAt);
            }
            debugPrint(
              'FVP_TRACK_EOF audioFault=$audioFault automatic=$automatic stalledAt=${stall.snapshot.position.inMilliseconds} '
              'waited=${stall.stalledFor!.inMilliseconds} opens=${ports.length}',
            );
          } finally {
            await subscription.cancel();
            await _withFrames(tester, session?.close() ?? engine.dispose());
            await tester.pumpWidget(const SizedBox.shrink());
          }
        },
      );
    }
  }
}

const _part = VideoPart(
  cid: 'audio-fixture',
  page: 1,
  title: 'fixture',
  duration: Duration(seconds: 30),
);
final _detail = VideoDetail(
  summary: VideoSummary(
    id: VideoId('BV1234567890'),
    title: 'fixture',
    coverUrl: '',
    author: '',
    duration: _part.duration,
  ),
  description: '',
  parts: const [_part],
);

final class _Repository implements PlaybackRepository {
  _Repository(this.source, this.backup);
  final DashPairSource source;
  final DashPairSource backup;
  int opens = 0;
  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async {
    opens++;
    return PlaybackMedia(
      video: PlaybackTrack(
        urls: [opens == 1 ? source.video.uri : backup.video.uri],
        codec: 'avc1',
        bandwidth: 1000,
      ),
      audio: PlaybackTrack(
        urls: [opens == 1 ? source.audio!.uri : backup.audio!.uri],
        codec: 'mp4a',
        bandwidth: 128,
      ),
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

Future<void> _withFrames(WidgetTester tester, Future<void> operation) async {
  var done = false;
  final result = operation.whenComplete(() => done = true);
  while (!done) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await result;
}
