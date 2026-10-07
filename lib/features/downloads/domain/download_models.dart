import 'dart:typed_data';

import '../../../domain/app_failure.dart';
import '../../../domain/video.dart';
import '../../pgc/domain/pgc_repository.dart';
import '../../playback/domain/playback_repository.dart';

enum DownloadStatus {
  queued,
  resolving,
  downloading,
  verifying,
  paused,
  failed,
  completed,
}

enum DownloadTrackKind { video, audio }

/// Permanent content identity. Signed URLs and credentials are never stored.
final class DownloadItem {
  const DownloadItem({
    required this.video,
    required this.part,
    this.aid,
    this.episodeId,
    this.seasonId,
  });
  final VideoSummary video;
  final VideoPart part;
  final String? aid, episodeId, seasonId;
  String get key =>
      '${episodeId == null ? 'video:${video.id.value}' : 'episode:$episodeId'}:${part.cid}';
  bool get isValid =>
      (episodeId != null || video.id.isValid) &&
      RegExp(r'^[1-9][0-9]*$').hasMatch(part.cid) &&
      (episodeId == null || RegExp(r'^[1-9][0-9]*$').hasMatch(episodeId ?? ''));

  static List<DownloadItem> fromVideo(VideoDetail detail) => List.unmodifiable(
    detail.parts.map(
      (part) =>
          DownloadItem(video: detail.summary, part: part, aid: detail.aid),
    ),
  );
  static List<DownloadItem> fromSeason(PgcSeason season) => List.unmodifiable(
    season.episodes
        .where(
          (episode) =>
              episode.available &&
              RegExp(r'^[1-9][0-9]*$').hasMatch(episode.cid ?? ''),
        )
        .map(
          (episode) => DownloadItem(
            video: VideoSummary(
              id: VideoId(episode.bvid ?? ''),
              title: season.title,
              coverUrl: (episode.coverUrl ?? season.coverUrl)?.toString() ?? '',
              author: season.title,
              duration: episode.duration ?? Duration.zero,
            ),
            part: VideoPart(
              cid: episode.cid ?? '',
              page: season.episodes.indexOf(episode) + 1,
              title: episode.displayTitle,
              duration: episode.duration ?? Duration.zero,
            ),
            aid: episode.aid,
            episodeId: episode.episodeId,
            seasonId: season.seasonId,
          ),
        ),
  );
}

final class DownloadSelection {
  const DownloadSelection({
    this.quality = 80,
    this.codec = VideoCodecPreference.h264,
    this.includeDanmaku = true,
    this.includeSubtitles = true,
  });
  final int quality;
  final VideoCodecPreference codec;
  final bool includeDanmaku, includeSubtitles;
}

final class DownloadPreferences {
  const DownloadPreferences({this.directory, this.concurrency = 2});

  /// Null selects the application-owned offline directory.
  final String? directory;
  final int concurrency;
}

final class DownloadTrackSource {
  DownloadTrackSource({
    required this.identity,
    required this.kind,
    required List<Uri> urls,
    required this.codec,
    required this.bandwidth,
  }) : urls = List.unmodifiable(urls);
  final String identity, codec;
  final DownloadTrackKind kind;
  final List<Uri> urls;
  final int bandwidth;
}

final class DownloadResolvedSource {
  DownloadResolvedSource({
    required this.video,
    required this.audio,
    required this.quality,
    required this.duration,
    required Map<String, String> headers,
  }) : headers = Map.unmodifiable(headers);
  final DownloadTrackSource video, audio;
  final int quality;
  final Duration duration;
  final Map<String, String> headers;
}

final class DownloadedSubtitle {
  DownloadedSubtitle({required this.label, required List<SubtitleCue> cues})
    : cues = List.unmodifiable(cues);
  final String label;
  final List<SubtitleCue> cues;
}

