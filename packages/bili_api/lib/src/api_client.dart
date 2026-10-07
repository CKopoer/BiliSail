import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'cookies.dart';
import 'models.dart';
import 'transport.dart';
import 'wbi.dart';

final class _WbiKeyFlight {
  _WbiKeyFlight(this.epoch);
  final int? epoch;
  final cancellation = ApiCancellation();
  late final Future<WbiSigner> result;
}

abstract interface class ApiSessionProvider {
  int get sessionEpoch;
}

final class BiliApiClient {
  BiliApiClient({
    ApiTransport? transport,
    ApiSessionProvider? sessionProvider,
    ApiCookieJar? cookieJar,
    this.onCookiesChanged,
    this.timeout = const Duration(seconds: 12),
    DateTime Function()? clock,
    Future<List<ApiDanmakuItem>> Function(Uint8List)? danmakuDecoder,
  }) : _transport = transport ?? DioApiTransport(),
       _ownsTransport = transport == null,
       _sessionProvider = sessionProvider,
       cookieJar = cookieJar ?? ApiCookieJar(),
       _clock = clock ?? DateTime.now,
       _danmakuDecoder = danmakuDecoder ?? _decodeInIsolate;

  final ApiTransport _transport;
  final bool _ownsTransport;
  final ApiSessionProvider? _sessionProvider;
  final ApiCookieJar cookieJar;
  final Future<void> Function()? onCookiesChanged;
  final Duration timeout;
  final DateTime Function() _clock;
  final Future<List<ApiDanmakuItem>> Function(Uint8List) _danmakuDecoder;
  _WbiKeyFlight? _wbiInFlight;
  WbiSigner? _wbi;
  DateTime? _wbiFetched;

  static final _api = Uri.https('api.bilibili.com', '/');
  static final _passport = Uri.https('passport.bilibili.com', '/');

  /// Registered Web reads share WBI keys and bounded re-signing.
  Future<Map<String, Object?>> requestWbiJson(
    String path,
    Map<String, String> parameters,
    String endpoint, {
    ApiRequestContext? context,
  }) {
    if (!const {
      '/x/space/wbi/arc/search',
      '/x/web-interface/wbi/search/type',
      '/x/web-interface/wbi/search/all/v2',
      '/x/player/wbi/v2',
    }.contains(path)) {
      throw ArgumentError('Unsupported WBI endpoint');
    }
    return _wbiJson(path, parameters, endpoint, context);
  }

  /// Live Web connection discovery shares the account's WBI key single-flight.
  Future<Map<String, Object?>> requestLiveWbiJson(
    String path,
    Map<String, String> parameters,
    String endpoint, {
    ApiRequestContext? context,
  }) {
    if (!const {'/xlive/web-room/v1/index/getDanmuInfo'}.contains(path)) {
      throw ArgumentError('Unsupported live WBI endpoint');
    }
    return _wbiJson(
      path,
      parameters,
      endpoint,
      context,
      origin: Uri.https('api.live.bilibili.com', '/'),
    );
  }

  void close() {
    _wbiInFlight?.cancellation.cancel();
    if (_ownsTransport && _transport is DioApiTransport) {
      (_transport).close();
    }
  }

