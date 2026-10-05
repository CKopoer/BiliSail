import '../mappers/dynamic_post_parser.dart';
import '../api_client.dart';
import '../models.dart';
import '../models/home_models.dart';

/// Web read-only home endpoints. Credentials/retry/deadline stay in the client.
final class HomeClient {
  HomeClient(this.api);
  final BiliApiClient api;
  static const _liveAreaPageSize = 36;

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
              .map(_video)
              .toList();
      return ApiPage(List.unmodifiable(entries), hasMore: false);
    }
    if (channel == 'favorites') {
      if (folderId != null) {
        final data = await get('/x/v3/fav/resource/list', {
          'media_id': folderId,
          'pn': '$page',
          'ps': '20',
          'platform': 'web',
        });
        return ApiPage(
          List.unmodifiable(
            _list(data['medias'], nullable: true).map(_favoriteResource),
          ),
          hasMore: _yes(data['has_more']),
        );
      }
      if (mid == null) {
        throw const ApiFailure(
          ApiFailureCategory.authentication,
          'home_favorites',
        );
      }
      final subscribed = section == '订阅收藏夹';
      final data = await get(
        subscribed
            ? '/x/v3/fav/folder/collected/list'
            : '/x/v3/fav/folder/created/list',
        {'up_mid': mid, 'pn': '$page', 'ps': '20'},
      );
      final items = _list(data['list'], nullable: true).map((item) {
        final m = _map(item);
        return ApiHomeEntry(
          id: _id(m['id']),
          title: _required(m['title']),
          kind: ApiHomeEntryKind.folder,
          coverUrl: _uri(m['cover']),
          subtitle: '${m['media_count'] ?? 0} 个内容',
        );
      });
      return ApiPage(List.unmodifiable(items), hasMore: _yes(data['has_more']));
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
    if (section == '我的追番') {
      if (mid == null) {
        throw const ApiFailure(
          ApiFailureCategory.authentication,
          'home_follow',
        );
      }
      final data = await get('/x/space/bangumi/follow/list', {
        'vmid': mid,
        'type': '1',
        'pn': '$page',
        'ps': '20',
      });
      return ApiPage(
        List.unmodifiable(_list(data['list'], nullable: true).map(_season)),
        hasMore: page * 20 < (_number(data['total']) ?? 0),
      );
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

  static ApiHomeEntry _favoriteResource(Object? item) {
    final m = _map(item);
    if (_text(m['bvid']) == null || m['title'] == '已失效视频') {
      return ApiHomeEntry(
        id: _id(m['id']),
        title: _text(m['title']) ?? '已失效内容',
        kind: ApiHomeEntryKind.video,
        subtitle: '内容已失效或不支持在此播放',
      );
    }
    return _video(item);
  }

  static ApiHomeEntry _video(Object? item) {
    final m = _map(item);
    final bvid = _required(m['bvid']);
    final owner = _optionalMap(m['owner']) ?? _optionalMap(m['upper']);
    return ApiHomeEntry(
      id: bvid,
      title: _required(m['title']),
      kind: ApiHomeEntryKind.video,
      coverUrl: _uri(m['pic'] ?? m['cover']),
      subtitle: _text(owner?['name']) ?? '',
      bvid: bvid,
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
      authorMid: _userMid(m['mid']) ?? _userMid(m['uid']),
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
  static String? _userMid(Object? value) {
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
