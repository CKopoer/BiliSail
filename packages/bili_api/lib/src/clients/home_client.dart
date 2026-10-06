import '../mappers/dynamic_post_parser.dart';
import '../api_client.dart';
import '../models.dart';
import '../models/home_models.dart';

/// Web home endpoints. Credentials/retry/deadline stay in the client.
final class HomeClient {
  HomeClient(this.api);
  final BiliApiClient api;
  static const _liveAreaPageSize = 36;

  /// Explicit user action; the shared CSRF form pipeline sends only one attempt.
  Future<void> unsubscribeFavorite(
    String id, {
    required bool collection,
    ApiRequestContext? context,
  }) async {
    _validateId(id);
    await api.submitForm(
      collection ? '/x/v3/fav/season/unfav' : '/x/v3/fav/folder/unfav',
      'favorite_unsubscribe',
      {
        if (collection) ...{
          'season_id': id,
          'platform': 'web',
        } else
          'media_id': id,
      },
      context: context,
    );
  }

  Future<ApiPage<ApiHomeEntry>> load({
    required String channel,
    required String section,
    required int page,
    String? cursor,
    String? mid,
    String? folderId,
    ApiRequestContext? context,
  }) async {
    if (page < 1) throw ArgumentError.value(page, 'page');
    Future<Map<String, Object?>> get(
      String path,
      Map<String, String> query, {
      bool live = false,
    }) => api.requestJson(
      Uri.https(
        live ? 'api.live.bilibili.com' : 'api.bilibili.com',
        path,
        query,
      ),
      'home_$channel',
      context: context,
    );
    if (channel == 'watchLater') {
      final data = await get('/x/v2/history/toview', {});
      final entries =
          _list(data['list'], nullable: true)
              .where(
                (item) =>
                    section != '未看完' || _number(_map(item)['progress']) != -1,
              )
              .map((item) => _video(item, allowUnavailable: true))
              .toList();
      return ApiPage(List.unmodifiable(entries), hasMore: false);
    }
    if (channel == 'favorites') {
      if (folderId != null) {
        // Keep UGC collections distinct from favorite media IDs in queries.
        final collection = folderId.startsWith('ugc:');
        final id = collection ? folderId.substring(4) : folderId;
        _validateId(id);
        final data = await get(
          collection ? '/x/space/fav/season/list' : '/x/v3/fav/resource/list',
          {
            if (collection) 'season_id': id else 'media_id': id,
            if (collection && mid != null) 'mid': mid,
            'pn': '$page',
            'ps': '20',
            'platform': 'web',
          },
        );
        return _favoritePage(data, page);
      }
      if (mid == null) {
        throw const ApiFailure(
          ApiFailureCategory.authentication,
          'home_favorites',
        );
      }
      _validateId(mid);
      if (section == '我的追番' || section == '我的追剧') {
        return _follow(mid, section == '我的追剧', page, context);
      }
      final subscribed = section == '我的收藏与订阅';
      String? defaultId;
      if (!subscribed) {
        // The server identifies the default folder; titles/order can change.
        defaultId = cursor;
        if (defaultId == null) {
          final gallery = await get('/x/v3/fav/folder/space/v2', {
            'up_mid': mid,
          });
          final folder = _map(gallery['default_folder']);
          defaultId = _favoriteId(
            (_optionalMap(folder['folder_detail']) ??
                _map(folder['info']))['id'],
          );
        }
        _validateId(defaultId);
        if (section == '默认收藏夹') {
          final data = await get('/x/v3/fav/resource/list', {
            'media_id': defaultId,
            'pn': '$page',
            'ps': '20',
            'platform': 'web',
          });
          return _favoritePage(data, page, nextCursor: defaultId);
        }
      }
      final data = await get(
        subscribed
            ? '/x/v3/fav/folder/collected/list'
            : '/x/v3/fav/folder/created/list',
        {'up_mid': mid, 'pn': '$page', 'ps': '20', 'platform': 'web'},
      );
      final items = _list(data['list'], nullable: data['count'] == 0)
          .where((item) => _id(_map(item)['id']) != defaultId)
          .map(_favoriteFolder);
      return ApiPage(
        List.unmodifiable(items),
        hasMore: _hasMore(data, page, _number(data['count'])),
        nextCursor: defaultId,
      );
    }
    if (channel == 'dynamic' || channel == 'videoDynamic') {
      final data = await get('/x/polymer/web-dynamic/v1/feed/all', {
        'type': channel == 'videoDynamic' || section == '视频' ? 'video' : 'all',
        'page': '$page',
        // Current Web responses omit draw text unless the Opus shape is requested.
        'features': 'itemOpusStyle',
        if (cursor != null) 'offset': cursor,
      });
      final entries = _list(data['items'])
          .take(100)
          .where(
            (item) =>
                section != '图文' ||
                const {
                  'DYNAMIC_TYPE_DRAW',
                  'DYNAMIC_TYPE_WORD',
                  'DYNAMIC_TYPE_ARTICLE',
                }.contains(_map(item)['type']),
          )
          .map((item) {
            final m = _map(item);
            final post = parseDynamicPost(m, 'home_$channel');
            final video = post.video;
            final content = _optionalMap(
              _optionalMap(m['modules'])?['module_dynamic'],
            );
            final major = _optionalMap(content?['major']);
            final archive = _optionalMap(major?['archive']);
            final stat = _optionalMap(archive?['stat']);
            return ApiHomeEntry(
              id: post.id,
              title:
                  video?.title ??
                  (post.title.isNotEmpty
                      ? post.title
                      : post.linkTitle.isEmpty
                      ? post.authorName
                      : post.linkTitle),
              kind:
                  video == null
                      ? ApiHomeEntryKind.dynamic
                      : ApiHomeEntryKind.video,
              dynamicPost: post,
              coverUrl:
                  video?.coverUrl ??
                  post.imageUrls.firstOrNull ??
                  post.linkCoverUrl,
              subtitle: post.authorName,
              authorName: post.authorName,
              authorAvatarUrl: post.authorAvatarUrl,
              authorMid: post.authorId,
              duration: video?.duration,
              publishedAt: post.publishedAt,
              publishText: post.publishText,
              playCountText: _display(stat?['play']),
              danmakuCountText: _display(stat?['danmaku']),
              description: post.text,
              bvid: video?.bvid,
              url: post.linkUrl,
            );
          });
      final next = _text(data['offset']);
      if (_yes(data['has_more']) && (next == null || next == cursor)) {
        throw const ApiFailure(ApiFailureCategory.protocol, 'home_dynamic');
      }
      return ApiPage(
        List.unmodifiable(entries),
        hasMore: _yes(data['has_more']),
        nextCursor: next,
      );
    }
    if (channel == 'live') {
      if (section == '全部分区' && folderId == null) {
        final data = await get('/room/v1/Area/getList', {}, live: true);
        return ApiPage(
          List.unmodifiable(
            _list(data['list']).map((item) {
              final m = _map(item);
              return ApiHomeEntry(
                id: _id(m['id']),
                title: _required(m['name']),
                kind: ApiHomeEntryKind.folder,
                subtitle: '查看此分区的直播',
                children: List.unmodifiable(
                  _list(m['list'], nullable: true).map((raw) {
                    final child = _map(raw);
                    return ApiHomeEntry(
                      id: '${_id(m['id'])}:${_id(child['id'])}',
                      title: _required(child['name']),
                      kind: ApiHomeEntryKind.folder,
                    );
                  }),
                ),
              );
            }),
          ),
          hasMore: false,
        );
      }
      if (section == '观看记录') {
        final parts = cursor?.split(':');
        final data = await get('/x/web-interface/history/cursor', {
          'type': 'live',
          'ps': '20',
          if (parts != null && parts.length == 2) ...{
            'max': parts[0],
            'view_at': parts[1],
            'business': 'live',
          },
        });
        final items = _list(data['list']).map((raw) {
          final m = _map(raw);
          final h = _map(m['history']);
          final id = _id(h['oid']);
          return ApiHomeEntry(
            id: id,
            title: _required(m['title']),
            kind: ApiHomeEntryKind.live,
            coverUrl: _uri(m['cover']),
            subtitle: _text(m['author_name']) ?? '',
            url: Uri.https('live.bilibili.com', '/$id'),
          );
        });
        final next = _map(data['cursor']);
        final nextCursor = '${next['max']}:${next['view_at']}';
        return ApiPage(
          List.unmodifiable(items),
          hasMore: (_number(next['max']) ?? 0) != 0 && nextCursor != cursor,
          nextCursor: nextCursor,
        );
      }
      if (section == '我的关注') {
        final data = await get('/xlive/web-ucenter/v1/xfetter/GetWebList', {
          'page': '$page',
          'page_size': '20',
        }, live: true);
        return ApiPage(
          List.unmodifiable(_list(data['rooms'], nullable: true).map(_live)),
          hasMore: page * 20 < (_number(data['count']) ?? 0),
        );
      }
      if (folderId == null && (section == '推荐直播' || section == '推荐')) {
        final data = await get('/xlive/web-interface/v1/index/getList', {
          'platform': 'web',
        }, live: true);
        final rooms = <Object?>[
          ..._list(data['recommend_room_list'], nullable: true),
        ];
        for (final module in _list(data['room_list'], nullable: true)) {
          rooms.addAll(_list(_map(module)['list'], nullable: true));
        }
        final entries = <String, ApiHomeEntry>{};
        for (final room in rooms) {
          final raw = _map(room);
          // Homepage can carry promoted non-room cards. Only actual room IDs
          // enter this room list; malformed room content still fails parsing.
          final id = raw['roomid'] ?? raw['room_id'];
          if (id == null || id == 0 || id == '0' || _yes(raw['is_ad'])) {
            continue;
          }
          final entry = _live(raw);
          entries.putIfAbsent(entry.id, () => entry);
        }
        // This endpoint supplies one homepage snapshot, not a paged feed.
        return ApiPage(List.unmodifiable(entries.values), hasMore: false);
      }
      final area = _liveArea(folderId);
      // This read-only room-list endpoint is verified with Web guest parameters.
      // Its pagination uses count rather than second/getList's has_more.
      final data = await get('/room/v3/Area/getRoomList', {
        'platform': 'web',
        'parent_area_id': area.parentId,
        'area_id': area.areaId,
        'sort_type': 'online',
        'page': '$page',
        'page_size': '$_liveAreaPageSize',
      }, live: true);
      final count = _number(data['count']);
      if (count == null || count < 0) {
        throw const ApiFailure(ApiFailureCategory.protocol, 'home_live');
      }
      return ApiPage(
        List.unmodifiable(_list(data['list']).map(_live)),
        hasMore: page * _liveAreaPageSize < count,
      );
    }
    final type =
        channel == 'bangumi'
            ? 1
            : channel == 'guochuang'
            ? 4
            : switch (section) {
              '电视剧' => 2,
              '纪录片' => 3,
              '综艺' => 7,
              _ => 5,
            };
    if (section == '我的追番' || section == '我的追剧') {
      if (mid == null) {
        throw const ApiFailure(
          ApiFailureCategory.authentication,
          'home_follow',
        );
      }
      return _follow(mid, section == '我的追剧', page, context);
    }
    if (section == '时间表') {
      final data = await get('/pgc/web/timeline', {
        'types': '$type',
        'before': '6',
        'after': '6',
      });
      final entries = <ApiHomeEntry>[];
      for (final day in _list(data['list'])) {
        final m = _map(day);
        for (final raw in _list(m['episodes'])) {
          final episode = _map(raw);
          final season = _season(episode);
          entries.add(
            ApiHomeEntry(
              id: '${season.id}:${episode['episode_id']}',
              title: season.title,
              kind: season.kind,
              coverUrl: season.coverUrl,
              subtitle:
                  '${m['date'] ?? ''} ${episode['pub_time'] ?? ''} · ${episode['pub_index'] ?? ''}',
              url: season.url,
            ),
          );
        }
      }
      return ApiPage(List.unmodifiable(entries), hasMore: false);
    }
    // The index endpoint exposes native PGC content, rather than UGC popular.
    final data = await get('/pgc/season/index/result', {
      'season_type': '$type',
      'page': '$page',
      'pagesize': '20',
      'type': '1',
      'order': section == '推荐' ? '2' : '0',
      'sort': '0',
    });
    return ApiPage(
      List.unmodifiable(_list(data['list'], nullable: true).map(_season)),
      hasMore: _yes(data['has_next']),
    );
  }

