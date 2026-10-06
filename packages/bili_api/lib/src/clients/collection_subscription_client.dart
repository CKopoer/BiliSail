import '../api_client.dart';
import '../models.dart';

/// Web UGC collection subscription state and explicit mutations.
final class CollectionSubscriptionClient {
  const CollectionSubscriptionClient(this.api);
  final BiliApiClient api;

  Future<bool> isSubscribed(
    String seasonId, {
    required String mid,
    ApiRequestContext? context,
  }) async {
    _validateId(seasonId);
    _validateId(mid);
    const endpoint = 'collection_subscription_state';
    const pageSize = 20;
    final seen = <(int, String)>{};
    // Only the current account's collected list proves membership. The
    // season-detail `info` omits fav_state, even when its ID is correct.
    for (var page = 1; page <= 100; page++) {
      final data = await api.requestJson(
        Uri.https('api.bilibili.com', '/x/v3/fav/folder/collected/list', {
          'up_mid': mid,
          'pn': '$page',
          'ps': '$pageSize',
          'platform': 'web',
        }),
        endpoint,
        context: context,
      );
      final count = _count(data['count']);
      final rawItems = data['list'];
      if (count == null ||
          rawItems is! List<Object?> && !(count == 0 && rawItems == null)) {
        throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
      }
      final items = rawItems is List<Object?> ? rawItems : const <Object?>[];
      final previousCount = seen.length;
      for (final item in items) {
        if (item is! Map<String, Object?>) {
          throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
        }
        final type = item['type'];
        final itemId = item['id'];
        if (type is! int ||
            (itemId is! int && itemId is! String) ||
            !RegExp(r'^[1-9]\d*$').hasMatch('$itemId')) {
          throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
        }
        seen.add((type, '$itemId'));
        if (type == 21 && '$itemId' == seasonId) return true;
      }
      final hasMore = switch (data['has_more']) {
        true || 1 => true,
        false || 0 => false,
        null => page * pageSize < count,
        _ => throw const ApiFailure(ApiFailureCategory.protocol, endpoint),
      };
      if (!hasMore) {
        if (seen.length < count) {
          throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
        }
        return false;
      }
      if (seen.length == previousCount) {
        throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
      }
    }
    // An incomplete list cannot prove that the target is not subscribed.
    throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
  }

  /// A user click sends one CSRF form; callers reconcile unknown outcomes.
  Future<void> setSubscribed(
    String seasonId,
    bool subscribed, {
    ApiRequestContext? context,
  }) async {
    _validateId(seasonId);
    await api.submitForm(
      subscribed ? '/x/v3/fav/season/fav' : '/x/v3/fav/season/unfav',
      'collection_subscription_write',
      {'season_id': seasonId, 'platform': 'web'},
      context: context,
    );
  }

  static void _validateId(String id) {
    if (!RegExp(r'^[1-9]\d*$').hasMatch(id)) {
      throw ArgumentError.value(id, 'seasonId', 'Invalid collection ID');
    }
  }

  static int? _count(Object? value) => switch (value) {
    int count when count >= 0 => count,
    String text => switch (int.tryParse(text)) {
      final int count when count >= 0 => count,
      _ => null,
    },
    _ => null,
  };
}
