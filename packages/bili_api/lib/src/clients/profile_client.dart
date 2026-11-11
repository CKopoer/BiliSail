import '../mappers/dynamic_post_parser.dart';
import '../mappers/video_access_parser.dart';
import '../api_client.dart';
import '../models.dart';
import '../models/profile_models.dart';

/// Web space reads and explicit relationship writes. Privacy remains enforced.
final class ProfileClient {
  const ProfileClient(this.api);
  final BiliApiClient api;
  static const _size = 30;
  static const _collectionSize = 10;

  Future<void> report(
    String mid, {
    required Set<int> contents,
    int? reason,
    ApiRequestContext? context,
  }) => api.reportMember(
    mid,
    contents: contents,
    reason: reason,
    context: context,
  );

  Future<ApiProfileSpaceDetails> loadDetails(
    String mid, {
    ApiRequestContext? context,
  }) async {
    _id(mid);
    const e = 'profile_details';
    final data = await api.requestWbiJson(
      '/x/space/wbi/acc/info',
      {'mid': mid, 'platform': 'web', 'web_location': '1550101', 'token': ''},
      e,
      context: context,
    );
    if (_key(data['mid'], e) != mid) _fail(e);
    return ApiProfileSpaceDetails(
      bannerUrl:
          _uri(_optionalMap(data['top_photo_v2'])['l_img']) ??
          _uri(data['top_photo']),
      gender: _string(data['sex']),
      birthday: _string(data['birthday']),
    );
  }

  Future<ApiPage<ApiProfileEntry>> loadCollections(
    String mid, {
    required int page,
    ApiRequestContext? context,
  }) async {
    _id(mid);
    _page(page);
    const e = 'profile_collections';
    final data = await _get('/x/polymer/web-space/seasons_series_list', e, {
      'mid': mid,
      'page_num': '$page',
      'page_size': '$_collectionSize',
    }, context);
    final lists = _map(data['items_lists'], e);
    final total = _number(_map(lists['page'], e)['total']);
    if (total == null || total < 0) _fail(e);
    final entries = <ApiProfileEntry>[];
    for (final isSeries in [false, true]) {
      for (final value in _list(
        lists[isSeries ? 'series_list' : 'seasons_list'],
        e,
      )) {
        final meta = _map(_map(value, e)['meta'], e);
        final id = _key(meta[isSeries ? 'series_id' : 'season_id'], e);
        entries.add(
          ApiProfileEntry(
            id: '${isSeries ? 'series' : 'season'}:$id',
            kind: ApiProfileEntryKind.collection,
            collectionId: id,
            isSeries: isSeries,
            title: _text(meta['name'], e),
            subtitle: _string(meta['description']),
            coverUrl: _uri(meta['cover']),
            count: _number(meta['total']),
          ),
        );
      }
    }
    return _paged(entries, page, total, pageSize: _collectionSize);
  }

  Future<ApiPage<ApiProfileEntry>> loadCollectionVideos(
    String mid,
    String id, {
    required bool isSeries,
    required int page,
    ApiRequestContext? context,
  }) async {
    _id(mid);
    _id(id);
    _page(page);
    const e = 'profile_collection_videos';
    final data = await _get(
      isSeries
          ? '/x/series/archives'
          : '/x/polymer/web-space/seasons_archives_list',
      e,
      isSeries
          ? {
              'mid': mid,
              'series_id': id,
              'pn': '$page',
              'ps': '$_size',
              'sort': 'asc',
            }
          : {
              'mid': mid,
              'season_id': id,
              'page_num': '$page',
              'page_size': '$_size',
              'sort_reverse': 'false',
            },
      context,
    );
    final total = _number(_map(data['page'], e)['total']);
    if (total == null || total < 0) _fail(e);
    final items = _list(data['archives'], e).map((value) {
      final item = _map(value, e), stat = _optionalMap(_map(value, e)['stat']);
      return _video({
        ...item,
        'mid': mid,
        'play': stat['view'],
        'danmaku': stat['danmaku'],
      }, e);
    }).toList();
    return _paged(items, page, total);
  }