  Future<ApiPage<ApiHomeEntry>> _follow(
    String mid,
    bool cinema,
    int page,
    ApiRequestContext? context,
  ) async {
    _validateId(mid);
    final data = await api.requestJson(
      Uri.https('api.bilibili.com', '/x/space/bangumi/follow/list', {
        'vmid': mid,
        'type': cinema ? '2' : '1',
        'pn': '$page',
        'ps': '20',
      }),
      'home_follow',
      context: context,
    );
    final total = _number(data['total']);
    if (total == null || total < 0) {
      throw const ApiFailure(ApiFailureCategory.protocol, 'home_follow');
    }
    return ApiPage(
      List.unmodifiable(_list(data['list'], nullable: total == 0).map(_season)),
      hasMore: page * 20 < total,
      totalCount: total,
    );
  }

  static ApiPage<ApiHomeEntry> _favoritePage(
    Map<String, Object?> data,
    int page, {
    String? nextCursor,
  }) {
    final total = _number(_optionalMap(data['info'])?['media_count']);
    final items = _list(
      data['medias'],
      nullable: total == 0,
    ).map(_favoriteResource).toList(growable: false);
    return ApiPage(
      List.unmodifiable(items),
      // The collection endpoint may return the whole collection, ignoring ps.
      // Stop after all advertised media have arrived, even on an oversized page.
      hasMore:
          _hasMore(data, page, total) &&
          items.isNotEmpty &&
          (total == null || items.length < total),
      totalCount: total,
      nextCursor: nextCursor,
    );
  }

