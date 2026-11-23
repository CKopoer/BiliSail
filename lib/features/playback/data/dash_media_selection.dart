import 'package:bili_api/bili_api.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/audio_normalization.dart';
import '../../../domain/media_cdn.dart';
import '../../../domain/audio_quality.dart';
import '../../../domain/video_quality.dart';
import '../domain/playback_repository.dart';
import '../domain/sponsor_repository.dart';
import 'playback_enhancement_policy.dart';

/// Quality takes priority; a missing preferred codec does not downgrade it.
///
/// [avoidHdrDolby] drops HDR and Dolby Vision streams so output stays SDR. A
/// source that only offers tone-mapped streams still plays the highest one the
/// server returned instead of failing.
///
/// [unlockHighestBitrate] ignores the requested ceiling and applies BBZQ's
/// explicit quality order. The default numeric quality selection is unchanged.
PlaybackMedia selectDashMedia(
  ApiPlayInfo info, {
  required int quality,
  required VideoCodecPreference preferredCodec,
  required Map<String, String> headers,
  MediaCdnPreference cdnPreference = MediaCdnPreference.automatic,
  bool avoidHdrDolby = false,
  bool unlockHighestBitrate = false,
  bool videoOnly = false,
  AudioQualityPreference audioQuality = AudioQualityPreference.aac192,
}) {
  if (info.isPreview && !videoOnly) {
    throw const AppFailure(AppFailureKind.playback, '服务器仅返回预览，不能作为完整视频播放');
  }
  final knownVideos = info.dashVideo
      .where((track) => VideoCodecPreference.fromCodec(track.codecs) != null)
      .toList();
  final sdrVideos = avoidHdrDolby
      ? knownVideos.where((track) => !_isHdrOrDolbyTrack(track)).toList()
      : knownVideos;
  final videos = (sdrVideos.isEmpty ? knownVideos : sdrVideos)
    ..sort((a, b) {
      if (unlockHighestBitrate) {
        final rank = _highestBitrateRank(a.id)
            .compareTo(_highestBitrateRank(b.id));
        if (rank != 0) return rank;
      }
      return b.id.compareTo(a.id);
    });
  final audios =
      info.dashAudio
          .where(
            (track) =>
                AudioQualityPreference.identify(track.id, track.codecs) != null,
          )
          .toList()
        ..sort((a, b) {
          final order = audioQuality.fallbackOrder;
          final rank = order
              .indexWhere(
                (quality) =>
                    quality == AudioQualityPreference.identify(a.id, a.codecs),
              )
              .compareTo(
                order.indexWhere(
                  (quality) =>
                      quality ==
                      AudioQualityPreference.identify(b.id, b.codecs),
                ),
              );
          return rank != 0 ? rank : b.bandwidth.compareTo(a.bandwidth);
        });
  final silent =
      !videoOnly && info.isIntentionallySilent && info.dashAudio.isEmpty;
  if (videos.isEmpty || !videoOnly && audios.isEmpty && !silent) {
    throw AppFailure(
      AppFailureKind.playback,
      videoOnly ? '未取得可用的预览视频轨道' : '未取得可用的视频和音频轨道',
    );
  }
  final selectedQuality = unlockHighestBitrate
      ? videos.first.id
      : (videos.where((track) => track.id <= quality).firstOrNull ??
                videos.last)
            .id;
  final candidates = videos
      .where((track) => track.id == selectedQuality)
      .toList();
  final order = {preferredCodec, ...VideoCodecPreference.values}.toList();
  candidates.sort((a, b) {
    final codecOrder = order
        .indexWhere(
          (codec) => codec == VideoCodecPreference.fromCodec(a.codecs),
        )
        .compareTo(
          order.indexWhere(
            (codec) => codec == VideoCodecPreference.fromCodec(b.codecs),
          ),
        );
    return codecOrder != 0 ? codecOrder : b.bandwidth.compareTo(a.bandwidth);
  });
  PlaybackTrack map(ApiMediaTrack track) => PlaybackTrack(
    urls: orderMediaCdnUrls([track.url, ...track.backupUrls], cdnPreference),
    codec: track.codecs,
    bandwidth: track.bandwidth,
  );
  PlaybackVoice mapVoice(ApiPlaybackVoice voice) => PlaybackVoice(
    languageCode: voice.languageCode,
    label: voice.label,
    productionType: voice.productionType,
    subtitleLanguage: voice.subtitleLanguage,
    videoDetext: voice.videoDetext,
    videoMouthShapeChange: voice.videoMouthShapeChange,
  );
  final voices = List<PlaybackVoice>.unmodifiable(info.voices.map(mapVoice));
  final audioTracks = <PlaybackAudioTrack>[];
  if (!videoOnly) {
    for (final track in audios) {
      final quality = AudioQualityPreference.identify(track.id, track.codecs);
      if (quality != null &&
          !audioTracks.any((option) => option.quality == quality)) {
        audioTracks.add(
          PlaybackAudioTrack(quality: quality, track: map(track)),
        );
      }
    }
  }
  final loudness = videoOnly ? null : info.loudness;
  return PlaybackMedia(
    pgcSkipSegments: List.unmodifiable(
      info.pgcSkipSegments.map((clip) {
        final category = switch (clip.type) {
          ApiPgcSkipType.intro => 'intro',
          ApiPgcSkipType.outro => 'outro',
        };
        return SponsorSegment(
          id: 'official:$category:${clip.start.inMilliseconds}:${clip.end.inMilliseconds}',
          category: category,
          start: clip.start,
          end: clip.end,
          videoDuration: info.duration,
          isOfficial: true,
        );
      }),
    ),
    loudness: loudness == null
        ? null
        : AudioLoudness(
            measuredI: loudness.measuredI,
            normalTargetI: loudness.normalTargetI,
            highDynamicTargetI: loudness.highDynamicTargetI,
            undersizedTargetI: loudness.undersizedTargetI,
          ),
    video: map(candidates.first),
    audio: audioTracks.firstOrNull?.track,
    isIntentionallySilent: silent,
    audioTracks: List.unmodifiable(audioTracks),
    quality: selectedQuality,
    qualities: videos.map((track) => track.id).toSet().toList()..sort(),
    duration: info.duration,
    headers: headers,
    voices: voices,
    voice:
        voices
            .where(
              (voice) =>
                  voice.languageCode == info.currentLanguage &&
                  voice.productionType == info.productionType,
            )
            .firstOrNull ??
        const PlaybackVoice.original(),
  );
}

int _highestBitrateRank(int quality) {
  final index = PlaybackEnhancementPolicy.highestBitrateQualityOrder.indexOf(
    quality,
  );
  return index < 0
      ? PlaybackEnhancementPolicy.highestBitrateQualityOrder.length
      : index;
}

/// Whether this track is HDR by quality tier or Dolby Vision by codec.
///
/// Both need tone mapping the SDR preference is meant to avoid.
bool _isHdrOrDolbyTrack(ApiMediaTrack track) =>
    hdrVideoQualities.contains(track.id) ||
    VideoCodecPreference.fromCodec(track.codecs) ==
        VideoCodecPreference.dolbyVision;
