import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as path;

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../../downloads/domain/download_repository.dart';
import '../domain/content_playback.dart';
import '../domain/playback_repository.dart';

/// One adapter per PlaybackSession keeps offline reads isolated between tabs.
final class OfflinePlaybackRepository
    implements
        PlaybackRepository,
        PlaybackMetadataRepository,
        VoicePlaybackRepository {
  OfflinePlaybackRepository({
    required this.downloads,
    required this.network,
    required this.networkMetadata,
    required this.networkContent,
  });
  final DownloadRepository downloads;
  final PlaybackRepository network;
  final PlaybackMetadataRepository networkMetadata;
  final ContentPlaybackRepository networkContent;
  DownloadTask? _offline;
  Future<DownloadExtras>? _extras;
  int _revision = 0;

  ContentPlaybackRepository get content => _OfflineContentRepository(this);

  void _beginSource() {
    ++_revision;
    _offline = null;
    _extras = null;
  }

  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) {
    _beginSource();
    return network.resolve(
      video,
      cid,
      quality: quality,
      preferredCodec: preferredCodec,
      cancellation: cancellation,
    );
  }

  @override
  Future<PlaybackMedia> resolveVoice(
    VideoId video,
    String cid, {
    required PlaybackVoice voice,
    required int quality,
    required VideoCodecPreference preferredCodec,
    required RequestCancellation cancellation,
  }) {
    _beginSource();
    final resolver = network;
    if (resolver is! VoicePlaybackRepository) {
      throw const AppFailure(AppFailureKind.playback, '当前播放源不支持语音选择');
    }
    return (resolver as VoicePlaybackRepository).resolveVoice(
      video,
      cid,
      voice: voice,
      quality: quality,
      preferredCodec: preferredCodec,
      cancellation: cancellation,
    );
  }

  Future<PlaybackMedia> _resolveContent(
    ContentPlaybackTarget target, {
    required int quality,
    required VideoCodecPreference preferredCodec,
    required RequestCancellation cancellation,
  }) async {
    _beginSource();
    if (target is! OfflinePlaybackTarget) {
      return networkContent.resolve(
        target,
        quality: quality,
        preferredCodec: preferredCodec,
        cancellation: cancellation,
      );
    }
    final revision = _revision;
    _check(cancellation);
    final task = await downloads.offlineTask(target.taskId);
    _check(cancellation);
    if (revision != _revision) {
      throw const AppFailure(AppFailureKind.cancelled, '播放源已切换');
    }
    final video = task.tracks
        .where((track) => track.kind == DownloadTrackKind.video)
        .firstOrNull;
    final audio = task.tracks
        .where((track) => track.kind == DownloadTrackKind.audio)
        .firstOrNull;
    if (task.status != DownloadStatus.completed ||
        video == null ||
        audio == null ||
        !video.complete ||
        !audio.complete) {
      throw const AppFailure(AppFailureKind.storage, '离线音视频不完整，请重新下载');
    }
    PlaybackTrack localTrack(DownloadTrackProgress track) {
      if (path.basename(track.fileName) != track.fileName ||
          !const ['video.m4s', 'audio.m4s'].contains(track.fileName)) {
        throw const AppFailure(AppFailureKind.storage, '离线文件索引无效');
      }
      return PlaybackTrack(
        urls: [File(path.join(task.directory, track.fileName)).uri],
        codec: track.codec,
        bandwidth: track.bandwidth,
      );
    }

    final merged = task.mergedMedia;
    if (task.selection.output == DownloadOutput.mp4 && merged == null) {
      throw const AppFailure(AppFailureKind.storage, '离线合并文件索引无效');
    }
    final media = PlaybackMedia(
      video: task.selection.output == DownloadOutput.mp4 && merged != null
          ? PlaybackTrack(
              urls: [File(path.join(task.directory, merged.fileName)).uri],
              codec: video.codec,
              bandwidth: video.bandwidth + audio.bandwidth,
            )
          : localTrack(video),
      audio: task.selection.output == DownloadOutput.mp4
          ? null
          : localTrack(audio),
      quality: task.selection.quality,
      qualities: [task.selection.quality],
      duration: task.duration ?? task.item.part.duration,
      headers: const {},
    );
    _offline = task;
    return media;
  }

  Future<DownloadExtras> _readExtras(
    DownloadTask task,
    RequestCancellation cancellation,
  ) async {
    _check(cancellation);
    // Cached only for this source/session; no account-global decoded media.
    final extras = await (_extras ??= _loadExtras(task.directory));
    _check(cancellation);
    if (!identical(task, _offline)) {
      throw const AppFailure(AppFailureKind.cancelled, '播放源已切换');
    }
    return extras;
  }

  @override
  Future<List<TimedComment>> comments(
    String cid,
    int segment, {
    required RequestCancellation cancellation,
  }) async {
    final task = _offline;
    if (task == null) {
      return network.comments(cid, segment, cancellation: cancellation);
    }
    if (cid != task.item.part.cid || segment < 1) return const [];
    final extras = await _readExtras(task, cancellation);
    final start = Duration(seconds: (segment - 1) * 360);
    final end = start + const Duration(seconds: 360);
    return extras.comments
        .where((comment) => comment.position >= start && comment.position < end)
        .take(6000)
        .toList(growable: false);
  }

  @override
  Future<List<SubtitleTrack>> subtitles(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  }) async {
    final task = _offline;
    if (task == null) {
      return network.subtitles(video, cid, cancellation: cancellation);
    }
    final extras = await _readExtras(task, cancellation);
    return [
      for (var i = 0; i < extras.subtitles.length; i++)
        SubtitleTrack(
          extras.subtitles[i].label,
          Uri(scheme: 'bilisail-offline', host: task.id, path: '/subtitle/$i'),
        ),
    ];
  }

  @override
  Future<List<SubtitleCue>> subtitleCues(
    SubtitleTrack track, {
    required RequestCancellation cancellation,
  }) async {
    final task = _offline;
    if (task == null) {
      return network.subtitleCues(track, cancellation: cancellation);
    }
    final index = int.tryParse(track.uri.pathSegments.lastOrNull ?? '');
    final extras = await _readExtras(task, cancellation);
    if (track.uri.scheme != 'bilisail-offline' ||
        track.uri.host != task.id ||
        index == null ||
        index < 0 ||
        index >= extras.subtitles.length) {
      throw const AppFailure(AppFailureKind.storage, '离线字幕索引无效');
    }
    return extras.subtitles[index].cues;
  }

  @override
  Future<PlaybackMetadata> metadata(
    VideoDetail video,
    VideoPart part, {
    required RequestCancellation cancellation,
  }) async {
    if (_offline == null) {
      return networkMetadata.metadata(video, part, cancellation: cancellation);
    }
    return PlaybackMetadata(
      subtitles: await subtitles(
        video.summary.id,
        part.cid,
        cancellation: cancellation,
      ),
      chapters: const [],
    );
  }

  @override
  Future<VideoStoryboard?> storyboard(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  }) async {
    _check(cancellation);
    if (_offline != null) return null;
    return networkMetadata.storyboard(video, cid, cancellation: cancellation);
  }
}

