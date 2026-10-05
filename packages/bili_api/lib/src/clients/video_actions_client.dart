import '../api_client.dart';
import '../models.dart';

final class ApiVideoActionState {
  const ApiVideoActionState({
    required this.liked,
    required this.coins,
    required this.favorited,
  });
  final bool liked;
  final int coins;
  final bool favorited;
}

final class ApiFavoriteFolder {
  const ApiFavoriteFolder({
    required this.id,
    required this.title,
    required this.containsVideo,
  });
  final String id;
  final String title;
  final bool containsVideo;
}

/// Web Cookie/CSRF endpoints. No App token assumptions or mutation retries.
final class VideoActionsClient {
  const VideoActionsClient(this.api);
  final BiliApiClient api;

  Future<ApiVideoActionState> loadState(
    String bvid,
    String aid, {
    ApiRequestContext? context,
  }) async {
    _target(bvid, aid);
    const endpoint = 'video_action_state';
    final values = await Future.wait([
      api.requestValue(
        Uri.https('api.bilibili.com', '/x/web-interface/archive/has/like', {
          'bvid': bvid,
        }),
        endpoint,
        context: context,
      ),
      api.requestJson(
        Uri.https('api.bilibili.com', '/x/web-interface/archive/coins', {
          'bvid': bvid,
        }),
        endpoint,
        context: context,
      ),
      api.requestJson(
        Uri.https('api.bilibili.com', '/x/v2/fav/video/favoured', {'aid': aid}),
        endpoint,
        context: context,
      ),
    ]);
    final like = values[0];
    final coins = values[1];
    final fav = values[2];
    if (like is! int ||
        coins is! Map<String, Object?> ||
        fav is! Map<String, Object?> ||
        coins['multiply'] is! int ||
        fav['favoured'] is! bool) {
      throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    return ApiVideoActionState(
      liked: like == 1,
      coins: coins['multiply'] as int,
      favorited: fav['favoured'] as bool,
    );
  }

  Future<List<ApiFavoriteFolder>> folders(
    String mid,
    String aid, {
    ApiRequestContext? context,
  }) async {
    _id(mid);
    _id(aid);
    const endpoint = 'favorite_folders';
    final data = await api.requestJson(
      Uri.https('api.bilibili.com', '/x/v3/fav/folder/created/list-all', {
        'up_mid': mid,
        'rid': aid,
        'type': '2',
      }),
      endpoint,
      context: context,
    );
    final raw = data['list'];
    if (raw == null) return const [];
    if (raw is! List || raw.length > 1000) {
      throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    return List.unmodifiable(
      raw.map((value) {
        if (value is! Map<String, Object?> ||
            value['title'] is! String ||
            (value['id'] is! int && value['id'] is! String) ||
            value['fav_state'] is! int) {
          throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
        }
        final id = '${value['id']}';
        _id(id);
        return ApiFavoriteFolder(
          id: id,
          title: value['title'] as String,
          containsVideo: value['fav_state'] == 1,
        );
      }),
    );
  }

  Future<void> like(
    String bvid,
    bool liked, {
    ApiRequestContext? context,
  }) async {
    _bvid(bvid);
    await api.submitForm('/x/web-interface/archive/like', 'video_like', {
      'bvid': bvid,
      'like': liked ? '1' : '2',
    }, context: context);
  }

  Future<void> coin(
    String bvid,
    int count, {
    ApiRequestContext? context,
  }) async {
    _bvid(bvid);
    if (count < 1 || count > 2) throw ArgumentError('Invalid coin count');
    await api.submitForm('/x/web-interface/coin/add', 'video_coin', {
      'bvid': bvid,
      'multiply': '$count',
      'select_like': '0',
    }, context: context);
  }

  Future<void> favorite(
    String aid,
    List<String> add,
    List<String> remove, {
    ApiRequestContext? context,
  }) async {
    _id(aid);
    for (final id in [...add, ...remove]) {
      _id(id);
    }
    if (add.toSet().intersection(remove.toSet()).isNotEmpty ||
        add.length + remove.length > 1000) {
      throw ArgumentError('Invalid folders');
    }
    if (add.isEmpty && remove.isEmpty) return;
    await api.submitForm('/x/v3/fav/resource/deal', 'video_favorite', {
      'rid': aid,
      'type': '2',
      'add_media_ids': add.join(','),
      'del_media_ids': remove.join(','),
    }, context: context);
  }

  Future<void> watchLater(String bvid, {ApiRequestContext? context}) async {
    _bvid(bvid);
    await api.submitForm('/x/v2/history/toview/add', 'watch_later_add', {
      'bvid': bvid,
    }, context: context);
  }

  Future<void> sendDanmaku(
    String bvid,
    String cid,
    String message,
    Duration position, {
    int mode = 1,
    int color = 0xffffff,
    ApiRequestContext? context,
  }) async {
    _bvid(bvid);
    _id(cid);
    if (message.trim().isEmpty ||
        message.runes.length > 100 ||
        position.isNegative ||
        !const [1, 4, 5].contains(mode) ||
        color < 0 ||
        color > 0xffffff) {
      throw ArgumentError('Invalid danmaku');
    }
    await api.submitForm('/x/v2/dm/post', 'danmaku_send', {
      'bvid': bvid,
      'oid': cid,
      'type': '1',
      'msg': message,
      'progress': '${position.inMilliseconds}',
      'mode': '$mode',
      'color': '$color',
      'fontsize': '25',
      'pool': '0',
      'plat': '1',
      'rnd': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
    }, context: context);
  }

  static void _bvid(String bvid) {
    if (!RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(bvid)) {
      throw ArgumentError('Invalid video ID');
    }
  }

  static void _id(String value) {
    if (!RegExp(r'^[1-9]\d*$').hasMatch(value)) {
      throw ArgumentError('Invalid ID');
    }
  }

  static void _target(String bvid, String aid) {
    _bvid(bvid);
    _id(aid);
  }
}
