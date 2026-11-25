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
  muxing,
  paused,
  failed,
  completed,
}

enum DownloadTrackKind { video, audio }

enum DownloadOutput {
  separate,
  mp4,
  mkv;

  bool get isMerged => this != separate;
  String get fileName => switch (this) {
    separate => throw StateError('Separate tracks have no merged file'),
    mp4 => 'media.mp4',
    mkv => 'media.mkv',
  };
  String get label => switch (this) {
    separate => '音视频分轨',
    mp4 => '合并 MP4',
    mkv => '合并 MKV',
  };
}

/// Permanent content identity. Signed URLs and credentials are never stored.
final class DownloadItem {
  const DownloadItem({
    required this.video,
    required this.part,
    this.aid,
    this.episodeId,
    this.seasonId,
    this.work,
    this.section,
    this.episodeTitle,
    this.episodeLongTitle,
  });
  final VideoSummary video;
  final VideoPart part;
  final String? aid, episodeId, seasonId;
  final DownloadWork? work;
  final String? section, episodeTitle, episodeLongTitle;
  String get displayPartTitle {
    final short = episodeTitle?.trim() ?? '',
        long = episodeLongTitle?.trim() ?? '';
    if (short.isEmpty) return long.isEmpty ? part.title : long;
    final label = RegExp(r'^[0-9]+$').hasMatch(short) ? '第 $short 集' : short;
    return long.isEmpty || short == long ? label : '$label · $long';
  }

  String get workKey => seasonId != null
      ? 'season:$seasonId'
      : episodeId != null
      ? 'episode:$episodeId'
      : 'video:${video.id.value}';
  DownloadCategory category(DownloadWork? metadata) => episodeId == null
      ? DownloadCategory.video
      : switch (metadata?.seasonType) {
          1 => DownloadCategory.bangumi,
          4 => DownloadCategory.guochuang,
          _ => DownloadCategory.cinema,
        };
  String get key =>
      '${episodeId == null ? 'video:${video.id.value}' : 'episode:$episodeId'}:${part.cid}';
  bool get isValid =>
      (episodeId != null || video.id.isValid) &&
      RegExp(r'^[1-9][0-9]*$').hasMatch(part.cid) &&
      (episodeId == null || RegExp(r'^[1-9][0-9]*$').hasMatch(episodeId ?? ''));

  static List<DownloadItem> fromVideo(VideoDetail detail) {
    final collection = detail.collection;
    final position =
        collection?.entries.indexWhere(
          (entry) => entry.id == detail.summary.id,
        ) ??
        -1;
    final work = DownloadWork(
      description: detail.description,
      partCount: detail.parts.length,
      collectionId: position < 0 ? null : collection?.id,
      collectionTitle: position < 0 ? null : collection?.title,
      collectionPosition: position < 0 ? null : position,
    );
    return List.unmodifiable([
      for (final part in detail.parts)
        DownloadItem(
          video: detail.summary,
          part: part,
          aid: detail.aid,
          work: work,
        ),
    ]);
  }

  static List<DownloadItem> fromSeason(PgcSeason season) {
    final work = DownloadWork(
      description: season.description,
      seasonType: season.type,
    );
    return List.unmodifiable([
      for (final (index, episode) in season.episodes.indexed)
        if (episode.available &&
            RegExp(r'^[1-9][0-9]*$').hasMatch(episode.cid ?? ''))
          DownloadItem(
            video: VideoSummary(
              id: VideoId(episode.bvid ?? ''),
              title: season.title,
              coverUrl: (episode.coverUrl ?? season.coverUrl)?.toString() ?? '',
              author: season.title,
              duration: episode.duration ?? Duration.zero,
            ),
            part: VideoPart(
              cid: episode.cid ?? '',
              page: index + 1,
              title: episode.displayTitle,
              duration: episode.duration ?? Duration.zero,
            ),
            aid: episode.aid,
            episodeId: episode.episodeId,
            seasonId: season.seasonId,
            work: work,
            section: pgcEpisodeSection(episode),
            episodeTitle: episode.title,
            episodeLongTitle: episode.longTitle,
          ),
    ]);
  }
}