final class _OfflineContentRepository implements ContentPlaybackRepository {
  const _OfflineContentRepository(this.owner);
  final OfflinePlaybackRepository owner;
  @override
  Future<PlaybackMedia> resolve(
    ContentPlaybackTarget target, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) => owner._resolveContent(
    target,
    quality: quality,
    preferredCodec: preferredCodec,
    cancellation: cancellation,
  );
}

void _check(RequestCancellation cancellation) {
  if (cancellation.isCancelled) {
    throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
  }
}

Future<DownloadExtras> _loadExtras(String directory) async {
  try {
    final file = File(path.join(directory, 'extras.json'));
    if (!await file.exists()) return DownloadExtras();
    if (await file.length() > 32 * 1024 * 1024) {
      throw const FormatException('Oversized offline extras');
    }
    final contents = await file.readAsString();
    return await Isolate.run(() => _decodeExtras(contents));
  } on FormatException {
    throw const AppFailure(AppFailureKind.storage, '离线字幕或弹幕文件损坏');
  } on FileSystemException {
    throw const AppFailure(AppFailureKind.storage, '无法读取离线字幕或弹幕');
  }
}

DownloadExtras _decodeExtras(String contents) {
  final Object? decoded = jsonDecode(contents);
  if (decoded is! Map<String, Object?> || decoded['version'] != 1) {
    throw const FormatException('Invalid offline extras');
  }
  final comments = <TimedComment>[];
  final subtitles = <DownloadedSubtitle>[];
  final rows = decoded['comments'];
  if (rows is! List<Object?> || rows.length > 60000) {
    throw const FormatException('Invalid comment count');
  }
  for (final row in rows) {
    if (row is! Map<String, Object?>) {
      throw const FormatException('Invalid comment');
    }
    comments.add(
      TimedComment(
        id: _string(row, 'id', 128),
        position: Duration(milliseconds: _integer(row, 'positionMs')),
        text: _string(row, 'text', 512),
        mode: _integer(row, 'mode'),
        color: _integer(row, 'color'),
        fontSize: _number(row, 'fontSize'),
        weight: _integer(row, 'weight'),
      ),
    );
  }
  final tracks = decoded['subtitles'];
  if (tracks is! List<Object?> || tracks.length > 16) {
    throw const FormatException('Invalid subtitle count');
  }
  var cueCount = 0;
  for (final track in tracks) {
    if (track is! Map<String, Object?> || track['cues'] is! List<Object?>) {
      throw const FormatException('Invalid subtitle');
    }
    final cues = <SubtitleCue>[];
    for (final row in track['cues'] as List<Object?>) {
      if (row is! Map<String, Object?> || ++cueCount > 100000) {
        throw const FormatException('Invalid cue count');
      }
      final start = _integer(row, 'startMs');
      final end = _integer(row, 'endMs');
      if (end < start) throw const FormatException('Invalid cue time');
      cues.add(
        SubtitleCue(
          Duration(milliseconds: start),
          Duration(milliseconds: end),
          _string(row, 'text', 4096),
        ),
      );
    }
    subtitles.add(
      DownloadedSubtitle(label: _string(track, 'label', 256), cues: cues),
    );
  }
  return DownloadExtras(comments: comments, subtitles: subtitles);
}

String _string(Map<String, Object?> row, String key, int maxLength) {
  final value = row[key];
  if (value is! String || value.length > maxLength) {
    throw const FormatException('Invalid offline text');
  }
  return value;
}

int _integer(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is! int || value < 0) {
    throw const FormatException('Invalid offline number');
  }
  return value;
}

double _number(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is! num || !value.isFinite || value < 0 || value > 1000) {
    throw const FormatException('Invalid offline font size');
  }
  return value.toDouble();
}
