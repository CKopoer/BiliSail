import 'package:bili_player/src/fvp_audio_end.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('container timestamp offsets cannot hide a truncated audio track', () {
    for (final sample in [
      (endpoint: 42009, complete: true),
      (endpoint: 36634, complete: false),
    ]) {
      final position = fvpAudioEndPosition(
        frameEndMilliseconds: sample.endpoint,
        mediaStartMilliseconds: 29989,
      );
      expect(
        fvpAudioEndedNaturally(
          decodedEndMilliseconds: position,
          audioDurationMilliseconds: 12021,
          videoPositionMilliseconds: 10000,
          videoDurationMilliseconds: 12021,
        ),
        sample.complete,
      );
    }
    expect(
      fvpAudioEndPosition(
        frameEndMilliseconds: -1,
        mediaStartMilliseconds: 29989,
      ),
      -1,
    );
  });

  test('complete audio is natural even while the video position trails', () {
    for (final sample in [
      (video: 43966, duration: 45567),
      (video: 162000, duration: 164000),
      (video: 162766, duration: 164000),
    ]) {
      expect(
        fvpAudioEndedNaturally(
          decodedEndMilliseconds: sample.duration - 20,
          audioDurationMilliseconds: sample.duration,
          videoPositionMilliseconds: sample.video,
          videoDurationMilliseconds: sample.duration,
        ),
        isTrue,
      );
    }
  });

  test('the audio track can have a shorter advertised duration than video', () {
    expect(
      fvpAudioEndedNaturally(
        decodedEndMilliseconds: 163220,
        audioDurationMilliseconds: 163221,
        videoPositionMilliseconds: 162000,
        videoDurationMilliseconds: 164000,
      ),
      isTrue,
    );
  });

  test(
    'truncated audio cannot be hidden by video progress or cached packets',
    () {
      for (final video in [12000, 29980]) {
        expect(
          fvpAudioEndedNaturally(
            decodedEndMilliseconds: 12000,
            audioDurationMilliseconds: 30000,
            videoPositionMilliseconds: video,
            videoDurationMilliseconds: 30000,
          ),
          isFalse,
        );
      }
    },
  );

  test(
    'unknown audio endpoints retain only the existing final-frame fallback',
    () {
      for (final missing in [
        (endpoint: -1, duration: 30000),
        (endpoint: 0, duration: 0),
      ]) {
        for (final video in [12000, 29980]) {
          expect(
            fvpAudioEndedNaturally(
              decodedEndMilliseconds: missing.endpoint,
              audioDurationMilliseconds: missing.duration,
              videoPositionMilliseconds: video,
              videoDurationMilliseconds: 30000,
            ),
            video == 29980,
          );
        }
      }
      expect(
        fvpAudioEndedNaturally(
          decodedEndMilliseconds: -1,
          audioDurationMilliseconds: 0,
          videoPositionMilliseconds: 0,
          videoDurationMilliseconds: 0,
        ),
        isFalse,
      );
    },
  );
}