  static bool _hasMore(Map<String, Object?> data, int page, int? total) {
    final more = data['has_more'];
    if (more is bool || more == 0 || more == 1) return _yes(more);
    if (more == null && total != null && total >= 0) return page * 20 < total;
    throw const ApiFailure(ApiFailureCategory.protocol, 'home_favorites');
  }

  static ApiHomeEntry _favoriteFolder(Object? item) {
    final m = _map(item);
    final collection = _number(m['type']) == 21;
    final id = _favoriteId(m['id']);
    final attr = _number(m['attr']);
    return ApiHomeEntry(
      id: id,
      title: _required(m['title']),
      kind: collection ? ApiHomeEntryKind.collection : ApiHomeEntryKind.folder,
      coverUrl: _uri(m['cover']),
      contentCount: _number(m['media_count']),
      viewCount: _number(m['view_count']),
      isPrivate: attr == null ? null : (attr & 2) != 0,
      createdAt: _date(m['ctime']),
      authorName: _text(_optionalMap(m['upper'])?['name']) ?? '',
    );
  }

  static ApiHomeEntry _favoriteResource(Object? item) {
    final m = _map(item);
    if (_text(m['bvid']) == null ||
        m['title'] == '已失效视频' ||
        (_number(m['attr']) ?? 0) & 1 != 0 ||
        m['type'] != null && _number(m['type']) != 2) {
      return ApiHomeEntry(
        id: _id(m['id']),
        title: _text(m['title']) ?? '已失效内容',
        kind: ApiHomeEntryKind.video,
        coverUrl: _uri(m['cover']),
        subtitle: '内容已失效或不支持在此播放',
      );
    }
    return _video(item);
  }

