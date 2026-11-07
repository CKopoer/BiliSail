import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/native_track_health.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const playing = PlaybackSnapshot(
    phase: PlaybackPhase.playing,
    generation: 1,
    desiredPlaying: true,
    duration: Duration(minutes: 5),
    position: Duration(seconds: 10),
  );
  late NativeTrackHealth health;
  setUp(() => health = NativeTrackHealth());

  for (final missingAudio in [false, true]) {
    for (final buffering in [false, true]) {
      test(
        'missing ${missingAudio ? 'audio' : 'video'} stops the pair in 2s; buffering=$buffering',
        () {
          for (var i = 0; i <= 6; i++) {
            final result = health.update(
              playing.copyWith(
                isBuffering: buffering,
                position: Duration(
                  milliseconds: 10000 + (missingAudio ? i * 250 : 0),
                ),
              ),
              Duration(milliseconds: i * 250),
              requiresAudio: true,
              requiresVideo: true,
              audioFrames: missingAudio ? 100 : 100 + i,
              videoPosition: Duration(
                milliseconds: 10000 + (missingAudio ? i * 250 : 0),
              ),
            );
            if (i < 6) {
              expect(result, isNull);
            } else {
              expect(
                result?.reason,
                missingAudio
                    ? PlaybackStallReason.audioFrames
                    : PlaybackStallReason.videoClock,
              );
              expect(
                result!.stalledFor,
                lessThanOrEqualTo(const Duration(seconds: 2)),
              );
            }
          }
        },
      );
    }
  }
  test('native video queue starvation uses the same companion deadline', () {
    for (var i = 0; i <= 6; i++) {
      final result = health.update(
        playing,
        Duration(milliseconds: i * 250),
        requiresAudio: true,
        requiresVideo: true,
        audioFrames: i,
        videoStarved: true,
      );
      expect(result?.reason, i < 6 ? isNull : PlaybackStallReason.videoBuffer);
    }
  });
  test('a synchronized native refill can wait and resume without a reopen', () {
    final buffering = playing.copyWith(isBuffering: true);
    for (var i = 0; i <= 100; i++) {
      expect(
        health.update(
          buffering,
          Duration(milliseconds: i * 250),
          requiresAudio: true,
          requiresVideo: true,
          audioFrames: 10,
          videoPosition: playing.position,
        ),
        isNull,
      );
    }
    for (var i = 0; i < 8; i++) {
      expect(
        health.update(
          playing.copyWith(position: Duration(milliseconds: 10000 + i * 250)),
          Duration(milliseconds: 25250 + i * 250),
          requiresAudio: true,
          requiresVideo: true,
          audioFrames: 10 + i,
          videoPosition: Duration(milliseconds: 10000 + i * 250),
        ),
        isNull,
      );
    }
  });
  test('cached video is not evidence of video advancing during buffering', () {
    for (var i = 0; i < 100; i++) {
      expect(
        health.update(
          playing.copyWith(isBuffering: true),
          Duration(milliseconds: i * 250),
          requiresAudio: true,
          requiresVideo: true,
          audioFrames: 100,
          videoPosition: playing.position,
          videoStarved: false,
        ),
        isNull,
      );
    }
  });
  for (final rate in [.25, 1.0, 4.0, 8.0]) {
    test(
      'silent PCM at zero volume and rate $rate does not imply interruption',
      () {
        for (var i = 0; i < 100; i++) {
          expect(
            health.update(
              playing.copyWith(rate: rate, volume: 0),
              Duration(milliseconds: i * 250),
              requiresAudio: true,
              requiresVideo: true,
              audioFrames: i,
              videoPosition: Duration(
                microseconds: 10000000 + (i * 250000 * rate).round(),
              ),
            ),
            isNull,
          );
        }
      },
    );
  }
  test('clock jitter does not conceal missing audio at quarter speed', () {
    for (var i = 0; i <= 6; i++) {
      final result = health.update(
        playing,
        Duration(milliseconds: i * 250),
        requiresAudio: true,
        requiresVideo: true,
        audioPosition: Duration(milliseconds: 10000 + (i.isOdd ? 10 : 0)),
        videoPosition: Duration(microseconds: 10000000 + i * 62500),
      );
      expect(result?.reason, i < 6 ? isNull : PlaybackStallReason.audioClock);
    }
  });
  test('paused intent, seeks, source changes and reset retire deadlines', () {
    for (final inactive in [
      playing.copyWith(desiredPlaying: false),
      playing.copyWith(isSeeking: true),
      playing.copyWith(phase: PlaybackPhase.ended),
    ]) {
      health.update(
        playing,
        Duration.zero,
        requiresAudio: true,
        requiresVideo: true,
        audioFrames: 5,
        videoPosition: playing.position,
      );
      expect(
        health.update(
          inactive,
          const Duration(seconds: 30),
          requiresAudio: true,
          requiresVideo: true,
          audioFrames: 5,
          videoPosition: playing.position,
        ),
        isNull,
      );
    }
    health.reset();
    expect(
      health.update(
        playing.copyWith(generation: 2),
        const Duration(seconds: 60),
        requiresAudio: true,
        requiresVideo: true,
        audioFrames: 0,
        videoPosition: playing.position,
      ),
      isNull,
    );
  });
  test(
    'intentionally silent video and audio-only sources need no companion',
    () {
      for (var i = 0; i < 40; i++) {
        expect(
          health.update(
            playing,
            Duration(milliseconds: i * 250),
            requiresAudio: false,
            requiresVideo: true,
            videoPosition: Duration(milliseconds: i * 250),
          ),
          isNull,
        );
      }
      health.reset();
      for (var i = 0; i < 40; i++) {
        expect(
          health.update(
            playing,
            Duration(milliseconds: i * 250),
            requiresAudio: true,
            requiresVideo: false,
            audioFrames: i,
          ),
          isNull,
        );
      }
    },
  );
}
