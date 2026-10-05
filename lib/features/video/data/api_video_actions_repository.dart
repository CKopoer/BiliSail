import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/video_actions_repository.dart';

final class ApiVideoActionsRepository implements VideoActionsRepository {
  ApiVideoActionsRepository(
    this.client,
    this.requests, {
    required String Function() accountScope,
  }) : _scope = accountScope;
  final VideoActionsClient client;
  final ApiRequests requests;
  final String Function() _scope;
  @override
  String get accountScope => _scope();
  @override
  Future<VideoInteraction> load(
    VideoActionTarget target,
    RequestCancellation cancellation,
  ) => requests.run((context) async {
    final result = await client.loadState(
      target.id.value,
      target.aid,
      context: context,
    );
    return VideoInteraction(
      liked: result.liked,
      coins: result.coins,
      favorited: result.favorited,
    );
  }, cancellation: cancellation);
  @override
  Future<List<FavoriteFolder>> folders(
    VideoActionTarget target,
    RequestCancellation cancellation,
  ) => requests.run((context) async {
    final scope = accountScope;
    if (!scope.startsWith('user:')) {
      throw const ApiFailure(
        ApiFailureCategory.authentication,
        'favorite_folders',
      );
    }
    final entries = await client.folders(
      scope.substring(5),
      target.aid,
      context: context,
    );
    return List.unmodifiable(
      entries.map(
        (f) => FavoriteFolder(
          id: f.id,
          title: f.title,
          containsVideo: f.containsVideo,
        ),
      ),
    );
  }, cancellation: cancellation);
  Future<void> _write(
    Future<void> Function(ApiRequestContext) operation,
    RequestCancellation cancellation,
  ) => requests.run((context) async {
    try {
      await operation(context);
    } on ApiFailure catch (e) {
      if (context.cancellation?.isCancelled == true) rethrow;
      if (e.category == ApiFailureCategory.network ||
          e.category == ApiFailureCategory.timeout ||
          e.category == ApiFailureCategory.protocol ||
          e.category == ApiFailureCategory.http) {
        throw const UnknownWriteOutcome();
      }
      rethrow;
    }
  }, cancellation: cancellation);
  @override
  Future<void> like(VideoActionTarget t, bool liked, RequestCancellation c) =>
      _write((ctx) => client.like(t.id.value, liked, context: ctx), c);
  @override
  Future<void> coin(VideoActionTarget t, int count, RequestCancellation c) =>
      _write((ctx) => client.coin(t.id.value, count, context: ctx), c);
  @override
  Future<void> favorite(
    VideoActionTarget t,
    List<String> add,
    List<String> remove,
    RequestCancellation c,
  ) => _write((ctx) => client.favorite(t.aid, add, remove, context: ctx), c);
  @override
  Future<void> watchLater(VideoActionTarget t, RequestCancellation c) =>
      _write((ctx) => client.watchLater(t.id.value, context: ctx), c);
  @override
  Future<void> sendDanmaku(
    VideoActionTarget t,
    String cid,
    String message,
    Duration position,
    int mode,
    int color,
    RequestCancellation c,
  ) => _write(
    (ctx) => client.sendDanmaku(
      t.id.value,
      cid,
      message,
      position,
      mode: mode,
      color: color,
      context: ctx,
    ),
    c,
  );
}
