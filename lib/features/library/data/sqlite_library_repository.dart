import 'package:drift/drift.dart';

import '../../../core/storage/app_database.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../domain/library_repository.dart';

class SqliteLibraryRepository implements LibraryRepository {
  SqliteLibraryRepository(this.database, {required this.accountScope});
  final AppDatabase database;
  final String Function() accountScope;

  @override
  Future<List<WatchHistoryEntry>> loadHistory({
    required RequestCancellation cancellation,
  }) async {
    if (cancellation.isCancelled) return const [];
    final scope = accountScope();
    final rows = await database
        .customSelect(
          'SELECT * FROM playback_progress WHERE scope = ? ORDER BY updated_at_ms DESC LIMIT 200',
          variables: [Variable<String>(scope)],
        )
        .get();
    if (cancellation.isCancelled || scope != accountScope()) return const [];
    return rows
        .map(
          (row) => WatchHistoryEntry(
            episodeId: row.readNullable<String>('pgc_episode_id'),
            video: VideoSummary(
              id: VideoId(row.read<String>('bvid')),
              title: row.read<String>('title'),
              coverUrl: row.read<String>('cover_url'),
              author: row.read<String>('author'),
              duration: Duration(milliseconds: row.read<int>('duration_ms')),
            ),
            part: VideoPart(
              cid: row.read<String>('cid'),
              page: row.read<int>('part_number'),
              title: row.read<String>('part_title'),
              duration: Duration(milliseconds: row.read<int>('duration_ms')),
            ),
            position: Duration(milliseconds: row.read<int>('position_ms')),
            watchedAt: DateTime.fromMillisecondsSinceEpoch(
              row.read<int>('updated_at_ms'),
            ),
          ),
        )
        .toList(growable: false);
  }

  Future<Duration> resumePosition(
    String scope,
    VideoId video,
    String cid,
  ) async {
    final row = await database
        .customSelect(
          'SELECT position_ms, duration_ms FROM playback_progress WHERE scope = ? AND bvid = ? AND cid = ?',
          variables: [
            Variable<String>(scope),
            Variable<String>(video.value),
            Variable<String>(cid),
          ],
        )
        .getSingleOrNull();
    if (row == null) return Duration.zero;
    final position = row.read<int>('position_ms');
    final duration = row.read<int>('duration_ms');
    // Completed videos reopen from the beginning; a deliberate rewind is saved as-is.
    return position >= duration - 5000
        ? Duration.zero
        : Duration(milliseconds: position);
  }

  Future<void> saveProgress({
    required String scope,
    required VideoSummary video,
    required VideoPart part,
    required Duration position,
    required Duration duration,
    String? episodeId,
  }) async {
    if (scope != accountScope() || duration <= Duration.zero) return;
    await database.transaction(() async {
      if (scope != accountScope()) return;
      await database.customStatement(
        '''INSERT INTO playback_progress
        (scope,bvid,cid,title,cover_url,author,duration_ms,part_title,part_number,position_ms,updated_at_ms,pgc_episode_id)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(scope,bvid,cid) DO UPDATE SET
        title=excluded.title,cover_url=excluded.cover_url,author=excluded.author,
        duration_ms=excluded.duration_ms,part_title=excluded.part_title,
        position_ms=excluded.position_ms,updated_at_ms=excluded.updated_at_ms,
        pgc_episode_id=excluded.pgc_episode_id''',
        [
          scope,
          video.id.value,
          part.cid,
          video.title,
          video.coverUrl,
          video.author,
          duration.inMilliseconds,
          part.title,
          part.page,
          position.inMilliseconds.clamp(0, duration.inMilliseconds),
          DateTime.now().millisecondsSinceEpoch,
          episodeId,
        ],
      );
      // Bounded per-account metadata. This never deletes offline media.
      await database.customStatement(
        '''DELETE FROM playback_progress WHERE scope = ?
        AND rowid NOT IN (SELECT rowid FROM playback_progress WHERE scope = ?
        ORDER BY updated_at_ms DESC LIMIT 500)''',
        [scope, scope],
      );
    });
  }
}
