import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/pgc_danmaku_repository.dart';

/// Uses the same Web Cookie/CSRF write as UGC, without UGC interaction reads.
final class ApiPgcDanmakuRepository implements PgcDanmakuRepository {
  factory ApiPgcDanmakuRepository(
    VideoActionsClient client,
    ApiRequests requests, {
    required String Function() accountScope,
  }) => ApiPgcDanmakuRepository._(client, requests, accountScope);

  ApiPgcDanmakuRepository._(this.client, this.requests, this._accountScope);

  final VideoActionsClient client;
  final ApiRequests requests;
  final String Function() _accountScope;

  @override
  String get accountScope => _accountScope();
  @override
  int get sessionEpoch => requests.sessionEpoch;

  @override
  Future<void> send(
    PgcDanmakuTarget target,
    String text,
    Duration position, {
    required int mode,
    required int color,
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    try {
      await client.sendDanmaku(
        target.video.value,
        target.cid,
        text,
        position,
        mode: mode,
        color: color,
        context: context,
      );
    } on ApiFailure catch (error) {
      if (context.cancellation?.isCancelled == true) rethrow;
      if (const {
        ApiFailureCategory.network,
        ApiFailureCategory.timeout,
        ApiFailureCategory.protocol,
        ApiFailureCategory.http,
      }.contains(error.category)) {
        throw const PgcDanmakuWriteUncertain();
      }
      rethrow;
    }
  }, cancellation: cancellation);
}