final class DownloadExtras {
  DownloadExtras({
    List<TimedComment> comments = const [],
    List<DownloadedSubtitle> subtitles = const [],
    List<String> warnings = const [],
    Uint8List? cover,
  }) : comments = List.unmodifiable(comments),
       subtitles = List.unmodifiable(subtitles),
       warnings = List.unmodifiable(warnings),
       _cover = cover == null ? null : Uint8List.fromList(cover);
  final List<TimedComment> comments;
  final List<DownloadedSubtitle> subtitles;
  final List<String> warnings;
  final Uint8List? _cover;
  Uint8List? get cover => _cover == null ? null : Uint8List.fromList(_cover);
}

final class DownloadTrackProgress {
  const DownloadTrackProgress({
    required this.kind,
    required this.identity,
    required this.fileName,
    required this.codec,
    required this.bandwidth,
    this.bytes = 0,
    this.totalBytes,
    this.etag,
    this.sha256,
  });
  final DownloadTrackKind kind;
  final String identity, fileName, codec;
  final int bandwidth, bytes;
  final int? totalBytes;
  final String? etag, sha256;
  bool get complete =>
      totalBytes != null &&
      totalBytes! > 0 &&
      bytes == totalBytes &&
      sha256 != null;
  DownloadTrackProgress copyWith({
    int? bytes,
    int? totalBytes,
    String? etag,
    String? sha256,
  }) => DownloadTrackProgress(
    kind: kind,
    identity: identity,
    fileName: fileName,
    codec: codec,
    bandwidth: bandwidth,
    bytes: bytes ?? this.bytes,
    totalBytes: totalBytes ?? this.totalBytes,
    etag: etag ?? this.etag,
    sha256: sha256 ?? this.sha256,
  );
}

final class DownloadTask {
  DownloadTask({
    required this.id,
    required this.scope,
    required this.item,
    required this.selection,
    required this.status,
    required this.directory,
    required this.createdAt,
    required this.updatedAt,
    List<DownloadTrackProgress> tracks = const [],
    this.failure,
    List<String> warnings = const [],
    this.bytesPerSecond = 0,
    this.duration,
  }) : tracks = List.unmodifiable(tracks),
       warnings = List.unmodifiable(warnings);
  final String id, scope, directory;
  final DownloadItem item;
  final DownloadSelection selection;
  final DownloadStatus status;
  final DateTime createdAt, updatedAt;
  final List<DownloadTrackProgress> tracks;
  final AppFailure? failure;
  final List<String> warnings;
  final int bytesPerSecond;
  final Duration? duration;
  int get downloadedBytes => tracks.fold(0, (sum, track) => sum + track.bytes);
  int? get totalBytes =>
      tracks.length != 2 || tracks.any((track) => track.totalBytes == null)
      ? null
      : tracks.fold<int>(0, (sum, track) => sum + (track.totalBytes ?? 0));
  double? get progress => totalBytes == null || totalBytes == 0
      ? null
      : (downloadedBytes / (totalBytes ?? 1)).clamp(0, 1);
  bool get active => const [
    DownloadStatus.queued,
    DownloadStatus.resolving,
    DownloadStatus.downloading,
    DownloadStatus.verifying,
  ].contains(status);
  DownloadTask copyWith({
    DownloadStatus? status,
    List<DownloadTrackProgress>? tracks,
    AppFailure? failure,
    bool clearFailure = false,
    List<String>? warnings,
    int? bytesPerSecond,
    DateTime? updatedAt,
    Duration? duration,
  }) => DownloadTask(
    id: id,
    scope: scope,
    item: item,
    selection: selection,
    status: status ?? this.status,
    directory: directory,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    tracks: tracks ?? this.tracks,
    failure: clearFailure ? null : failure ?? this.failure,
    warnings: warnings ?? this.warnings,
    bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
    duration: duration ?? this.duration,
  );
}

final class DownloadQueueState {
  DownloadQueueState({
    List<DownloadTask> tasks = const [],
    this.preferences = const DownloadPreferences(),
    this.initialized = false,
    this.failure,
  }) : tasks = List.unmodifiable(tasks);
  final List<DownloadTask> tasks;
  final DownloadPreferences preferences;
  final bool initialized;
  final AppFailure? failure;
}
