import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/playback_history_repository.dart';

final class ApiPlaybackHistoryRepository implements PlaybackHistoryRepository {
  ApiPlaybackHistoryRepository(
    this.client,
    this.requests, {
    required this.accountScope,
  });
  final PlaybackHistoryClient client;
  final ApiRequests requests;
  final String Function() accountScope;

  void _check(String scope) {
    if (scope != accountScope()) {
      throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
    }
    if (!scope.startsWith('user:')) {
      throw const AppFailure(AppFailureKind.authentication, '请先登录');
    }
  }

  @override
  Future<Duration?> read(
    PlaybackHistoryTarget target, {
    required String scope,
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    _check(scope);
    final value = await client.read(
      target.video.value,
      target.cid,
      episodeId: target.episodeId,
      seasonId: target.seasonId,
      context: context,
    );
    _check(scope);
    return value;
  }, cancellation: cancellation);

  @override
  Future<void> report(
    PlaybackHistoryRecord record, {
    required String scope,
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    _check(scope);
    final target = record.target;
    await client.report(
      target.video.value,
      target.cid,
      position: record.position,
      duration: record.duration,
      completed: record.completed,
      episodeId: target.episodeId,
      seasonId: target.seasonId,
      context: context,
    );
    _check(scope);
  }, cancellation: cancellation);
}
