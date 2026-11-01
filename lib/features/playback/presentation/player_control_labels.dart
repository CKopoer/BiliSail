import '../domain/playback_repository.dart';

String playbackQualityLabel(int? quality) => switch (quality) {
  120 => '4K',
  116 => '1080P60',
  112 => '1080P+',
  80 => '1080P',
  74 => '720P60',
  64 => '720P',
  32 => '480P',
  16 => '360P',
  null => '画质',
  _ => '$quality',
};

String playbackSubtitleLabel(SubtitleTrack track) {
  final label = track.label.isNotEmpty ? track.label : track.languageCode;
  return track.type == 1
      ? '$label · ${track.aiType == 1 ? 'AI 翻译' : 'AI'}'
      : label;
}

String playbackVoiceLabel(PlaybackVoice voice) =>
    voice.productionType == 2 ? '${voice.label} · AI 翻译' : voice.label;
