import 'dart:async';

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/pgc/domain/pgc_follow_repository.dart';
import 'package:bilisail/features/pgc/domain/pgc_repository.dart';

class PgcFollowFake implements PgcFollowRepository {
  @override
  String accountScope = 'user:7';
  @override
  int sessionEpoch = 1;
  bool followed = false;
  Object? readFailure, writeFailure;
  Completer<bool>? pendingRead;
  Completer<void>? pendingWrite;
  final reads = <PgcSeasonId>[];
  final writes = <(PgcSeasonId, bool)>[];
  RequestCancellation? lastCancellation;

  @override
  Future<bool> isFollowed(
    PgcSeasonId id,
    RequestCancellation cancellation,
  ) async {
    reads.add(id);
    lastCancellation = cancellation;
    if (readFailure case final error?) throw error;
    return pendingRead?.future ?? followed;
  }

  @override
  Future<void> setFollowed(
    PgcSeasonId id,
    bool followed,
    RequestCancellation cancellation,
  ) async {
    writes.add((id, followed));
    lastCancellation = cancellation;
    if (writeFailure case final error?) throw error;
    await pendingWrite?.future;
    this.followed = followed;
  }
}
