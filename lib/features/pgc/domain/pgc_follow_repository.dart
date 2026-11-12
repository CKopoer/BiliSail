import '../../../domain/request_cancellation.dart';
import 'pgc_repository.dart';

final class PgcFollowWriteUncertain implements Exception {
  const PgcFollowWriteUncertain();
}

abstract interface class PgcFollowRepository {
  String get accountScope;
  int get sessionEpoch;

  Future<bool> isFollowed(PgcSeasonId id, RequestCancellation cancellation);
  Future<void> setFollowed(
    PgcSeasonId id,
    bool followed,
    RequestCancellation cancellation,
  );
}