  Future<ApiPage<ApiProfileEntry>> loadFollowedSeasons(
    String mid, {
    required bool cinema,
    required int page,
    ApiRequestContext? context,
  }) async {
    _id(mid);
    _page(page);
    const e = 'profile_followed_seasons';
    final data = await _get('/x/space/bangumi/follow/list', e, {
      'vmid': mid,
      'type': cinema ? '2' : '1',
      'pn': '$page',
      'ps': '$_size',
    }, context);
    final total = _number(data['total']);
    if (total == null || total < 0) _fail(e);
    final items = _list(data['list'] ?? (total == 0 ? const [] : null), e).map((
      value,
    ) {
      final item = _map(value, e);
      final id = _key(item['season_id'], e);
      return ApiProfileEntry(
        id: id,
        seasonId: id,
        kind: ApiProfileEntryKind.season,
        title: _text(item['title'], e),
        subtitle: _string(
          item['index_show'] ?? _optionalMap(item['new_ep'])['index_show'],
        ),
        coverUrl: _uri(item['cover']),
      );
    }).toList();
    return _paged(items, page, total);
  }

  Future<Map<String, Object?>> _get(
    String path,
    String endpoint,
    Map<String, String> query,
    ApiRequestContext? context,
  ) => api.requestJson(
    Uri.https('api.bilibili.com', path, query),
    endpoint,
    context: context,
  );

  Future<ApiUserProfile> loadProfile(
    String mid, {
    ApiRequestContext? context,
  }) async {
    _id(mid);
    const e = 'profile';
    final data = await _get('/x/web-interface/card', e, {
      'mid': mid,
      'photo': 'true',
    }, context);
    final card = _map(data['card'], e);
    if (_key(card['mid'], e) != mid) _fail(e);
    final official = _optionalMap(card['official_verify']);
    final vip = _optionalMap(card['vip']);
    final label = _optionalMap(vip['label']);
    return ApiUserProfile(
      mid: mid,
      name: _text(card['name'], e),
      avatarUrl: _uri(card['face']),
      pendantUrl:
          _uri(_optionalMap(card['pendant'])['image_enhance']) ??
          _uri(_optionalMap(card['pendant'])['image']),
      bannerUrl:
          _uri(_optionalMap(data['space'])['l_img']) ??
          _uri(_optionalMap(data['space'])['s_img']),
      vipLabelImageUrl: label['use_img_label'] == true
          ? _uri(label['img_label_uri_hans_static']) ??
                _uri(label['img_label_uri_hans'])
          : null,
      vipStatus: _number(vip['status']),
      vipType: _number(vip['type']),
      signature: _string(card['sign']),
      level: _number(_optionalMap(card['level_info'])['current_level']),
      verifyType: _number(official['type']),
      verifyDescription: _string(official['desc']),
      vipLabel: _string(_optionalMap(vip['label'])['text']),
      followerCount: _number(data['follower'] ?? card['fans']),
      followingCount: _number(card['attention']),
      likeCount: _number(data['like_num']),
      videoCount: _number(data['archive_count']),
    );
  }

  /// The public user card does not contain a live room. A successful null
  /// result means the user has not opened a room, rather than a failed lookup.
  Future<ApiProfileLiveRoom?> loadLiveRoom(
    String mid, {
    ApiRequestContext? context,
  }) async {
    _id(mid);
    const e = 'profile_live_room';
    final data = await api.requestJson(
      Uri.https('api.live.bilibili.com', '/room/v1/Room/getRoomInfoOld', {
        'mid': mid,
      }),
      e,
      context: context,
    );
    final roomStatus = _number(data['roomStatus']);
    if (roomStatus == 0) return null;
    if (roomStatus != 1) _fail(e);
    final liveStatus = _number(data['liveStatus']);
    if (liveStatus != 0 && liveStatus != 1) _fail(e);
    return ApiProfileLiveRoom(
      roomId: _key(data['roomid'], e),
      isLive: liveStatus == 1,
    );
  }

  Future<ApiPage<ApiProfileEntry>> loadVideos(
    String mid, {
    required int page,
    String order = 'pubdate',
    String keyword = '',
    ApiRequestContext? context,
  }) async {
    _id(mid);
    _page(page);
    if (!const {'pubdate', 'click', 'stow'}.contains(order)) {
      throw ArgumentError('Invalid order');
    }
    const e = 'profile_videos';
    final data = await api.requestWbiJson(
      '/x/space/wbi/arc/search',
      {
        'mid': mid,
        'pn': '$page',
        'ps': '$_size',
        'tid': '0',
        'order': order,
        'keyword': keyword,
      },
      e,
      context: context,
    );
    final items = _list(
      _map(data['list'], e)['vlist'],
      e,
    ).map((v) => _video({..._map(v, e), 'mid': mid}, e)).toList();
    final total = _number(_map(data['page'], e)['count']);
    if (total == null || total < 0) _fail(e);
    return _paged(items, page, total);
  }