  static ApiHomeEntry _video(Object? item, {bool allowUnavailable = false}) {
    final m = _map(item);
    final rawBvid = _text(m['bvid']);
    final bvid =
        rawBvid != null && RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(rawBvid)
            ? rawBvid
            : null;
    final aid = _positiveId(m['aid']);
    if (bvid == null && (!allowUnavailable || aid == null)) {
      throw const ApiFailure(ApiFailureCategory.protocol, 'home_video');
    }
    final owner = _optionalMap(m['owner']) ?? _optionalMap(m['upper']);
    final stat = _optionalMap(m['cnt_info']) ?? _optionalMap(m['stat']);
    return ApiHomeEntry(
      id: bvid ?? 'aid:$aid',
      title:
          bvid == null ? _text(m['title']) ?? '已失效内容' : _required(m['title']),
      kind: ApiHomeEntryKind.video,
      coverUrl: _uri(m['pic'] ?? m['cover']),
      subtitle: bvid == null ? '内容已失效或不支持在此播放' : _text(owner?['name']) ?? '',
      authorName: _text(owner?['name']) ?? '',
      authorMid: _positiveId(owner?['mid']),
      duration: Duration(seconds: _number(m['duration']) ?? 0),
      // Watch-later uses stat.view; favorite resources use cnt_info.play.
      playCountText: _display(stat?['view'] ?? stat?['play']),
      danmakuCountText: _display(stat?['danmaku']),
      publishedAt: _date(m['pubtime'] ?? m['pubdate']),
      bvid: bvid,
      aid: aid,
      previewCid: _positiveId(m['cid']),
    );
  }

