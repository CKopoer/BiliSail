import '../../../domain/request_cancellation.dart';
import '../domain/pgc_repository.dart';
import '../domain/pgc_resume_repository.dart';

/// Uses the existing progress owner without importing another feature's data.
final class LocalPgcResumeRepository implements PgcResumeRepository {
  const LocalPgcResumeRepository({
    required this.resumeEnabled,
    required this.latestEpisode,
  });

  final Future<bool> Function() resumeEnabled;
  final Future<String?> Function(String scope, Iterable<String> episodeIds)
  latestEpisode;

  @override
  Future<PgcEpisodeId?> resumeEpisode(
    PgcSeason season, {
    required String scope,
    required RequestCancellation cancellation,
  }) async {
    if (cancellation.isCancelled || !await resumeEnabled()) return null;
    if (cancellation.isCancelled) return null;
    final local = await latestEpisode(
      scope,
      season.episodes.map((episode) => episode.episodeId),
    );
    if (cancellation.isCancelled || !await resumeEnabled()) return null;
    final localId = local == null ? null : PgcEpisodeId(local);
    if (season.episode(localId) != null) return localId;
    // Guest responses must never restore another account's cloud history.
    return scope.startsWith('user:') &&
            season.episode(season.lastEpisodeId) != null
        ? season.lastEpisodeId
        : null;
  }
}