  Future<ApiPage<ApiProfileEntry>> loadDynamics(
    String mid, {
    String? cursor,
    ApiRequestContext? context,
  }) async {
    _id(mid);
    const e = 'profile_dynamics';
    final data = await _get('/x/polymer/web-dynamic/v1/feed/space', e, {
      'host_mid': mid,
      'features': 'itemOpusStyle',
      'offset': ?cursor,
    }, context);
    final items = _list(data['items'], e).take(100).map((v) {
      final item = _map(v, e);
      final post = parseDynamicPost(item, e);
      return ApiProfileEntry(
        id: post.id,
        kind: ApiProfileEntryKind.dynamic,
        dynamicPost: post,
        title:
            post.video?.title ??
            (post.title.isNotEmpty
                ? post.title
                : post.linkTitle.isNotEmpty
                ? post.linkTitle
                : post.text.isEmpty
                ? '动态'
                : post.text),
        subtitle: post.text,
        video: post.video,
        coverUrl:
            post.video?.coverUrl ??
            post.imageUrls.firstOrNull ??
            post.linkCoverUrl,
        imageUrls: post.imageUrls,
        userMid: post.authorId ?? mid,
        publishedAt: post.publishedAt,
      );
    }).toList();
    final next = _string(data['offset']);
    final hasMoreValue = data['has_more'];
    if (hasMoreValue is! bool && hasMoreValue is! int) _fail(e);
    final more =
        (hasMoreValue == true || hasMoreValue == 1) &&
        items.isNotEmpty &&
        next.isNotEmpty &&
        next != cursor;
    return ApiPage(
      List.unmodifiable(items),
      hasMore: more,
      nextCursor: more ? next : null,
    );
  }

  Future<ApiPage<ApiProfileEntry>> loadFolders(
    String mid, {
    required int page,
    ApiRequestContext? context,
  }) async {
    _id(mid);
    _page(page);
    const e = 'profile_folders';
    final data = await _get('/x/v3/fav/folder/created/list', e, {
      'up_mid': mid,
      'pn': '$page',
      'ps': '$_size',
    }, context);
    final items =
        _list(data['list'] ?? (data['count'] == 0 ? const [] : null), e).map((
          v,
        ) {
          final item = _map(v, e);
          return ApiProfileEntry(
            id: _key(item['id'], e),
            kind: ApiProfileEntryKind.folder,
            title: _text(item['title'], e),
            coverUrl: _uri(item['cover']),
            count: _number(item['media_count']),
          );
        }).toList();
    final count = _number(data['count']);
    if (count == null || count < 0) _fail(e);
    return _paged(items, page, count);
  }

  Future<ApiPage<ApiProfileEntry>> loadFolderVideos(
    String folderId, {
    required int page,
    ApiRequestContext? context,
  }) async {
    _id(folderId);
    _page(page);
    const e = 'profile_folder_videos';
    final data = await _get('/x/v3/fav/resource/list', e, {
      'media_id': folderId,
      'pn': '$page',
      'ps': '$_size',
      'order': 'mtime',
      'type': '0',
      'platform': 'web',
    }, context);
    final total = _number(_map(data['info'], e)['media_count']);
    if (total == null || total < 0) _fail(e);
    final items = _list(data['medias'] ?? (total == 0 ? const [] : null), e)
        .map((v) {
          final item = _map(v, e);
          if (item['type'] != null && item['type'] != 2 ||
              item['title'] == '已失效视频' ||
              (_number(item['attr']) ?? 0) & 1 != 0 ||
              item['bvid'] is! String ||
              (item['bvid'] as String).isEmpty) {
            return ApiProfileEntry(
              id: _key(item['id'], e),
              kind: ApiProfileEntryKind.video,
              title: _string(item['title']),
              subtitle: '该收藏内容不可播放',
              coverUrl: _uri(item['cover']),
            );
          }
          return _video({
            ...item,
            'pic': item['cover'],
            'author': _optionalMap(item['upper'])['name'],
            'mid': _optionalMap(item['upper'])['mid'],
            'play': _optionalMap(item['cnt_info'])['play'] ?? item['play'],
            'danmaku':
                _optionalMap(item['cnt_info'])['danmaku'] ?? item['danmaku'],
            'pubdate': item['pubtime'] ?? item['pubdate'],
          }, e);
        })
        .toList();
    return _paged(items, page, total);
  }

