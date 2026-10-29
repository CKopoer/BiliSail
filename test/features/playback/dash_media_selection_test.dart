import 'package:bili_api/bili_api.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/audio_quality.dart';
import 'package:bilisail/domain/media_cdn.dart';
import 'package:bilisail/features/playback/data/dash_media_selection.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dvh1 and dvhe are Dolby Vision rather than ordinary HEVC', () {
    expect(
      VideoCodecPreference.fromCodec('dvh1.05.06'),
      VideoCodecPreference.dolbyVision,
    );
    expect(
      VideoCodecPreference.fromCodec('dvhe.08.06'),
      VideoCodecPreference.dolbyVision,
    );
    final media = selectDashMedia(
      ApiPlayInfo(
        duration: const Duration(seconds: 60),
        dashVideo: [_track(126, 'dvh1.05.06')],
        dashAudio: [_track(30280, 'mp4a.40.2')],
        acceptQuality: const [126],
      ),
      quality: 126,
      preferredCodec: VideoCodecPreference.dolbyVision,
      headers: const {},
    );
    expect(media.video.codec, 'dvh1.05.06');
  });
  for (final (preference, expected) in [
    (AudioQualityPreference.aac64, 'mp4a.40.5'),
    (AudioQualityPreference.aac132, 'mp4a.40.29'),
    (AudioQualityPreference.aac192, 'mp4a.40.2'),
    (AudioQualityPreference.lossless, 'fLaC'),
    (AudioQualityPreference.dolby, 'ec-3'),
  ]) {
    test(
      'audio preference $preference selects format before bandwidth and ID',
      () {
        final info = ApiPlayInfo(
          duration: const Duration(seconds: 60),
          dashVideo: [_track(80, 'avc1')],
          dashAudio: [
            _track(30255, 'ec-3'),
            _track(30251, 'fLaC'),
            _track(30280, 'mp4a.40.2'),
            _track(30232, 'mp4a.40.29'),
            _track(30216, 'mp4a.40.5'),
          ],
          acceptQuality: const [80],
        );
        final media = selectDashMedia(
          info,
          quality: 80,
          preferredCodec: VideoCodecPreference.h264,
          headers: const {},
          audioQuality: preference,
        );
        expect(media.audio?.codec, expected);
      },
    );
  }
  test(
    'missing special audio falls back to AAC and unknown codecs stay excluded',
    () {
      final info = ApiPlayInfo(
        duration: const Duration(seconds: 60),
        dashVideo: [_track(80, 'avc1')],
        dashAudio: [_track(30280, 'mp4a.40.2'), _track(99999, 'unknown')],
        acceptQuality: const [80],
      );
      for (final preference in [
        AudioQualityPreference.lossless,
        AudioQualityPreference.dolby,
      ]) {
        expect(
          selectDashMedia(
            info,
            quality: 80,
            preferredCodec: VideoCodecPreference.h264,
            headers: const {},
            audioQuality: preference,
          ).audio?.codec,
          'mp4a.40.2',
        );
      }
    },
  );
  test('explicit CDN mirrors preserve DASH audio, video and original backups', () {
    ApiMediaTrack track(bool audio) => ApiMediaTrack(
      id: audio ? 30280 : 80,
      url: Uri.parse(
        'https://upos-sz-mirrorhw.bilivideo.com/upgcxcode/${audio ? 'audio' : 'video'}.m4s?key=fixture%2Bvalue',
      ),
      backupUrls: const [],
      bandwidth: 100000,
      mimeType: audio ? 'audio/mp4' : 'video/mp4',
      codecs: audio ? 'mp4a.40.2' : 'avc1.640028',
    );
    final video = track(false);
    final audio = track(true);
    final media = selectDashMedia(
      ApiPlayInfo(
        duration: const Duration(minutes: 1),
        dashVideo: [video],
        dashAudio: [audio],
        acceptQuality: const [80],
      ),
      quality: 80,
      preferredCodec: VideoCodecPreference.h264,
      cdnPreference: MediaCdnPreference.ali,
      headers: const {'Referer': 'https://www.bilibili.com/'},
    );
    for (final (result, source) in [
      (media.video, video),
      (media.audio, audio),
    ]) {
      expect(result?.urls.first.host, MediaCdnPreference.ali.host);
      expect(result?.urls.first.path, source.url.path);
      expect(result?.urls.first.query, source.url.query);
      expect(result?.urls.last, source.url);
      expect(
        backupMediaCdnUrl(result?.urls ?? [], MediaCdnPreference.ali),
        source.url,
      );
    }
  });
  test(
    'both DASH repositories share loudness mapping; muted preview omits it',
    () {
      final info = ApiPlayInfo(
        duration: const Duration(seconds: 60),
        dashVideo: [_track(80, 'avc1')],
        dashAudio: [_track(30280, 'mp4a.40.2')],
        acceptQuality: const [80],
        loudness: const ApiAudioLoudness(
          measuredI: -16.7,
          normalTargetI: -14,
          highDynamicTargetI: -24,
          undersizedTargetI: -28,
        ),
      );
      PlaybackMedia resolve(bool videoOnly) => selectDashMedia(
        info,
        quality: 80,
        preferredCodec: VideoCodecPreference.h264,
        headers: const {},
        videoOnly: videoOnly,
      );
      expect(resolve(false).loudness?.measuredI, -16.7);
      expect(resolve(false).loudness?.highDynamicTargetI, -24);
      expect(resolve(true).loudness, isNull);
    },
  );
  test('DASH mapping preserves voice options, associated subtitles and selected voice', () {
    final media = selectDashMedia(
      ApiPlayInfo(
        duration: const Duration(minutes: 2),
        dashVideo: [_track(80, 'avc1')],
        dashAudio: [_track(30280, 'mp4a.40.2')],
        acceptQuality: const [80],
        currentLanguage: 'en',
        productionType: 2,
        voices: const [
          ApiPlaybackVoice(
            languageCode: 'en',
            label: 'English',
            productionType: 2,
            subtitleLanguage: 'ai-en',
            videoDetext: true,
          ),
        ],
      ),
      quality: 80,
      preferredCodec: VideoCodecPreference.h264,
      headers: const {},
    );
    expect(media.voices.single.key, '2:en');
    expect(media.voice.subtitleLanguage, 'ai-en');
    expect(media.voice.videoDetext, isTrue);
    expect(media.voice.videoMouthShapeChange, isFalse);
    expect(media.voice.isOriginal, isFalse);
  });
  test('explicit video preview accepts video without weakening normal DASH selection', () {
    final info = ApiPlayInfo(
      duration: const Duration(seconds: 20),
      dashVideo: [_track(32, 'avc1')],
      dashAudio: const [],
      acceptQuality: const [32],
    );
    PlaybackMedia resolve(bool videoOnly) => selectDashMedia(
      info,
      quality: 32,
      preferredCodec: VideoCodecPreference.h264,
      videoOnly: videoOnly,
      headers: const {},
    );
    expect(resolve(true).audio, isNull);
    expect(() => resolve(false), throwsA(isA<AppFailure>()));
  });
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
