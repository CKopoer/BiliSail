import 'package:bili_api/bili_api.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/media_cdn.dart';
import '../domain/playback_repository.dart';

/// Quality takes priority; a missing preferred codec does not downgrade it.
PlaybackMedia selectDashMedia(
  ApiPlayInfo info, {
  required int quality,
  required VideoCodecPreference preferredCodec,
  required Map<String, String> headers,
  MediaCdnPreference cdnPreference = MediaCdnPreference.automatic,
  bool videoOnly = false,
}) {
  final videos =
      info.dashVideo
          .where(
            (track) => VideoCodecPreference.fromCodec(track.codecs) != null,
          )
          .toList()
        ..sort((a, b) => b.id.compareTo(a.id));
  final audios =
      info.dashAudio
          .where((track) => track.codecs.toLowerCase().startsWith('mp4a'))
          .toList()
        ..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
  if (videos.isEmpty || !videoOnly && audios.isEmpty) {
    throw AppFailure(
      AppFailureKind.playback,
      videoOnly ? '未取得可用的预览视频轨道' : '未取得可用的 H.264、HEVC 或 AV1 视频和 AAC 音频轨道',
    );
  }
  final selectedQuality =
      (videos.where((track) => track.id <= quality).firstOrNull ?? videos.last)
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
  return PlaybackMedia(
    video: map(candidates.first),
    audio: videoOnly ? null : map(audios.first),
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