  Future<ApiProfileRelationPrivacy> loadRelationPrivacy(
    String mid, {
    ApiRequestContext? context,
  }) async {
    _id(mid);
    const e = 'profile_relation_privacy';
    final data = await _get('/x/space/setting', e, {'mid': mid}, context);
    final privacy = _map(data['privacy'], e);
    bool hidden(Object? value) => switch (_number(value)) {
      0 => false,
      1 => true,
      _ => _fail(e),
    };
    return ApiProfileRelationPrivacy(
      followingHidden: hidden(privacy['disable_following']),
      followersHidden: hidden(privacy['disable_show_fans']),
    );
  }

  Future<ApiProfileContentPrivacy> loadContentPrivacy(
    String mid, {
    ApiRequestContext? context,
  }) async {
    _id(mid);
    const e = 'profile_content_privacy';
    final data = await _get('/x/space/setting', e, {'mid': mid}, context);
    final privacy = _map(data['privacy'], e);
    bool hidden(Object? value) => switch (_number(value)) {
      0 => true,
      1 => false,
      _ => _fail(e),
    };
    return ApiProfileContentPrivacy(
      foldersHidden: hidden(privacy['fav_video']),
      seasonsHidden: hidden(privacy['bangumi']),
    );
  }

  Future<bool> loadBlocked(String mid, {ApiRequestContext? context}) async {
    _id(mid);
    const e = 'profile_relation';
    final data = await _get('/x/relation', e, {'fid': mid}, context);
    final attribute = _number(data['attribute']);
    if (attribute == null || attribute < 0) _fail(e);
    return attribute & 128 != 0;
  }

  Future<void> setBlocked(
    String mid,
    bool blocked, {
    ApiRequestContext? context,
  }) async {
    _id(mid);
    await api.submitForm('/x/relation/modify', 'profile_set_blocked', {
      'fid': mid,
      'act': blocked ? '5' : '6',
      're_src': '11',
    }, context: context);
  }

  Future<ApiPage<ApiProfileEntry>> loadRelations(
    String mid, {
    required bool followers,
    required int page,
    String orderType = '',
    ApiRequestContext? context,
  }) async {
    _id(mid);
    _page(page);
    final e = followers ? 'profile_followers' : 'profile_followings';
    final data =
        await _get('/x/relation/${followers ? 'followers' : 'followings'}', e, {
          'vmid': mid,
          'pn': '$page',
          'ps': '$_size',
          'order': 'desc',
          if (orderType.isNotEmpty) 'order_type': orderType,
        }, context);
    final items = _list(data['list'], e).map((v) => _relation(v, e)).toList();
    final total = _number(data['total']);
    if (total == null || total < 0) _fail(e);
    return _paged(items, page, total);
  }

  Future<ApiPage<ApiProfileEntry>> searchFollowing(
    String mid,
    String keyword, {
    required int page,
    ApiRequestContext? context,
  }) async {
    _id(mid);
    _page(page);
    if (keyword.trim().isEmpty || keyword.runes.length > 100) {
      throw ArgumentError('Invalid following search');
    }
    const e = 'profile_following_search';
    final data = await api.requestWbiJson(
      '/x/relation/followings/search',
      {
        'vmid': mid,
        'pn': '$page',
        'ps': '$_size',
        'name': keyword.trim(),
        'order': 'desc',
        'order_type': 'attention',
        'gaia_source': 'main_web',
        'web_location': '333.999',
      },
      e,
      context: context,
    );
    return _relationPage(data, page, e);
  }

  Future<ApiPage<ApiProfileEntry>> loadBlacklist({
    required int page,
    ApiRequestContext? context,
  }) async {
    _page(page);
    const e = 'profile_blacklist';
    final data = await _get('/x/relation/blacks', e, {
      'pn': '$page',
      'ps': '$_size',
      'order': 'desc',
    }, context);
    return _relationPage(data, page, e);
  }

  static ApiPage<ApiProfileEntry> _relationPage(
    Map<String, Object?> data,
    int page,
    String e,
  ) {
    final total = _number(data['total']);
    if (total == null || total < 0) _fail(e);
    final items = _list(
      data['list'] ?? (total == 0 ? const [] : null),
      e,
    ).map((value) => _relation(value, e)).toList();
    return _paged(items, page, total);
  }

