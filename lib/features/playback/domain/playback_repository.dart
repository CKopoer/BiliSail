import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../../../domain/video_codec.dart';
import '../../../domain/app_failure.dart';
import 'playback_timeline.dart';

export '../../../domain/video_codec.dart';
export 'playback_timeline.dart';

final class PlaybackTrack {
  const PlaybackTrack({
    required this.urls,
    required this.codec,
    required this.bandwidth,
  });
  final List<Uri> urls;
  final String codec;
  final int bandwidth;
}

enum PlaybackMediaKind { dash, liveHls, liveFlv }

final class PlaybackMedia {
  const PlaybackMedia({
    required this.video,
    required this.audio,
    required this.quality,
    required this.qualities,
    required this.duration,
    required this.headers,
    this.kind = PlaybackMediaKind.dash,
    this.qualityLabels = const {},
    this.voices = const [],
    this.voice = const PlaybackVoice.original(),
  });
  final PlaybackTrack video;
  final PlaybackTrack? audio;
  final PlaybackMediaKind kind;
  final Map<int, String> qualityLabels;
  final int quality;
  final List<int> qualities;
  final Duration duration;
  final Map<String, String> headers;
  final List<PlaybackVoice> voices;
  final PlaybackVoice voice;
}

final class PlaybackVoice {
  const PlaybackVoice({
    required this.languageCode,
    required this.label,
    required this.productionType,
    this.subtitleLanguage = '',
    this.videoDetext = false,
    this.videoMouthShapeChange = false,
  });
  const PlaybackVoice.original()
    : languageCode = '',
      label = '原声',
      productionType = 0,
      subtitleLanguage = '',
      videoDetext = false,
      videoMouthShapeChange = false;
  final String languageCode, label, subtitleLanguage;
  final int productionType;
  final bool videoDetext, videoMouthShapeChange;
  bool get isOriginal => productionType == 0 && languageCode.isEmpty;
  String get key => '$productionType:$languageCode';
}

final class TimedComment {
  const TimedComment({
    required this.id,
    required this.position,
    required this.text,
    required this.mode,
    required this.color,
    required this.fontSize,
    this.weight = 0,
  });
  final String id;
  final Duration position;
  final String text;
  final int mode;
  final int color;
  final double fontSize;
  final int weight;
}

final class SubtitleTrack {
  const SubtitleTrack(
    this.label,
    this.uri, {
    this.id = '',
    this.languageCode = '',
    this.type,
    this.aiType,
    this.aiStatus,
  });
  final String label;
  final Uri uri;
  final String id, languageCode;
  final int? type, aiType, aiStatus;
  String get preferenceKey => languageCode.isEmpty ? label : languageCode;
}

/// Optional online capability; offline and content resolvers keep their contract.
abstract interface class VoicePlaybackRepository {
  Future<PlaybackMedia> resolveVoice(
    VideoId video,
    String cid, {
    required PlaybackVoice voice,
    required int quality,
    required VideoCodecPreference preferredCodec,
    required RequestCancellation cancellation,
  });
}

final class SubtitleCue {
  const SubtitleCue(this.start, this.end, this.text);
  final Duration start;
  final Duration end;
  final String text;
}

final class PlaybackMetadata {
  const PlaybackMetadata({
    required this.subtitles,
    required this.chapters,
    this.subtitleFailure,
    this.chapterFailure,
  });
  final List<SubtitleTrack> subtitles;
  final List<VideoChapter> chapters;
  final AppFailure? subtitleFailure, chapterFailure;
}

abstract interface class PlaybackMetadataRepository {
  Future<PlaybackMetadata> metadata(
    VideoDetail video,
    VideoPart part, {
    required RequestCancellation cancellation,
  });
  Future<VideoStoryboard?> storyboard(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  });
}

abstract interface class PlaybackRepository {
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  });
  Future<List<TimedComment>> comments(
    String cid,
    int segment, {
    required RequestCancellation cancellation,
  });
  Future<List<SubtitleTrack>> subtitles(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  });
  Future<List<SubtitleCue>> subtitleCues(
    SubtitleTrack track, {
    required RequestCancellation cancellation,
  });
}

abstract interface class PlaybackProgressStore {
  /// Null means no record; zero is an existing rewind/completed record.
  Future<Duration?> read(String scope, VideoId video, String cid);
  Future<void> write(
    String scope,
    VideoSummary video,
    VideoPart part,
    Duration position,
    Duration duration, {
    String? episodeId,
  });
}
