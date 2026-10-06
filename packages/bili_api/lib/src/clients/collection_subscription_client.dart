import '../api_client.dart';
import '../models.dart';

/// Web UGC collection subscription state and explicit mutations.
final class CollectionSubscriptionClient {
  const CollectionSubscriptionClient(this.api);
  final BiliApiClient api;

  Future<bool> isSubscribed(
    String bvid, {
    String? aid,
    ApiRequestContext? context,
  }) async {
    if (!RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(bvid)) {
      throw ArgumentError.value(bvid, 'bvid', 'Invalid video ID');
    }
    if (aid != null) _validateId(aid, 'aid');
    const endpoint = 'collection_subscription_state';
    final data = await api.requestJson(
      Uri.https('api.bilibili.com', '/x/web-interface/archive/relation', {
        'bvid': bvid,
        'aid': ?aid,
      }),
      endpoint,
      context: context,
    );
    return switch (data['season_fav']) {
      final bool subscribed => subscribed,
      _ => throw const ApiFailure(ApiFailureCategory.protocol, endpoint),
    };
  }

  /// A user click sends one CSRF form; callers reconcile unknown outcomes.
  Future<void> setSubscribed(
    String seasonId,
    bool subscribed, {
    ApiRequestContext? context,
  }) async {
    _validateId(seasonId, 'seasonId');
    await api.submitForm(
      subscribed ? '/x/v3/fav/season/fav' : '/x/v3/fav/season/unfav',
      'collection_subscription_write',
      {'season_id': seasonId, 'platform': 'web'},
      context: context,
    );
  }

  static void _validateId(String id, String name) {
    if (!RegExp(r'^[1-9]\d*$').hasMatch(id)) {
      throw ArgumentError.value(id, name, 'Invalid ID');
    }
  }
}