  /// Shared authenticated, bounded GET pipeline for the package's Web clients.
  Future<Map<String, Object?>> requestJson(
    Uri uri,
    String endpoint, {
    ApiRequestContext? context,
  }) async {
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        !const {
          'api.bilibili.com',
          'api.live.bilibili.com',
          'api.vc.bilibili.com',
          'message.bilibili.com',
        }.contains(uri.host)) {
      throw ArgumentError('Unsupported Web API destination');
    }
    final value = await _jsonValue(uri, endpoint, context);
    // Timeline APIs return a top-level result array instead of a data object.
    return value is List<Object?> ? {'list': value} : _map(value, endpoint);
  }

  Future<Object?> requestValue(
    Uri uri,
    String endpoint, {
    ApiRequestContext? context,
  }) {
    if (uri.scheme != 'https' ||
        uri.host != 'api.bilibili.com' ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443) {
      throw ArgumentError('Unsupported Web API destination');
    }
    return _jsonValue(uri, endpoint, context);
  }

  /// Authenticated form writes are sent once. Unknown outcomes must be
  /// reconciled by the caller, never automatically replayed.
  Future<Object?> submitForm(
    String path,
    String endpoint,
    Map<String, String> fields, {
    ApiRequestContext? context,
  }) async {
    if (!const {
      '/x/web-interface/archive/like',
      '/x/web-interface/coin/add',
      '/x/v3/fav/resource/deal',
      '/x/v3/fav/folder/unfav',
      '/x/v3/fav/season/unfav',
      '/x/v3/fav/season/fav',
      '/x/v3/fav/folder/edit',
      '/x/v2/history/toview/add',
      '/x/v2/history/toview/del',
      '/x/web-interface/feedback/dislike',
      '/x/web-interface/feedback/dislike/cancel',
      '/x/click-interface/web/heartbeat',
      '/x/v2/dm/post',
      '/x/v2/reply/action',
      '/x/v2/reply/add',
      '/x/relation/modify',
      '/x/relation/tags/addUsers',
    }.contains(path)) {
      throw ArgumentError('Unsupported mutation');
    }
    return _submitForm(_api.replace(path: path), endpoint, fields, context);
  }

  /// The live host has its own Cookie scope, Origin and mutation allowlist.
  Future<Object?> submitLiveForm(
    String path,
    String endpoint,
    Map<String, String> fields, {
    ApiRequestContext? context,
  }) {
    if (path != '/msg/send') throw ArgumentError('Unsupported live mutation');
    return _submitForm(
      Uri.https('api.live.bilibili.com', path),
      endpoint,
      fields,
      context,
    );
  }

  /// Web IM writes are single attempts and use the destination's Cookie scope.
  Future<Object?> submitMessageForm(
    String path,
    String endpoint,
    Map<String, String> fields, {
    ApiRequestContext? context,
  }) {
    if (!const {
      '/web_im/v1/web_im/send_msg',
      '/session_svr/v1/session_svr/update_ack',
    }.contains(path)) {
      throw ArgumentError('Unsupported message mutation');
    }
    return _submitForm(
      Uri.https('api.vc.bilibili.com', path),
      endpoint,
      fields,
      context,
    );
  }

  /// Dynamic writes use JSON and query CSRF, as in the official Web client.
  Future<Object?> submitDynamicJson(
    String path,
    String endpoint,
    Map<String, Object?> body, {
    ApiRequestContext? context,
  }) {
    if (!const {
      '/x/dynamic/feed/dyn/thumb',
      '/x/dynamic/feed/create/dyn',
    }.contains(path)) {
      throw ArgumentError('Unsupported dynamic mutation');
    }
    return _submitForm(
      _api.replace(
        path: path,
        queryParameters: path == '/x/dynamic/feed/create/dyn'
            ? const {'platform': 'web'}
            : null,
      ),
      endpoint,
      const {},
      context,
      jsonBody: body,
    );
  }

  Future<Object?> _submitForm(
    Uri uri,
    String endpoint,
    Map<String, String> fields,
    ApiRequestContext? context, {
    Map<String, Object?>? jsonBody,
  }) async {
    final live = uri.host == 'api.live.bilibili.com';
    final message = uri.host == 'api.vc.bilibili.com';
    final epoch = _sessionProvider?.sessionEpoch;
    void check() {
      if (context?.cancellation?.isCancelled == true ||
          (context?.sessionEpoch != null && context?.sessionEpoch != epoch) ||
          (epoch != null && _sessionProvider?.sessionEpoch != epoch)) {
        throw ApiFailure(ApiFailureCategory.cancelled, endpoint);
      }
    }

    check();
    final cookie = cookieJar.headerFor(uri, now: _clock());
    final cookies = <String, String>{};
    for (final pair in cookie?.split('; ') ?? const <String>[]) {
      final separator = pair.indexOf('=');
      if (separator > 0) {
        cookies.putIfAbsent(
          pair.substring(0, separator),
          () => pair.substring(separator + 1),
        );
      }
    }
    final csrf = cookies['bili_jct'];
    if (csrf == null ||
        csrf.isEmpty ||
        cookies['SESSDATA']?.isNotEmpty != true) {
      throw ApiFailure(ApiFailureCategory.authentication, endpoint);
    }
    final transport = _transport;
    if (jsonBody == null
        ? transport is! ApiFormTransport
        : transport is! ApiJsonTransport) {
      throw ApiFailure(ApiFailureCategory.unavailable, endpoint);
    }
    final remaining = context?.deadline?.difference(_clock()) ?? timeout;
    if (remaining <= Duration.zero) {
      throw ApiFailure(ApiFailureCategory.timeout, endpoint);
    }
    final budget = remaining < timeout ? remaining : timeout;
    ApiHttpResponse response;
    try {
      final headers = <String, String>{
        'Accept': 'application/json',
        'User-Agent': 'BiliSail/0.1',
        'Referer': message
            ? 'https://message.bilibili.com/'
            : live
            ? 'https://live.bilibili.com/'
            : 'https://www.bilibili.com/',
        'Origin': message
            ? 'https://message.bilibili.com'
            : live
            ? 'https://live.bilibili.com'
            : 'https://www.bilibili.com',
        'Cookie': cookie ?? '',
      };
      final operation = jsonBody == null
          ? (transport as ApiFormTransport).postForm(
              uri,
              fields: {
                ...fields,
                'csrf': csrf,
                if (live || message) 'csrf_token': csrf,
              },
              headers: headers,
              timeout: budget,
              cancellation: context?.cancellation,
            )
          : (transport as ApiJsonTransport).postJson(
              uri.replace(
                queryParameters: {...uri.queryParameters, 'csrf': csrf},
              ),
              body: jsonBody,
              headers: headers,
              timeout: budget,
              cancellation: context?.cancellation,
            );
      response = await operation.timeout(budget);
    } on TimeoutException {
      throw ApiFailure(ApiFailureCategory.timeout, endpoint);
    }
    check();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiFailure(
        response.statusCode == 429
            ? ApiFailureCategory.rateLimited
            : response.statusCode == 401 || response.statusCode == 403
            ? ApiFailureCategory.authentication
            : ApiFailureCategory.http,
        endpoint,
        httpStatus: response.statusCode,
      );
    }
    final result = _decodeJson(response, endpoint);
    if (live) {
      final root = _map(jsonDecode(utf8.decode(response.body)), endpoint);
      // Live may reject a message with code=0 (e.g. a muted account). Keep
      // server text out of diagnostics and do not report a false success.
      if (['message', 'msg'].any((key) {
        final message = root[key];
        return message is String && message.isNotEmpty && message != '0';
      })) {
        throw ApiFailure(ApiFailureCategory.permission, endpoint);
      }
    }
    return result;
  }

  Future<List<String>> getVideoTags(
    String bvid, {
    ApiRequestContext? context,
  }) async {
    _validateBvid(bvid);
    const endpoint = 'video_tags';
    final data = await _jsonValue(
      _api.replace(
        path: '/x/tag/archive/tags',
        queryParameters: {'bvid': bvid},
      ),
      endpoint,
      context,
    );
    final tags = <String>{};
    for (final value in _list(data, endpoint).take(100)) {
      final name = _requiredString(
        _map(value, endpoint)['tag_name'],
        endpoint,
      ).trim();
      if (name.isNotEmpty) tags.add(name);
    }
    return List.unmodifiable(tags);
  }

  Future<List<ApiVideoSummary>> getRelatedVideos(
    String bvid, {
    ApiRequestContext? context,
  }) async {
    _validateBvid(bvid);
    final data = await _jsonValue(
      _api.replace(
        path: '/x/web-interface/archive/related',
        queryParameters: {'bvid': bvid},
      ),
      'video_related',
      context,
    );
    return List.unmodifiable(
      _list(data, 'video_related').map(
        (entry) => _videoSummary(_map(entry, 'video_related'), 'video_related'),
      ),
    );
  }

  Future<ApiPage<ApiVideoComment>> getVideoComments(
    String aid, {
    int page = 1,
    ApiCommentSort sort = ApiCommentSort.hot,
    int commentType = 1,
    ApiRequestContext? context,
  }) => _comments(
    aid,
    page,
    sort: sort,
    commentType: commentType,
    context: context,
  );

  Future<ApiPage<ApiVideoComment>> getVideoReplies(
    String aid,
    String rootId, {
    int page = 1,
    int commentType = 1,
    ApiRequestContext? context,
  }) => _comments(
    aid,
    page,
    rootId: rootId,
    commentType: commentType,
    context: context,
  );

  Future<ApiPage<ApiVideoComment>> _comments(
    String aid,
    int page, {
    ApiCommentSort sort = ApiCommentSort.hot,
    String? rootId,
    int commentType = 1,
    ApiRequestContext? context,
  }) async {
    _validateCommentId(aid);
    _validateCommentType(commentType);
    if (rootId != null) _validateCommentId(rootId);
    if (page < 1) throw ArgumentError('Invalid comment page');
    final endpoint = rootId == null ? 'video_comments' : 'video_replies';
    final data = await _json(
      _api.replace(
        path: rootId == null ? '/x/v2/reply' : '/x/v2/reply/reply',
        queryParameters: {
          'oid': aid,
          'type': '$commentType',
          'pn': '$page',
          'ps': '20',
          'root': ?rootId,
          if (rootId == null) 'sort': sort == ApiCommentSort.hot ? '1' : '0',
          if (rootId == null) 'nohot': '1',
        },
      ),
      endpoint,
      context,
    );
    final values = <Object?>[
      if (page == 1 &&
          rootId == null &&
          _optionalMap(data['upper'])?['top'] is Map)
        _optionalMap(data['upper'])?['top'],
      ..._list(data['replies'] ?? const [], endpoint),
    ];
    final seen = <String>{};
    final items = <ApiVideoComment>[];
    for (final value in values.take(100)) {
      final comment = _comment(_map(value, endpoint), endpoint);
      if (seen.add(comment.id)) items.add(comment);
    }
    final paging = _map(data['page'], endpoint);
    final count = _requiredInt(paging['count'], endpoint);
    final size = _requiredInt(paging['size'], endpoint);
    // Legacy time order can return this explicit empty page to guests.
    // It is a successful server result, not a malformed comment or transport error.
    if (count == 0 && size == 0 && data['replies'] == null && items.isEmpty) {
      return const ApiPage([], hasMore: false, totalCount: 0);
    }
    if (count < 0 || size < 1) {
      throw ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    final hasMore = items.isNotEmpty && page * size < count;
    return ApiPage(
      List.unmodifiable(items),
      hasMore: hasMore,
      nextCursor: hasMore ? '${page + 1}' : null,
      totalCount: count,
    );
  }

  ApiVideoComment _comment(
    Map<String, Object?> entry,
    String endpoint, {
    int depth = 0,
  }) {
    final member = _map(entry['member'], endpoint);
    final content = _map(entry['content'], endpoint);
    final location = _text(
      _commentMap(entry['reply_control'])['location'],
    )?.trim();
    final card = _commentMap(_commentMap(member['user_sailing'])['cardbg']);
    final fan = _commentMap(card['fan']);
    String? optionalId(Object? value) =>
        value == null || value == 0 || value == '0'
        ? null
        : _id(value, endpoint);
    return ApiVideoComment(
      id: _id(entry['rpid_str'] ?? entry['rpid'], endpoint),
      author: _requiredString(member['uname'], endpoint),
      authorMid: _userMid(member['mid']),
      avatarUrl: _commentImage(member['avatar']),
      level: _int(_commentMap(member['level_info'])['current_level']),
      verifyType: _int(_commentMap(member['official_verify'])['type']),
      vipLabel:
          _int(_commentMap(member['vip'])['vipStatus']) == 1 ||
              _int(_commentMap(member['vip'])['vip_status']) == 1
          ? _text(_commentMap(_commentMap(member['vip'])['label'])['text']) ??
                '大会员'
          : null,
      medalName: _text(_commentMap(member['fans_detail'])['medal_name']),
      medalLevel: _int(_commentMap(member['fans_detail'])['level']),
      decorationImageUrl: _commentImage(card['image']),
      decorationName: _text(card['name']),
      decorationFanNumber: _text(fan['num_desc']),
      decorationFanColor: _commentColor(fan['color']),
      emotes: Map.unmodifiable({
        for (final e in _commentMap(content['emote']).entries.take(100))
          if (e.key.isNotEmpty &&
              e.key.length <= 100 &&
              _commentImage(_commentMap(e.value)['url']) != null)
            e.key: _commentImage(_commentMap(e.value)['url'])!,
      }),
      pictures: List.unmodifiable(
        (content['pictures'] is List<Object?>
                ? content['pictures'] as List<Object?>
                : const <Object?>[])
            .take(9)
            .map((v) => _commentImage(_commentMap(v)['img_src']))
            .whereType<Uri>(),
      ),
      message: _requiredString(content['message'], endpoint),
      likeCount: _count(entry['like']) ?? 0,
      liked: _int(entry['action']) == 1,
      replyCount: _count(entry['rcount'] ?? entry['count']) ?? 0,
      rootId: optionalId(entry['root_str'] ?? entry['root']),
      parentId: optionalId(entry['parent_str'] ?? entry['parent']),
      replies: depth >= 1
          ? const []
          : List.unmodifiable(
              _list(entry['replies'] ?? const [], endpoint)
                  .take(20)
                  .map(
                    (value) => _comment(
                      _map(value, endpoint),
                      endpoint,
                      depth: depth + 1,
                    ),
                  ),
            ),
      publishedAt: _publishedAt(entry['ctime']),
      ipLocation: location?.isNotEmpty == true ? location : null,
    );
  }

  /// Web reply panel, optional Cookie; bounded GET with the shared deadline.
  Future<List<ApiCommentEmotePackage>> getCommentEmotes({
    ApiRequestContext? context,
  }) async {
    const endpoint = 'comment_emotes';
    final data = await requestJson(
      Uri.https('api.bilibili.com', '/x/emote/user/panel/web', {
        'business': 'reply',
      }),
      endpoint,
      context: context,
    );
    return List.unmodifiable(
      _list(data['packages'] ?? const [], endpoint).take(50).map((v) {
        final p = _map(v, endpoint);
        return ApiCommentEmotePackage(
          _text(p['text']) ?? '表情',
          List.unmodifiable(
            _list(p['emote'] ?? const [], endpoint)
                .take(200)
                .map((v) {
                  final e = _map(v, endpoint);
                  return ApiCommentEmote(
                    _text(e['text']) ?? '',
                    _int(e['type']) == 4 ? null : _commentImage(e['url']),
                  );
                })
                .where((e) => e.text.isNotEmpty && e.text.length <= 100),
          ),
        );
      }),
    );
  }

  static String? _text(Object? value) => value is String && value.isNotEmpty
      ? value.substring(0, value.length.clamp(0, 200))
      : null;
  static Map<String, Object?> _commentMap(Object? value) =>
      value is Map<String, Object?> ? value : const {};
  static int? _commentColor(Object? value) {
    final rgb = switch (value) {
      int() => value,
      String() when RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value) =>
        int.tryParse(value.substring(1), radix: 16),
      String() =>
        int.tryParse(value) ??
            (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value)
                ? int.tryParse(value, radix: 16)
                : null),
      _ => null,
    };
    return rgb != null && rgb >= 0 && rgb <= 0xffffff ? rgb : null;
  }

  static Uri? _commentImage(Object? value) {
    if (value is! String || value.length > 2048) return null;
    final uri = Uri.tryParse(value.startsWith('//') ? 'https:$value' : value);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 80 && uri.port != 443)) {
      return null;
    }
    return uri.replace(scheme: 'https', port: 443);
  }

  void _validateCommentId(String value) {
    if (!RegExp(r'^[1-9]\d*$').hasMatch(value)) {
      throw ArgumentError('Invalid comment ID');
    }
  }

  Future<void> likeVideoComment(
    String aid,
    String commentId,
    bool liked, {
    int commentType = 1,
    ApiRequestContext? context,
  }) async {
    _validateCommentId(aid);
    _validateCommentType(commentType);
    _validateCommentId(commentId);
    await submitForm('/x/v2/reply/action', 'comment_like', {
      'oid': aid,
      'rpid': commentId,
      'type': '$commentType',
      'action': liked ? '1' : '0',
    }, context: context);
  }

  Future<ApiVideoComment> addVideoComment(
    String aid,
    String message, {
    String? rootId,
    String? parentId,
    int commentType = 1,
    ApiRequestContext? context,
  }) async {
    _validateCommentId(aid);
    _validateCommentType(commentType);
    if (rootId != null) _validateCommentId(rootId);
    if (parentId != null) _validateCommentId(parentId);
    if (message.trim().isEmpty ||
        message.runes.length > 1000 ||
        (parentId != null && rootId == null)) {
      throw ArgumentError('Invalid comment content or reply target');
    }
    final data = _map(
      await submitForm('/x/v2/reply/add', 'comment_add', {
        'oid': aid,
        'type': '$commentType',
        'message': message,
        'root': rootId ?? '0',
        'parent': parentId ?? rootId ?? '0',
      }, context: context),
      'comment_add',
    );
    return _comment(_map(data['reply'], 'comment_add'), 'comment_add');
  }

  static void _validateCommentType(int type) {
    if (!const {1, 11, 12, 14, 17, 33}.contains(type)) {
      throw ArgumentError.value(type, 'commentType');
    }
  }

  Future<ApiPage<ApiVideoSummary>> getPopular({
    int page = 1,
    ApiRequestContext? context,
  }) async {
    if (page < 1) throw ArgumentError.value(page, 'page');
    final data = await _json(
      _api.replace(
        path: '/x/web-interface/popular',
        queryParameters: {'pn': '$page', 'ps': '20'},
      ),
      'popular',
      context,
    );
    final list = _list(data['list'], 'popular');
    final items = list
        .map((entry) => _videoSummary(_map(entry, 'popular'), 'popular'))
        .toList();
    return ApiPage(
      items,
      hasMore: _bool(data['no_more']) != true && items.isNotEmpty,
      nextCursor: items.isEmpty ? null : '${page + 1}',
    );
  }

  Future<ApiPage<ApiVideoSummary>> getRecommended({
    int page = 1,
    ApiRequestContext? context,
  }) async {
    if (page < 1) throw ArgumentError.value(page, 'page');
    final data = await _wbiJson(
      '/x/web-interface/index/top/feed/rcmd',
      {
        'ps': '20',
        'fresh_idx': '$page',
        'fresh_idx_1h': '$page',
        'fresh_type': '4',
        'feed_version': 'V8',
        'y_num': '5',
      },
      'recommended',
      context,
    );
    // Feed cards can also advertise non-video destinations.
    final items = _list(data['item'], 'recommended')
        .map((entry) => _map(entry, 'recommended'))
        .where((entry) => entry['goto'] == null || entry['goto'] == 'av')
        .map((entry) => _videoSummary(entry, 'recommended'))
        .toList();
    return ApiPage(
      items,
      hasMore: items.isNotEmpty,
      nextCursor: items.isEmpty ? null : '${page + 1}',
    );
  }

  Future<ApiPage<ApiVideoSummary>> getRegionalVideos({
    required String categoryId,
    int page = 1,
    ApiRequestContext? context,
  }) async {
    if ((int.tryParse(categoryId) ?? 0) < 1 || page < 1) {
      throw ArgumentError('Invalid region input');
    }
    final data = await _json(
      _api.replace(
        path: '/x/web-interface/newlist',
        queryParameters: {'rid': categoryId, 'pn': '$page', 'ps': '20'},
      ),
      'regional_videos',
      context,
    );
    final items = _list(data['archives'], 'regional_videos')
        .map(
          (entry) =>
              _videoSummary(_map(entry, 'regional_videos'), 'regional_videos'),
        )
        .toList();
    final total = _int(_optionalMap(data['page'])?['count']);
    final hasMore =
        items.isNotEmpty &&
        (total == null ? items.length >= 20 : page * 20 < total);
    return ApiPage(
      items,
      hasMore: hasMore,
      nextCursor: hasMore ? '${page + 1}' : null,
    );
  }

  Future<ApiPage<ApiVideoSummary>> getRanking({
    String categoryId = '0',
    ApiRequestContext? context,
  }) async {
    if ((int.tryParse(categoryId) ?? -1) < 0) {
      throw ArgumentError.value(categoryId, 'categoryId');
    }
    final data = await _wbiJson(
      '/x/web-interface/ranking/v2',
      {'rid': categoryId, 'type': 'all'},
      'ranking',
      context,
    );
    final items = _list(
      data['list'],
      'ranking',
    ).map((entry) => _videoSummary(_map(entry, 'ranking'), 'ranking')).toList();
    return ApiPage(items, hasMore: false);
  }

  Future<ApiPage<ApiVideoSummary>> searchVideos(
    String query, {
    int page = 1,
    ApiRequestContext? context,
  }) async {
    if (query.trim().isEmpty || page < 1) {
      throw ArgumentError('Invalid search input');
    }
    final data = await _wbiJson(
      '/x/web-interface/wbi/search/type',
      {
        'search_type': 'video',
        'keyword': query.trim(),
        'page': '$page',
        'page_size': '20',
      },
      'search',
      context,
    );
    final list = data['result'] == null
        ? const <Object?>[]
        : _list(data['result'], 'search');
    // Search can include inline live cards with an empty bvid even for video.
    final items = list
        .map((entry) => _map(entry, 'search'))
        .where((entry) => _string(entry['bvid'])?.isNotEmpty == true)
        .map((entry) => _videoSummary(entry, 'search'))
        .toList();
    final pages = _int(data['numPages']);
    return ApiPage(
      items,
      hasMore: pages == null ? items.length >= 20 : page < pages,
      nextCursor: items.isEmpty ? null : '${page + 1}',
    );
  }

  Future<ApiVideoDetail> getVideoDetail(
    String bvid, {
    ApiRequestContext? context,
  }) async {
    _validateBvid(bvid);
    final data = await _json(
      _api.replace(
        path: '/x/web-interface/view',
        queryParameters: {'bvid': bvid},
      ),
      'video_detail',
      context,
    );
    final pages = _list(data['pages'], 'video_detail').map((value) {
      final page = _map(value, 'video_detail');
      return ApiVideoPage(
        cid: _id(page['cid'], 'video_detail'),
        page: _requiredInt(page['page'], 'video_detail'),
        title: _string(page['part']) ?? '',
        duration: Duration(seconds: _int(page['duration']) ?? 0),
      );
    }).toList();
    if (pages.isEmpty) {
      throw const ApiFailure(ApiFailureCategory.protocol, 'video_detail');
    }
    return ApiVideoDetail(
      aid: _id(data['aid'], 'video_detail'),
      bvid: _requiredString(data['bvid'], 'video_detail'),
      title: _requiredString(data['title'], 'video_detail'),
      description: _string(data['desc']) ?? '',
      coverUrl: _uri(data['pic']),
      ownerName: _string(_optionalMap(data['owner'])?['name']) ?? '',
      ownerAvatarUrl: _uri(_optionalMap(data['owner'])?['face']),
      ownerMid: _optionalMap(data['owner'])?['mid'] == null
          ? null
          : _id(_optionalMap(data['owner'])?['mid'], 'video_detail'),
      likeCount: _count(_optionalMap(data['stat'])?['like']),
      coinCount: _count(_optionalMap(data['stat'])?['coin']),
      favoriteCount: _count(_optionalMap(data['stat'])?['favorite']),
      replyCount: _count(_optionalMap(data['stat'])?['reply']),
      collection: _collection(data['ugc_season']),
      pages: List.unmodifiable(pages),
      playCount: _count(_optionalMap(data['stat'])?['view']),
      danmakuCount: _count(_optionalMap(data['stat'])?['danmaku']),
      publishedAt: _publishedAt(data['pubdate']),
    );
  }

  static String? _recommendationReason(Object? value) {
    final content = (_string(_optionalMap(value)?['content']) ?? _string(value))
        ?.trim();
    return content == null || content.isEmpty ? null : content;
  }

  ApiVideoCollection? _collection(Object? value) {
    if (value == null) return null;
    const endpoint = 'video_detail';
    final season = _map(value, endpoint);
    final entries = <ApiVideoCollectionEntry>[];
    final seen = <String>{};
    for (final section in _list(
      season['sections'] ?? const [],
      endpoint,
    ).take(50)) {
      for (final value in _list(
        _map(section, endpoint)['episodes'] ?? const [],
        endpoint,
      ).take(500)) {
        if (entries.length >= 500) break;
        final episode = _map(value, endpoint);
        final arc = _optionalMap(episode['arc']);
        final bvid = _requiredString(episode['bvid'] ?? arc?['bvid'], endpoint);
        if (!seen.add(bvid)) continue;
        final pages = <ApiVideoPage>[];
        for (final value in _list(
          episode['pages'] ?? arc?['pages'] ?? const [],
          endpoint,
        ).take(100)) {
          final page = _map(value, endpoint);
          pages.add(
            ApiVideoPage(
              cid: _id(page['cid'], endpoint),
              page: _requiredInt(page['page'], endpoint),
              title: _string(page['part']) ?? '',
              duration: Duration(seconds: _int(page['duration']) ?? 0),
            ),
          );
        }
        entries.add(
          ApiVideoCollectionEntry(
            bvid: bvid,
            title: _requiredString(episode['title'] ?? arc?['title'], endpoint),
            pages: List.unmodifiable(pages),
            duration: switch (_int(arc?['duration'] ?? episode['duration'])) {
              final int seconds when seconds >= 0 => Duration(seconds: seconds),
              _ => null,
            },
          ),
        );
      }
    }
    return ApiVideoCollection(
      id: _id(season['id'], endpoint),
      title: _requiredString(season['title'], endpoint),
      entries: List.unmodifiable(entries),
      playCount: _count(_optionalMap(season['stat'])?['view']),
    );
  }

  Future<ApiPlayInfo> getPlayInfo(
    String bvid,
    String cid, {
    int qn = 80,
    ApiRequestContext? context,
  }) => _getPlayInfo(bvid, cid, qn: qn, context: context);

  /// Homepage inline playback uses the same endpoint with a browser profile.
  /// Missing audio is allowed here because the caller explicitly requests video.
  Future<ApiPlayInfo> getVideoPreviewInfo(
    String bvid,
    String cid, {
    ApiRequestContext? context,
  }) => _getPlayInfo(bvid, cid, qn: 32, preview: true, context: context);

  Future<ApiPlayInfo> _getPlayInfo(
    String bvid,
    String cid, {
    required int qn,
    bool preview = false,
    ApiRequestContext? context,
  }) async {
    _validateBvid(bvid);
    if (int.tryParse(cid) == null || qn < 1) {
      throw ArgumentError('Invalid play target');
    }
    final data = await _wbiJson(
      '/x/player/wbi/playurl',
      {
        'bvid': bvid,
        'cid': cid,
        'qn': '$qn',
        'fnval': preview ? '2000' : '4048',
        'fourk': '1',
        if (preview) ...{
          'fnver': '0',
          'from_client': 'BROWSER',
          'need_fragment': 'false',
        },
      },
      'playurl',
      context,
    );
    final dash = _optionalMap(data['dash']);
    if (dash == null) {
      throw const ApiFailure(ApiFailureCategory.unavailable, 'playurl');
    }
    final videos = _list(
      dash['video'],
      'playurl',
    ).map((v) => _track(_map(v, 'playurl'))).toList();
    final audios = preview
        ? const <ApiMediaTrack>[]
        : _list(dash['audio'], 'playurl')
              .map((v) => _track(_map(v, 'playurl')))
              .where((v) => v.codecs.toLowerCase().startsWith('mp4a'))
              .toList();
    if (videos.isEmpty || !preview && audios.isEmpty) {
      throw const ApiFailure(ApiFailureCategory.unavailable, 'playurl');
    }
    final dashSeconds = _num(dash['duration']);
    final durationMs = dashSeconds == null
        ? _int(data['timelength']) ?? 0
        : (dashSeconds * 1000).round();
    return ApiPlayInfo(
      duration: Duration(milliseconds: durationMs),
      dashVideo: List.unmodifiable(videos),
      dashAudio: List.unmodifiable(audios),
      acceptQuality: List.unmodifiable(
        (_list(
          data['accept_quality'],
          'playurl',
        )).map((v) => _int(v)).whereType<int>(),
      ),
    );
  }

  Future<List<ApiSubtitleTrack>> getSubtitleTracks(
    String aid,
    String cid, {
    ApiRequestContext? context,
  }) async {
    if (int.tryParse(aid) == null || int.tryParse(cid) == null) {
      throw ArgumentError('Invalid video identifiers');
    }
    final data = await _wbiJson(
      '/x/player/wbi/v2',
      {'aid': aid, 'cid': cid},
      'subtitle_index',
      context,
    );
    final subtitle = _optionalMap(data['subtitle']);
    if (subtitle == null) return const [];
    final entries = subtitle['subtitles'];
    if (entries == null) return const [];
    return List.unmodifiable(
      _list(entries, 'subtitle_index').map((v) {
        final entry = _map(v, 'subtitle_index');
        final url = _uri(entry['subtitle_url']);
        if (url == null) {
          throw const ApiFailure(ApiFailureCategory.protocol, 'subtitle_index');
        }
        return ApiSubtitleTrack(
          languageCode: _string(entry['lan']) ?? '',
          label: _string(entry['lan_doc']) ?? '',
          url: url,
        );
      }),
    );
  }

  Future<List<ApiSubtitleCue>> getSubtitleCues(
    Uri url, {
    ApiRequestContext? context,
  }) async {
    if (url.scheme != 'https' ||
        !(url.host == 'hdslb.com' ||
            url.host.endsWith('.hdslb.com') ||
            url.host == 'bilibili.com' ||
            url.host.endsWith('.bilibili.com'))) {
      throw ArgumentError.value(url, 'url');
    }
    final data = await _json(url, 'subtitle_body', context);
    return List.unmodifiable(
      _list(data['body'], 'subtitle_body').map((v) {
        final cue = _map(v, 'subtitle_body');
        final from = _num(cue['from']);
        final to = _num(cue['to']);
        if (from == null || to == null || to < from) {
          throw const ApiFailure(ApiFailureCategory.protocol, 'subtitle_body');
        }
        return ApiSubtitleCue(
          start: Duration(milliseconds: (from * 1000).round()),
          end: Duration(milliseconds: (to * 1000).round()),
          text: _requiredString(cue['content'], 'subtitle_body'),
        );
      }),
    );
  }

  Future<List<ApiDanmakuItem>> getDanmakuSegment(
    String cid,
    int segmentIndex, {
    ApiRequestContext? context,
  }) async {
    if (int.tryParse(cid) == null || segmentIndex < 1) {
      throw ArgumentError('Invalid segment');
    }
    final epoch = _sessionProvider?.sessionEpoch;
    final deadline = context?.deadline ?? _clock().add(timeout);
    final activeContext = ApiRequestContext(
      cancellation: context?.cancellation,
      deadline: deadline,
      sessionEpoch: context?.sessionEpoch,
    );
    _checkDecodeContext(activeContext, epoch, deadline);
    final response = await _request(
      _api.replace(
        path: '/x/v2/dm/web/seg.so',
        queryParameters: {
          'type': '1',
          'oid': cid,
          'segment_index': '$segmentIndex',
        },
      ),
      'danmaku_segment',
      activeContext,
    );
    _checkDecodeContext(activeContext, epoch, deadline);
    if (response.body.length > 2 * 1024 * 1024) {
      throw const ApiFailure(ApiFailureCategory.protocol, 'danmaku_segment');
    }
    if (response.body.length <= 32 * 1024) {
      final items = decodeDanmakuSegment(response.body);
      _checkDecodeContext(activeContext, epoch, deadline);
      return items;
    }
    await _decodeGate.enter(activeContext.cancellation, deadline, _clock);
    try {
      _checkDecodeContext(activeContext, epoch, deadline);
      final items = await _danmakuDecoder(response.body);
      _checkDecodeContext(activeContext, epoch, deadline);
      return items;
    } finally {
      _decodeGate.leave();
    }
  }

  void _checkDecodeContext(
    ApiRequestContext context,
    int? epoch,
    DateTime deadline,
  ) {
    if (context.cancellation?.isCancelled == true ||
        (epoch != null && _sessionProvider?.sessionEpoch != epoch) ||
        (context.sessionEpoch != null && context.sessionEpoch != epoch)) {
      throw const ApiFailure(ApiFailureCategory.cancelled, 'danmaku_segment');
    }
    if (!deadline.isAfter(_clock())) {
      throw const ApiFailure(ApiFailureCategory.timeout, 'danmaku_segment');
    }
  }

  Future<ApiQrCode> generateQr({ApiRequestContext? context}) async {
    final data = await _json(
      _passport.replace(path: '/x/passport-login/web/qrcode/generate'),
      'qr_generate',
      context,
    );
    final url = _uri(data['url']);
    final key = _string(data['qrcode_key']);
    if (url == null || key == null || key.isEmpty) {
      throw const ApiFailure(ApiFailureCategory.protocol, 'qr_generate');
    }
    return ApiQrCode(url: url, key: key);
  }

  Future<ApiQrPollResult> pollQr(
    String qrcodeKey, {
    ApiRequestContext? context,
  }) async {
    if (qrcodeKey.isEmpty) throw ArgumentError.value(qrcodeKey, 'qrcodeKey');
    final data = await _json(
      _passport.replace(
        path: '/x/passport-login/web/qrcode/poll',
        queryParameters: {'qrcode_key': qrcodeKey},
      ),
      'qr_poll',
      context,
    );
    return switch (_int(data['code'])) {
      0 => const ApiQrPollResult(ApiQrStatus.confirmed),
      86101 => const ApiQrPollResult(ApiQrStatus.waitingScan),
      86090 => const ApiQrPollResult(ApiQrStatus.waitingConfirm),
      86038 => const ApiQrPollResult(ApiQrStatus.expired),
      final code => throw ApiFailure(
        ApiFailureCategory.protocol,
        'qr_poll',
        businessCode: code,
      ),
    };
  }

  Future<ApiNavInfo> getNav({ApiRequestContext? context}) async {
    final data = await _json(
      _api.replace(path: '/x/web-interface/nav'),
      'nav',
      context,
    );
    return ApiNavInfo(
      isLogin: _bool(data['isLogin']) ?? false,
      mid: data['mid'] == null ? null : _id(data['mid'], 'nav'),
      name: _string(data['uname']),
      avatarUrl: _uri(data['face']),
    );
  }

  Future<Map<String, String>> _signed(
    Map<String, String> values,
    ApiRequestContext? context,
  ) async {
    final now = _clock();
    final epoch = _sessionProvider?.sessionEpoch;
    final deadline = context?.deadline ?? now.add(timeout);
    _checkWbiContext(context, epoch, deadline);
    if (_wbi == null ||
        _wbiFetched == null ||
        now.difference(_wbiFetched!) > const Duration(hours: 1)) {
      var flight = _wbiInFlight;
      if (flight == null ||
          flight.epoch != epoch ||
          flight.cancellation.isCancelled) {
        flight?.cancellation.cancel();
        flight = _WbiKeyFlight(epoch);
        _wbiInFlight = flight;
        final active = flight;
        // Public keys are shared, but the first consumer must not own their
        // cancellation/deadline. A session change starts a separate flight.
        active.result =
            _loadWbi(
                  ApiRequestContext(
                    cancellation: active.cancellation,
                    sessionEpoch: epoch,
                    deadline: now.add(timeout),
                  ),
                )
                .then((signer) {
                  if (identical(_wbiInFlight, active) &&
                      !active.cancellation.isCancelled &&
                      _sessionProvider?.sessionEpoch == epoch) {
                    _wbi = signer;
                    _wbiFetched = _clock();
                  }
                  return signer;
                })
                .whenComplete(() {
                  // A late old-session completion cannot clear a newer flight.
                  if (identical(_wbiInFlight, active)) _wbiInFlight = null;
                });
      }
      final pending = flight;
      try {
        final signer = await Future.any<WbiSigner>([
          pending.result,
          pending.cancellation.whenCancelled.then(
            (_) =>
                throw const ApiFailure(ApiFailureCategory.cancelled, 'wbi_key'),
          ),
          if (context?.cancellation case final cancellation?)
            cancellation.whenCancelled.then(
              (_) => throw const ApiFailure(
                ApiFailureCategory.cancelled,
                'wbi_key',
              ),
            ),
        ]).timeout(deadline.difference(_clock()));
        _checkWbiContext(context, epoch, deadline);
        return signer.sign(values, _clock());
      } on TimeoutException {
        throw const ApiFailure(ApiFailureCategory.timeout, 'wbi_key');
      }
    }
    return _wbi!.sign(values, now);
  }

  void _checkWbiContext(
    ApiRequestContext? context,
    int? epoch,
    DateTime deadline,
  ) {
    if (context?.cancellation?.isCancelled == true ||
        _sessionProvider?.sessionEpoch != epoch ||
        context?.sessionEpoch != null && context?.sessionEpoch != epoch) {
      throw const ApiFailure(ApiFailureCategory.cancelled, 'wbi_key');
    }
    if (!deadline.isAfter(_clock())) {
      throw const ApiFailure(ApiFailureCategory.timeout, 'wbi_key');
    }
  }

  Future<WbiSigner> _loadWbi(ApiRequestContext? context) async {
    final nav = await _json(
      _api.replace(path: '/x/web-interface/nav'),
      'wbi_key',
      context,
    );
    final wbi = _map(nav['wbi_img'], 'wbi_key');
    try {
      return WbiSigner.fromUrls(
        _requiredString(wbi['img_url'], 'wbi_key'),
        _requiredString(wbi['sub_url'], 'wbi_key'),
      );
    } on FormatException {
      throw const ApiFailure(ApiFailureCategory.protocol, 'wbi_key');
    }
  }

  Future<Map<String, Object?>> _wbiJson(
    String path,
    Map<String, String> parameters,
    String endpoint,
    ApiRequestContext? context, {
    Uri? origin,
  }) async {
    final base = origin ?? _api;
    var signed = await _signed(parameters, context);
    try {
      return await _json(
        base.replace(path: path, queryParameters: signed),
        endpoint,
        context,
      );
    } on ApiFailure catch (failure) {
      if (failure.businessCode != -403) rethrow;
      _wbi = null;
      _wbiFetched = null;
      signed = await _signed(parameters, context);
      return _json(
        base.replace(path: path, queryParameters: signed),
        endpoint,
        context,
      );
    }
  }

  Future<Map<String, Object?>> _json(
    Uri uri,
    String endpoint,
    ApiRequestContext? context,
  ) async => _map(await _jsonValue(uri, endpoint, context), endpoint);

  Future<Object?> _jsonValue(
    Uri uri,
    String endpoint,
    ApiRequestContext? context,
  ) async {
    final response = await _request(uri, endpoint, context);
    return _decodeJson(response, endpoint);
  }

  Object? _decodeJson(ApiHttpResponse response, String endpoint) {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.body));
    } on FormatException {
      throw ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    final root = _map(decoded, endpoint);
    if (endpoint == 'subtitle_body') return root;
    final code = _int(root['code']);
    if (code == null) throw ApiFailure(ApiFailureCategory.protocol, endpoint);
    // Guest nav returns -101 while still carrying the public WBI image keys.
    if (code == -101 && (endpoint == 'nav' || endpoint == 'wbi_key')) {
      return _map(root['data'], endpoint);
    }
    if (code != 0) {
      final category = switch (code) {
        -101 || -111 || -400 => ApiFailureCategory.authentication,
        -403 || -404 => ApiFailureCategory.permission,
        -412 || -352 => ApiFailureCategory.rateLimited,
        62002 || 62004 => ApiFailureCategory.notFound,
        _ => ApiFailureCategory.unavailable,
      };
      throw ApiFailure(category, endpoint, businessCode: code);
    }
    return root['data'] ?? root['result'];
  }

  Future<ApiHttpResponse> _request(
    Uri uri,
    String endpoint,
    ApiRequestContext? context,
  ) async {
    if (context?.cancellation?.isCancelled ?? false) {
      throw ApiFailure(ApiFailureCategory.cancelled, endpoint);
    }
    final epoch = _sessionProvider?.sessionEpoch;
    if (context?.sessionEpoch != null && context!.sessionEpoch != epoch) {
      throw ApiFailure(ApiFailureCategory.cancelled, endpoint);
    }
    final headers = <String, String>{
      'Accept': endpoint == 'danmaku_segment'
          ? 'application/octet-stream'
          : 'application/json',
      'User-Agent': endpoint == 'video_storyboard'
          ? 'Mozilla/5.0'
          : 'BiliSail/0.1',
      'Referer': 'https://www.bilibili.com/',
    };
    final cookie = cookieJar.headerFor(uri, now: _clock());
    if (cookie != null) headers['Cookie'] = cookie;
    final response = await _sendWithRetry(
      uri,
      endpoint,
      headers,
      context,
      epoch,
    );
    if (epoch != null && _sessionProvider?.sessionEpoch != epoch ||
        context?.cancellation?.isCancelled == true) {
      throw ApiFailure(ApiFailureCategory.cancelled, endpoint);
    }
    if (response.statusCode >= 300 && response.statusCode < 400) {
      // Redirects are never followed: a redirect must not receive credentials.
      throw ApiFailure(
        ApiFailureCategory.http,
        endpoint,
        httpStatus: response.statusCode,
      );
    }
    if (response.statusCode == 429) {
      throw ApiFailure(
        ApiFailureCategory.rateLimited,
        endpoint,
        httpStatus: response.statusCode,
      );
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw ApiFailure(
        ApiFailureCategory.authentication,
        endpoint,
        httpStatus: response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiFailure(
        ApiFailureCategory.http,
        endpoint,
        httpStatus: response.statusCode,
      );
    }
    if (endpoint == 'qr_poll' && response.header('set-cookie').isNotEmpty) {
      cookieJar.receive(uri, response.header('set-cookie'), now: _clock());
      await onCookiesChanged?.call();
    }
    return response;
  }

  Future<ApiHttpResponse> _sendWithRetry(
    Uri uri,
    String endpoint,
    Map<String, String> headers,
    ApiRequestContext? context,
    int? epoch,
  ) async {
    final deadline = context?.deadline ?? _clock().add(timeout);
    for (var attempt = 0; attempt < 3; attempt++) {
      if (context?.cancellation?.isCancelled == true ||
          (epoch != null && _sessionProvider?.sessionEpoch != epoch)) {
        throw ApiFailure(ApiFailureCategory.cancelled, endpoint);
      }
      final remaining = deadline.difference(_clock());
      if (remaining <= Duration.zero) {
        throw ApiFailure(ApiFailureCategory.timeout, endpoint);
      }
      try {
        final response = await _transport
            .get(
              uri,
              headers: headers,
              timeout: remaining,
              cancellation: context?.cancellation,
            )
            .timeout(remaining);
        if (attempt < 2 &&
            const [500, 502, 503, 504].contains(response.statusCode)) {
          await _retryDelay(attempt, deadline, context?.cancellation);
          continue;
        }
        return response;
      } on TimeoutException {
        if (attempt == 2) {
          throw ApiFailure(ApiFailureCategory.timeout, endpoint);
        }
      } on ApiFailure catch (failure) {
        if (attempt == 2 ||
            (failure.category != ApiFailureCategory.timeout &&
                failure.category != ApiFailureCategory.network)) {
          throw ApiFailure(
            failure.category,
            endpoint,
            httpStatus: failure.httpStatus,
            retryAfter: failure.retryAfter,
          );
        }
      }
      await _retryDelay(attempt, deadline, context?.cancellation);
    }
    throw ApiFailure(ApiFailureCategory.timeout, endpoint);
  }

  Future<void> _retryDelay(
    int attempt,
    DateTime deadline,
    ApiCancellation? cancellation,
  ) async {
    final delay = Duration(
      milliseconds: 200 * (1 << attempt) + Random().nextInt(100),
    );
    final remaining = deadline.difference(_clock());
    if (remaining <= Duration.zero) return;
    final wait = delay < remaining ? delay : remaining;
    if (cancellation == null) {
      await Future<void>.delayed(wait);
    } else {
      await Future.any<void>([
        Future<void>.delayed(wait),
        cancellation.whenCancelled.then(
          (_) => throw const ApiFailure(ApiFailureCategory.cancelled, 'retry'),
        ),
      ]);
    }
  }

  static ApiVideoSummary _videoSummary(
    Map<String, Object?> data,
    String endpoint,
  ) {
    final owner = _optionalMap(data['owner']) ?? _optionalMap(data['author']);
    final duration =
        _int(data['duration']) ??
        _parseDuration(_string(data['duration']) ?? '');
    final stat = _optionalMap(data['stat']);
    return ApiVideoSummary(
      bvid: _requiredString(data['bvid'], endpoint),
      previewCid: _userMid(data['cid']),
      title: _requiredString(
        data['title'],
        endpoint,
      ).replaceAll(RegExp(r'<[^>]*>'), ''),
      coverUrl: _uri(data['pic']),
      ownerName: _string(owner?['name']) ?? _string(data['author']) ?? '',
      ownerMid: _userMid(owner?['mid'] ?? data['mid']),
      ownerAvatarUrl: _uri(owner?['face'] ?? data['upic']),
      duration: Duration(seconds: duration),
      playCount: _count(stat?['view'] ?? data['play']),
      danmakuCount: _count(stat?['danmaku'] ?? data['video_review']),
      publishedAt: _publishedAt(data['pubdate']),
      recommendationReason: _recommendationReason(data['rcmd_reason']),
      recommendationFeedback: endpoint == 'recommended'
          ? _recommendationFeedback(data, owner)
          : null,
    );
  }

  static ApiRecommendationFeedback? _recommendationFeedback(
    Map<String, Object?> data,
    Map<String, Object?>? owner,
  ) {
    final rawId = data['id'];
    final aid = rawId is int || rawId is String ? '$rawId' : '';
    final trackId = _string(data['track_id']) ?? '';
    if (!RegExp(r'^[1-9]\d*$').hasMatch(aid) || data['goto'] != 'av') {
      return null;
    }
    return ApiRecommendationFeedback(
      aid: aid,
      goto: 'av',
      trackId: trackId,
      ownerMid: _userMid(owner?['mid']) ?? '0',
    );
  }

  static ApiMediaTrack _track(Map<String, Object?> data) {
    final url = _uri(data['baseUrl'] ?? data['base_url']);
    if (url == null) {
      throw const ApiFailure(ApiFailureCategory.protocol, 'playurl');
    }
    final backups = data['backupUrl'] ?? data['backup_url'];
    return ApiMediaTrack(
      id: _requiredInt(data['id'], 'playurl'),
      url: url,
      backupUrls: List.unmodifiable(
        backups is List ? backups.map(_uri).whereType<Uri>() : const <Uri>[],
      ),
      bandwidth: _int(data['bandwidth']) ?? 0,
      mimeType: _string(data['mimeType'] ?? data['mime_type']) ?? '',
      codecs: _string(data['codecs']) ?? '',
    );
  }

  static Map<String, Object?> _map(Object? value, String endpoint) {
    if (value is Map<String, Object?>) return value;
    throw ApiFailure(ApiFailureCategory.protocol, endpoint);
  }

  static Map<String, Object?>? _optionalMap(Object? value) =>
      value is Map<String, Object?> ? value : null;
  static List<Object?> _list(Object? value, String endpoint) {
    if (value is List) return value;
    throw ApiFailure(ApiFailureCategory.protocol, endpoint);
  }

  static String? _userMid(Object? value) {
    final text = value is int
        ? value.toString()
        : value is String
        ? value
        : null;
    return text != null && RegExp(r'^[1-9][0-9]*$').hasMatch(text)
        ? text
        : null;
  }

  static String? _string(Object? value) => value is String ? value : null;
  static String _requiredString(Object? value, String endpoint) {
    if (value is String && value.isNotEmpty) return value;
    throw ApiFailure(ApiFailureCategory.protocol, endpoint);
  }

  static String _id(Object? value, String endpoint) {
    if (value is int && value >= 0) return '$value';
    if (value is String && RegExp(r'^\d+$').hasMatch(value)) return value;
    throw ApiFailure(ApiFailureCategory.protocol, endpoint);
  }

  static int? _int(Object? value) => value is int
      ? value
      : value is String
      ? int.tryParse(value)
      : null;
  static int _requiredInt(Object? value, String endpoint) =>
      _int(value) ?? (throw ApiFailure(ApiFailureCategory.protocol, endpoint));
  static num? _num(Object? value) => value is num ? value : null;
  static bool? _bool(Object? value) => value is bool ? value : null;
  static int? _count(Object? value) {
    if (value is int && value >= 0) return value;
    if (value is String && RegExp(r'^\d+$').hasMatch(value)) {
      return int.tryParse(value);
    }
    return null;
  }

  static DateTime? _publishedAt(Object? value) {
    final seconds = _int(value);
    if (seconds == null || seconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  static Uri? _uri(Object? value) {
    if (value is! String || value.isEmpty) return null;
    final absolute = value.startsWith('//') ? 'https:$value' : value;
    final uri = Uri.tryParse(absolute);
    if (uri == null) return null;
    if (uri.scheme == 'https') return uri;
    final host = uri.host.toLowerCase();
    if (uri.scheme == 'http' &&
        (host == 'hdslb.com' ||
            host.endsWith('.hdslb.com') ||
            host == 'bilibili.com' ||
            host.endsWith('.bilibili.com'))) {
      return uri.replace(scheme: 'https');
    }
    return null;
  }

  static int _parseDuration(String value) {
    final parts = value.split(':').map(int.tryParse).toList();
    if (parts.isEmpty || parts.any((v) => v == null)) return 0;
    var seconds = 0;
    for (final part in parts) {
      seconds = seconds * 60 + part!;
    }
    return seconds;
  }

  static void _validateBvid(String bvid) {
    if (!RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(bvid)) {
      throw ArgumentError.value(bvid, 'bvid');
    }
  }
}

final _decodeGate = _DecodeGate();

Future<List<ApiDanmakuItem>> _decodeInIsolate(Uint8List bytes) {
  final payload = TransferableTypedData.fromList([bytes]);
  return Isolate.run(
    () => decodeDanmakuSegment(payload.materialize().asUint8List()),
  );
}

final class _DecodeGate {
  int _active = 0;
  final Queue<_DecodeWaiter> _waiting = Queue<_DecodeWaiter>();

  Future<void> enter(
    ApiCancellation? cancellation,
    DateTime deadline,
    DateTime Function() clock,
  ) async {
    if (cancellation?.isCancelled == true) {
      throw const ApiFailure(ApiFailureCategory.cancelled, 'danmaku_segment');
    }
    final remaining = deadline.difference(clock());
    if (remaining <= Duration.zero) {
      throw const ApiFailure(ApiFailureCategory.timeout, 'danmaku_segment');
    }
    if (_active < 2 && _waiting.isEmpty) {
      _active++;
      return;
    }
    if (_waiting.length >= 4) {
      throw const ApiFailure(ApiFailureCategory.unavailable, 'danmaku_segment');
    }
    final waiter = _DecodeWaiter();
    _waiting.add(waiter);
    final expired = Completer<void>();
    final timer = Timer(
      remaining,
      () => expired.completeError(
        const ApiFailure(ApiFailureCategory.timeout, 'danmaku_segment'),
      ),
    );
    try {
      await Future.any<void>([
        waiter.ready.future,
        expired.future,
        if (cancellation != null)
          cancellation.whenCancelled.then<void>(
            (_) => throw const ApiFailure(
              ApiFailureCategory.cancelled,
              'danmaku_segment',
            ),
          ),
      ]);
    } catch (_) {
      if (waiter.granted) {
        leave();
      } else {
        _waiting.remove(waiter);
      }
      rethrow;
    } finally {
      timer.cancel();
    }
  }

  void leave() {
    if (_waiting.isEmpty) {
      _active--;
      return;
    }
    final waiter = _waiting.removeFirst();
    waiter.granted = true;
    waiter.ready.complete();
  }
}

final class _DecodeWaiter {
  final Completer<void> ready = Completer<void>();
  bool granted = false;
}

/// Small bounded decoder for only the fields used by ordinary video comments.
List<ApiDanmakuItem> decodeDanmakuSegment(Uint8List bytes) {
  if (bytes.length > 2 * 1024 * 1024) {
    throw const ApiFailure(ApiFailureCategory.protocol, 'danmaku_segment');
  }
  const maxItems = 6000;
  // Signed-in pools can contain more than 6000 valid elements. Count framing
  // first, then sample across the entire reply while still validating every
  // element. The byte budget bounds both passes; retained objects stay bounded.
  final framing = _ProtoReader(bytes);
  var elementCount = 0;
  while (!framing.done) {
    final tag = framing.varint();
    if (tag >> 3 == 1 && tag & 7 == 2) elementCount++;
    framing.skip(tag & 7);
  }
  final reader = _ProtoReader(bytes);
  final items = <ApiDanmakuItem>[];
  var elementIndex = 0, previousBucket = -1;
  while (!reader.done) {
    final tag = reader.varint();
    if (tag >> 3 == 1 && tag & 7 == 2) {
      // Include the reply's first and last elements as well as evenly spaced
      // entries between them, so dense pools retain coverage across the reply.
      final bucket = elementCount > maxItems
          ? elementIndex * (maxItems - 1) ~/ (elementCount - 1)
          : elementIndex;
      elementIndex++;
      final retain = bucket != previousBucket;
      previousBucket = bucket;
      final element = _ProtoReader(reader.bytes(4096));
      String id = '';
      var progress = 0, mode = 1, fontSize = 25, color = 0xffffff;
      var weight = 0;
      String content = '';
      while (!element.done) {
        final field = element.varint();
        final number = field >> 3;
        final wire = field & 7;
        if (wire == 0) {
          final value = element.varint();
          switch (number) {
            case 1:
              id = '$value';
            case 2:
              progress = value;
            case 3:
              mode = value;
            case 4:
              fontSize = value;
            case 5:
              color = value;
            case 9:
              weight = value.clamp(0, 10);
          }
        } else if (wire == 2) {
          final value = element.bytes(1024);
          if (number == 7) {
            try {
              content = utf8.decode(value);
            } on FormatException {
              throw const ApiFailure(
                ApiFailureCategory.protocol,
                'danmaku_segment',
              );
            }
          }
        } else {
          element.skip(wire);
        }
      }
      if (retain &&
          content.isNotEmpty &&
          (mode == 1 || mode == 4 || mode == 5)) {
        items.add(
          ApiDanmakuItem(
            id: id,
            progress: Duration(milliseconds: progress),
            mode: mode,
            fontSize: fontSize,
            color: color,
            content: content,
            weight: weight,
          ),
        );
      }
    } else {
      reader.skip(tag & 7);
    }
  }
  return List.unmodifiable(items);
}

final class _ProtoReader {
  _ProtoReader(this.data);
  final Uint8List data;
  int offset = 0;
  bool get done => offset == data.length;

  int varint() {
    var value = 0;
    for (var shift = 0; shift < 64; shift += 7) {
      if (offset >= data.length) _invalid();
      final byte = data[offset++];
      value |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) return value;
    }
    _invalid();
  }

  Uint8List bytes(int max) {
    final length = varint();
    if (length < 0 || length > max || offset + length > data.length) _invalid();
    final result = Uint8List.sublistView(data, offset, offset + length);
    offset += length;
    return result;
  }

  void skip(int wire) {
    switch (wire) {
      case 0:
        varint();
      case 1:
        _advance(8);
      case 2:
        _advance(varint());
      case 5:
        _advance(4);
      default:
        _invalid();
    }
  }

  void _advance(int count) {
    if (count < 0 || offset + count > data.length) _invalid();
    offset += count;
  }

  Never _invalid() =>
      throw const ApiFailure(ApiFailureCategory.protocol, 'danmaku_segment');
}
