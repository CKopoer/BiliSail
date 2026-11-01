import '../../../domain/video_quality.dart';
import '../domain/playback_repository.dart';

String playbackQualityLabel(int? quality) =>
    quality == null ? '画质' : videoQualityLabel(quality);

String playbackSubtitleLabel(SubtitleTrack track) {
  final label = track.label.isNotEmpty ? track.label : track.languageCode;
  return track.type == 1
      ? '$label · ${track.aiType == 1 ? 'AI 翻译' : 'AI'}'
      : label;
}

String playbackVoiceLabel(PlaybackVoice voice) =>
    voice.productionType == 2 ? '${voice.label} · AI 翻译' : voice.label;
