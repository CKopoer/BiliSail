import 'package:bili_api/bili_api.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/features/playback/data/dash_media_selection.dart';
import 'package:bilisail/features/playback/data/playback_enhancement_policy.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PlaybackMedia select(
    List<ApiMediaTrack> videos, {
    int quality = 80,
    bool highest = false,
    bool avoidHdrDolby = false,
    bool preview = false,
    bool videoOnly = false,
  }) => selectDashMedia(
    ApiPlayInfo(
      duration: const Duration(seconds: 60),
      dashVideo: videos,
      dashAudio: videoOnly ? const [] : [_track(30280, 'mp4a.40.2')],
      acceptQuality: videos.map((track) => track.id).toList(),
      isPreview: preview,
    ),
    quality: quality,
    preferredCodec: VideoCodecPreference.h264,
    unlockHighestBitrate: highest,
    avoidHdrDolby: avoidHdrDolby,
    videoOnly: videoOnly,
    headers: const {},
  );

  group('PlaybackEnhancementPolicy', () {
    test('all enhancements are disabled by default', () {
      const policy = PlaybackEnhancementPolicy();

      expect(policy.unlockHighestBitrate, isFalse);
      expect(policy.unlimitedQualityTrial, isFalse);
      expect(policy.trialUiSync, isFalse);
      expect(policy.uiSyncReport.enabled, isFalse);
      expect(
        policy.uiSyncReport.qualityOptionsFollowReturnedDashTracks,
        isTrue,
      );
      expect(policy.uiSyncReport.behavior, contains('still follow'));
    });

    test(
      'UI sync reports returned-quality mapping without fake host state',
      () {
        const policy = PlaybackEnhancementPolicy(
          unlimitedQualityTrial: true,
          trialUiSync: true,
        );
        final report = policy.uiSyncReport;

        expect(report.qualityOptionsFollowReturnedDashTracks, isTrue);
        expect(report.rewritesOfficialHostFields, isFalse);
        expect(report.grantsMembership, isFalse);
        expect(report.trialRequestsEnabled, isTrue);
        expect(report.behavior, contains('server-returned DASH tracks'));
        expect(report.behavior, contains('not rewritten'));
      },
    );

    test('UI sync alone does not enable trial requests', () {
      const policy = PlaybackEnhancementPolicy(trialUiSync: true);

      expect(policy.unlimitedQualityTrial, isFalse);
      expect(policy.uiSyncReport.trialRequestsEnabled, isFalse);
      expect(policy.uiSyncReport.behavior, contains('remain disabled'));
    });
  });

  group('highest bitrate selection', () {
    test('follows every tier in the exact BBZQ preference order', () {
      final remaining = [
        for (final quality
            in PlaybackEnhancementPolicy.highestBitrateQualityOrder.reversed)
          _track(quality, 'avc1'),
      ];

      for (final expected
          in PlaybackEnhancementPolicy.highestBitrateQualityOrder) {
        expect(select(remaining, quality: 16, highest: true).quality, expected);
        remaining.removeWhere((track) => track.id == expected);
      }
    });

    test('prefers 1080P high bitrate over 1080P60 when enabled', () {
      final tracks = [_track(116, 'avc1'), _track(112, 'avc1')];

      expect(select(tracks, quality: 16, highest: true).quality, 112);
      expect(select(tracks, quality: 120).quality, 116);
    });

    test('keeps codec preference then highest bandwidth within a tier', () {
      final low = _track(112, 'avc1', bandwidth: 1000, name: 'low');
      final high = _track(112, 'avc1', bandwidth: 3000, name: 'high');
      final hevc = _track(112, 'hev1.1.6.L120', bandwidth: 9000);

      final media = select([low, hevc, high], highest: true);

      expect(media.video.bandwidth, 3000);
      expect(media.video.codec, 'avc1');
    });

    test('composes with HDR filtering without changing the quality order', () {
      final media = select(
        [
          _track(126, 'dvh1.05.06'),
          _track(125, 'hev1.1.6.L120'),
          _track(116, 'avc1'),
          _track(112, 'avc1'),
        ],
        highest: true,
        avoidHdrDolby: true,
      );

      expect(media.quality, 112);
      expect(media.qualities, [112, 116]);
    });
  });

  test('preview media fails full playback but remains usable for hover', () {
    expect(
      () => select([_track(80, 'avc1')], preview: true),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.kind,
          'kind',
          AppFailureKind.playback,
        ),
      ),
    );

    final hover = select([_track(32, 'avc1')], preview: true, videoOnly: true);
    expect(hover.quality, 32);
    expect(hover.audio, isNull);
  });
}

ApiMediaTrack _track(
  int quality,
  String codec, {
  int bandwidth = 100000,
  String? name,
}) => ApiMediaTrack(
  id: quality,
  url: Uri.parse('https://cdn.example/${name ?? quality}.m4s'),
  backupUrls: const [],
  bandwidth: bandwidth,
  mimeType: 'video/mp4',
  codecs: codec,
);