enum DownloadCategory {
  all('全部'),
  video('视频'),
  bangumi('番剧'),
  guochuang('国创'),
  cinema('影视');

  const DownloadCategory(this.label);
  final String label;
}

/// Shared by all parts of a BV or all episodes of one season in an account.
final class DownloadWork {
  const DownloadWork({
    this.description = '',
    this.partCount,
    this.seasonType,
    this.collectionId,
    this.collectionTitle,
    this.collectionPosition,
  });
  final String description;
  final int? partCount, seasonType, collectionPosition;
  final String? collectionId, collectionTitle;
}

typedef DownloadVideoOption = ({int quality, VideoCodecPreference codec});

final class DownloadSelection {
  const DownloadSelection({
    this.quality = 80,
    this.codec = VideoCodecPreference.h264,
    this.includeDanmaku = true,
    this.includeSubtitles = true,
    this.output = DownloadOutput.separate,
  });
  final int quality;
  final VideoCodecPreference codec;
  final bool includeDanmaku, includeSubtitles;
  final DownloadOutput output;
}

/// Committed local output; source track identities remain in the task index.
final class DownloadMergedMedia {
  const DownloadMergedMedia({
    required this.bytes,
    this.sha256,
    this.output = DownloadOutput.mp4,
  });
  final int bytes;
  final String? sha256;
  final DownloadOutput output;
  String get fileName => output.fileName;
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
    this.committed = false,
  });
  final DownloadTrackKind kind;
  final String identity, fileName, codec;
  final int bandwidth, bytes;
  final int? totalBytes;
  final String? etag, sha256;

  /// Old records used a digest as the commit marker, never as a playback gate.
  final bool committed;
  bool get complete => committed || sha256 != null;
  DownloadTrackProgress copyWith({
    int? bytes,
    int? totalBytes,
    String? etag,
    String? sha256,
    bool? committed,
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
    committed: committed ?? this.committed,
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
    this.mergedMedia,
    this.muxProgress,
    this.publicDestination,
    Map<String, String> publicFiles = const {},
  }) : publicFiles = Map.unmodifiable(publicFiles),
       tracks = List.unmodifiable(tracks),
       warnings = List.unmodifiable(warnings);
  final String id, scope, directory;
  final String? publicDestination;
  final Map<String, String> publicFiles;
  final DownloadItem item;
  final DownloadSelection selection;
  final DownloadStatus status;
  final DateTime createdAt, updatedAt;
  final List<DownloadTrackProgress> tracks;
  final AppFailure? failure;
  final List<String> warnings;
  final int bytesPerSecond;
  final Duration? duration;
  final DownloadMergedMedia? mergedMedia;
  final double? muxProgress;
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
    DownloadStatus.muxing,
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
    DownloadMergedMedia? mergedMedia,
    bool clearMergedMedia = false,
    double? muxProgress,
    Map<String, String>? publicFiles,
  }) => DownloadTask(
    id: id,
    scope: scope,
    item: item,
    selection: selection,
    status: status ?? this.status,
    directory: directory,
    publicDestination: publicDestination,
    publicFiles: publicFiles ?? this.publicFiles,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    tracks: tracks ?? this.tracks,
    failure: clearFailure ? null : failure ?? this.failure,
    warnings: warnings ?? this.warnings,
    bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
    duration: duration ?? this.duration,
    mergedMedia: clearMergedMedia ? null : mergedMedia ?? this.mergedMedia,
    muxProgress: muxProgress ?? this.muxProgress,
  );
}

final class DownloadQueueState {
  DownloadQueueState({
    List<DownloadTask> tasks = const [],
    this.preferences = const DownloadPreferences(),
    this.initialized = false,
    this.failure,
    this.canMerge = false,
    this.works = const {},
  }) : tasks = List.unmodifiable(tasks);
  final List<DownloadTask> tasks;
  final DownloadPreferences preferences;
  final bool initialized;
  final AppFailure? failure;
  final bool canMerge;
  final Map<String, DownloadWork> works;
}