  static ApiHomeEntry _season(Object? item) {
    final m = _map(item);
    final id = _id(m['season_id']);
    return ApiHomeEntry(
      id: id,
      title: _required(m['title']),
      kind: ApiHomeEntryKind.season,
      coverUrl: _uri(m['cover']),
      subtitle:
          _text(m['index_show']) ??
          _text(_optionalMap(m['new_ep'])?['index_show']) ??
          '',
      url: Uri.https('www.bilibili.com', '/bangumi/play/ss$id'),
    );
  }

  static ApiHomeEntry _live(Object? item) {
    final m = _map(item);
    final id = _id(m['roomid'] ?? m['room_id']);
    return ApiHomeEntry(
      id: id,
      title: _required(m['title']),
      kind: ApiHomeEntryKind.live,
      coverUrl:
          _uri(m['cover']) ??
          _uri(m['user_cover']) ??
          _uri(m['keyframe']) ??
          _uri(m['system_cover']),
      subtitle: _text(m['uname']) ?? '',
      authorName: _text(m['uname']) ?? '',
      authorAvatarUrl: _uri(m['face']),
      authorMid: _positiveId(m['mid']) ?? _positiveId(m['uid']),
      popularityText: _display(m['online']),
      areaName:
          _text(m['area_name']) ??
          _text(m['area_v2_name']) ??
          _text(m['area_v2_parent_name']) ??
          '',
      url: Uri.https('live.bilibili.com', '/$id'),
    );
  }

  static ({String parentId, String areaId}) _liveArea(String? folderId) {
    if (folderId == null) return (parentId: '0', areaId: '0');
    final match = RegExp(
      r'^([1-9][0-9]*)(?::([1-9][0-9]*))?$',
    ).firstMatch(folderId);
    if (match == null) {
      throw ArgumentError.value(folderId, 'folderId', 'Invalid live area');
    }
    return (parentId: _required(match[1]), areaId: match[2] ?? '0');
  }

  static String _display(Object? value) =>
      value is String
          ? value
          : value is int
          ? '$value'
          : '';
  static Map<String, Object?> _map(Object? value) =>
      value is Map<String, Object?>
          ? value
          : throw const ApiFailure(ApiFailureCategory.protocol, 'home');
  static Map<String, Object?>? _optionalMap(Object? value) =>
      value is Map<String, Object?> ? value : null;
  static List<Object?> _list(Object? value, {bool nullable = false}) =>
      value is List<Object?>
          ? value
          : value == null && nullable
          ? const []
          : throw const ApiFailure(ApiFailureCategory.protocol, 'home');
  static String? _positiveId(Object? value) {
    final text =
        value is int
            ? value.toString()
            : value is String
            ? value
            : null;
    return text != null && RegExp(r'^[1-9][0-9]*$').hasMatch(text)
        ? text
        : null;
  }

  static String? _text(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
  static String _required(Object? value) =>
      _text(value) ??
      (throw const ApiFailure(ApiFailureCategory.protocol, 'home'));
  static String _id(Object? value) =>
      value is int && value > 0 ? '$value' : _required(value);
  static int? _number(Object? value) => value is int ? value : null;
  static void _validateId(String value) {
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(value)) {
      throw ArgumentError.value(value, 'id', 'Invalid favorite identity');
    }
  }

  static String _favoriteId(Object? value) {
    final id = _id(value);
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(id)) {
      throw const ApiFailure(ApiFailureCategory.protocol, 'home_favorites');
    }
    return id;
  }

  static DateTime? _date(Object? value) {
    final seconds = _number(value);
    return seconds != null && seconds > 0 && seconds < 8640000000000
        ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
        : null;
  }

  static bool _yes(Object? value) => value == true || value == 1;
  static Uri? _uri(Object? value) {
    final text = _text(value);
    if (text == null) return null;
    final uri = Uri.tryParse(text.startsWith('//') ? 'https:$text' : text);
    return uri != null && (uri.scheme == 'https' || uri.scheme == 'http')
        ? uri.replace(scheme: 'https')
        : null;
  }
}