  Future<ApiPage<ApiProfileEntry>> loadFollowingGroup(
    String mid,
    String groupId, {
    required int page,
    ApiRequestContext? context,
  }) async {
    _id(mid);
    _page(page);
    if (!RegExp(r'^-?(0|[1-9]\d*)$').hasMatch(groupId)) {
      throw ArgumentError('Invalid follow group ID');
    }
    const e = 'profile_following_group';
    final data = await api.requestValue(
      Uri.https('api.bilibili.com', '/x/relation/tag', {
        'mid': mid,
        'tagid': groupId,
        'pn': '$page',
        'ps': '$_size',
      }),
      e,
      context: context,
    );
    final items = _list(
      data ?? const [],
      e,
    ).map((v) => _relation(v, e)).toList();
    // This endpoint returns an array without a total or continuation flag.
    final more = items.length >= _size;
    return ApiPage(
      List.unmodifiable(items),
      hasMore: more,
      nextCursor: more ? '${page + 1}' : null,
    );
  }

  static ApiProfileEntry _relation(Object? value, String e) {
    final item = _map(value, e);
    final id = _key(item['mid'], e);
    return ApiProfileEntry(
      id: id,
      kind: ApiProfileEntryKind.user,
      userMid: id,
      title: _text(item['uname'], e),
      subtitle: _string(item['sign']),
      coverUrl: _uri(item['face']),
    );
  }

  static ApiPage<ApiProfileEntry> _paged(
    List<ApiProfileEntry> items,
    int page,
    int total, {
    int pageSize = _size,
  }) {
    final more = items.isNotEmpty && page * pageSize < total;
    return ApiPage(
      List.unmodifiable(items),
      hasMore: more,
      totalCount: total,
      nextCursor: more ? '${page + 1}' : null,
    );
  }

  static ApiProfileEntry _video(Map<String, Object?> item, String e) {
    final bvid = _text(item['bvid'], e);
    if (!RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(bvid)) _fail(e);
    final title = _text(item['title'], e);
    final length = item['length'];
    var seconds = _number(item['duration']) ?? 0;
    if (length is String) {
      seconds = 0;
      for (final part in length.split(':')) {
        seconds = seconds * 60 + (int.tryParse(part) ?? 0);
      }
    }
    final video = ApiVideoSummary(
      access: parseVideoAccess(item),
      bvid: bvid,
      title: title,
      coverUrl: _uri(item['pic']),
      ownerName: _string(item['author']),
      ownerMid: item['mid'] == null ? null : _key(item['mid'], e),
      duration: Duration(seconds: seconds),
      playCount: _number(item['play']),
      danmakuCount: _number(item['video_review'] ?? item['danmaku']),
      publishedAt: _date(item['created'] ?? item['pubdate']),
    );
    return ApiProfileEntry(
      id: bvid,
      kind: ApiProfileEntryKind.video,
      title: title,
      coverUrl: video.coverUrl,
      video: video,
      publishedAt: video.publishedAt,
      count: video.playCount,
    );
  }

  static Never _fail(String e) =>
      throw ApiFailure(ApiFailureCategory.protocol, e);
  static void _id(String value) {
    if (!RegExp(r'^[1-9]\d*$').hasMatch(value)) {
      throw ArgumentError('Invalid ID');
    }
  }

  static void _page(int value) {
    if (value < 1) throw ArgumentError('Invalid page');
  }

  static String _key(Object? value, String e) {
    final text = value is String
        ? value
        : value is int
        ? '$value'
        : '';
    if (!RegExp(r'^[1-9]\d*$').hasMatch(text)) _fail(e);
    return text;
  }

  static Map<String, Object?> _map(Object? value, String e) =>
      value is Map<String, Object?> ? value : _fail(e);
  static Map<String, Object?> _optionalMap(Object? value) =>
      value is Map<String, Object?> ? value : const {};
  static List<Object?> _list(Object? value, String e) =>
      value is List<Object?> ? value : _fail(e);
  static String _text(Object? value, String e) =>
      value is String && value.isNotEmpty ? value : _fail(e);
  static String _string(Object? value) => value is String ? value : '';
  static int? _number(Object? value) => value is int
      ? value
      : value is String
      ? int.tryParse(value)
      : null;
  static DateTime? _date(Object? value) {
    final seconds = _number(value);
    return seconds != null && seconds > 0 && seconds < 8640000000000
        ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
        : null;
  }

  static Uri? _uri(Object? value) {
    if (value is! String || value.isEmpty) return null;
    final uri = Uri.tryParse(value.startsWith('//') ? 'https:$value' : value);
    return uri != null &&
            const {'http', 'https'}.contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty
        ? uri.replace(scheme: 'https')
        : null;
  }
}
