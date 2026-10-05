import '../mappers/dynamic_post_parser.dart';
import '../api_client.dart';
import '../models.dart';
import '../models/profile_models.dart';

/// Read-only Web space protocol. Private or restricted content stays restricted.
final class ProfileClient {
  const ProfileClient(this.api);
  final BiliApiClient api;
  static const _size = 30;
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
    final data = await _get('/x/web-interface/card', e, {'mid': mid}, context);
    final card = _map(data['card'], e);
    if (_key(card['mid'], e) != mid) _fail(e);
    final official = _optionalMap(card['official_verify']);
    final vip = _optionalMap(card['vip']);
    return ApiUserProfile(
      mid: mid,
      name: _text(card['name'], e),
      avatarUrl: _uri(card['face']),
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
    final items =
        _list(
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
      if (cursor != null) 'offset': cursor,
    }, context);
    final items =
        _list(data['items'], e).take(100).map((v) {
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
    final items =
        _list(data['medias'] ?? (total == 0 ? const [] : null), e).map((v) {
          final item = _map(v, e);
          if (item['type'] != null && item['type'] != 2 ||
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
          }, e);
        }).toList();
    return _paged(items, page, total);
  }

  Future<ApiPage<ApiProfileEntry>> loadRelations(
    String mid, {
    required bool followers,
    required int page,
    ApiRequestContext? context,
  }) async {
    _id(mid);
    _page(page);
    final e = followers ? 'profile_followers' : 'profile_followings';
    final data = await _get(
      '/x/relation/${followers ? 'followers' : 'followings'}',
      e,
      {'vmid': mid, 'pn': '$page', 'ps': '$_size', 'order': 'desc'},
      context,
    );
    final items =
        _list(data['list'], e).map((v) {
          final item = _map(v, e);
          final id = _key(item['mid'], e);
          return ApiProfileEntry(
            id: id,
            kind: ApiProfileEntryKind.user,
            userMid: id,
            title: _text(item['uname'], e),
            subtitle: _string(item['sign']),
            coverUrl: _uri(item['face']),
          );
        }).toList();
    final total = _number(data['total']);
    if (total == null || total < 0) _fail(e);
    return _paged(items, page, total);
  }

  static ApiPage<ApiProfileEntry> _paged(
    List<ApiProfileEntry> items,
    int page,
    int total,
  ) {
    final more = items.isNotEmpty && page * _size < total;
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
    final text =
        value is String
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
  static int? _number(Object? value) =>
      value is int
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
