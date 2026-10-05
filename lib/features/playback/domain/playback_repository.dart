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
  });
  final PlaybackTrack video;
  final PlaybackTrack? audio;
  final PlaybackMediaKind kind;
  final Map<int, String> qualityLabels;
  final int quality;
  final List<int> qualities;
  final Duration duration;
  final Map<String, String> headers;
}

final class TimedComment {
  const TimedComment({
    required this.id,
    required this.position,
    required this.text,
    required this.mode,
    required this.color,
    required this.fontSize,
  });
  final String id;
  final Duration position;
  final String text;
  final int mode;
  final int color;
  final double fontSize;
}

final class SubtitleTrack {
  const SubtitleTrack(this.label, this.uri);
  final String label;
  final Uri uri;
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
  Future<Duration> read(String scope, VideoId video, String cid);
  Future<void> write(
    String scope,
    VideoSummary video,
    VideoPart part,
    Duration position,
    Duration duration, {
    String? episodeId,
  });
}
