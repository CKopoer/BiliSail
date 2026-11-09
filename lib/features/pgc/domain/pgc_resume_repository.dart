import '../../../domain/request_cancellation.dart';
import 'pgc_repository.dart';

abstract interface class PgcResumeRepository {
  Future<PgcEpisodeId?> resumeEpisode(
    PgcSeason season, {
    required String scope,
    required RequestCancellation cancellation,
  });
}
