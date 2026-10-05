import 'package:bili_api/bili_api.dart';
import 'package:bili_lite/domain/app_failure.dart';
import 'package:bili_lite/features/playback/data/dash_media_selection.dart';
import 'package:bili_lite/features/playback/domain/playback_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PlaybackMedia select(
    List<ApiMediaTrack> video, {
    int quality = 80,
    VideoCodecPreference preferred = VideoCodecPreference.h264,
    List<ApiMediaTrack>? audio,
  }) => selectDashMedia(
    ApiPlayInfo(
      duration: const Duration(minutes: 2),
      dashVideo: video,
      dashAudio: audio ?? [_track(30280, 'mp4a.40.2')],
      acceptQuality: const [32, 80, 120],
    ),
    quality: quality,
    preferredCodec: preferred,
    headers: const {'Referer': 'https://www.bilibili.com/'},
  );

  for (final (preference, codec) in const [
    (VideoCodecPreference.h264, 'avc1.640028'),
    (VideoCodecPreference.hevc, 'hev1.1.6.L120'),
    (VideoCodecPreference.av1, 'av01.0.08M.08'),
  ]) {
    test(
      'selects $preference at the requested quality and retains DASH audio',
      () {
        final media = select([
          _track(80, 'av01.0.08M.08'),
          _track(80, 'hev1.1.6.L120'),
          _track(80, 'avc1.640028'),
          _track(120, codec),
        ], preferred: preference);
        expect(media.video.codec, codec);
        expect(media.quality, 80);
        expect(media.qualities, [80, 120]);
        expect(media.audio?.codec, 'mp4a.40.2');
        expect(media.video.urls, hasLength(2));
        expect(media.headers['Referer'], 'https://www.bilibili.com/');
      },
    );
  }
  test(
    'quality is preserved when the preferred codec only exists lower down',
    () {
      final media = select([
        _track(32, 'av01.0.08M.08'),
        _track(80, 'hvc1.1.6.L120'),
        _track(80, 'AVC1.640028'),
        _track(120, 'av01.0.08M.08'),
      ], preferred: VideoCodecPreference.av1);
      expect(media.quality, 80);
      expect(media.video.codec, 'AVC1.640028');
      expect(media.qualities, [32, 80, 120]);
    },
  );
  test('HEVC-only and AV1-only sources remain usable without H.264', () {
    for (final codec in ['hev1.1.6.L120', 'av01.0.08M.08']) {
      expect(select([_track(80, codec)]).video.codec, codec);
    }
  });
  test('unsupported quality uses nearest lower or minimum server quality', () {
    final tracks = [_track(32, 'avc1'), _track(80, 'avc1')];
    expect(select(tracks, quality: 64).quality, 32);
    expect(select(tracks, quality: 16).quality, 32);
  });
  test(
    'unknown codecs do not enter quality choices or replace known codecs',
    () {
      final media = select([
        _track(120, 'vp09'),
        _track(32, 'avc1'),
      ], quality: 120);
      expect(media.quality, 32);
      expect(media.qualities, [32]);
      expect(() => select([_track(80, 'future')]), throwsA(isA<AppFailure>()));
      expect(
        () => select([_track(80, 'avc1')], audio: []),
        throwsA(isA<AppFailure>()),
      );
    },
  );
}

ApiMediaTrack _track(int quality, String codec) => ApiMediaTrack(
  id: quality,
  url: Uri.parse('https://cdn.example/$quality/$codec.m4s'),
  backupUrls: [Uri.parse('https://backup.example/$quality/$codec.m4s')],
  bandwidth: 100000,
  mimeType: 'video/mp4',
  codecs: codec,
);
