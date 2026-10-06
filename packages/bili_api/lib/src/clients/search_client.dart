import '../api_client.dart';
import '../models.dart';
import '../models/search_models.dart';

/// Cookie-optional Web search; App/gRPC credentials are never assumed.
final class SearchClient {
  const SearchClient(this.api);
  final BiliApiClient api;
  static const _endpoint = 'search';
  static const _types = {
    ApiSearchType.video: 'video',
    ApiSearchType.bangumi: 'media_bangumi',
    ApiSearchType.film: 'media_ft',
    ApiSearchType.live: 'live',
    ApiSearchType.article: 'article',
    ApiSearchType.user: 'bili_user',
  };

  Future<ApiSearchPage> search(
    String keyword, {
    ApiSearchType type = ApiSearchType.all,
    int page = 1,
    String order = 'totalrank',
    int orderSort = 0,
    int duration = 0,
    int userType = 0,
    ApiRequestContext? context,
  }) async {
    final orders = switch (type) {
      ApiSearchType.all || ApiSearchType.video => const {
        'totalrank',
        'click',
        'pubdate',
        'dm',
        'stow',
      },
      ApiSearchType.article => const {
        'totalrank',
        'click',
        'pubdate',
        'attention',
        'scores',
      },
      ApiSearchType.user => const {'totalrank', 'fans', 'level'},
      _ => const {'totalrank'},
    };
    if (keyword.trim().isEmpty ||
        page < 1 ||
        !orders.contains(order) ||
        orderSort < 0 ||
        orderSort > 1 ||
        duration < 0 ||
        duration > 4 ||
        userType < 0 ||
        userType > 2 ||
        (duration != 0 &&
            type != ApiSearchType.all &&
            type != ApiSearchType.video) ||
        (userType != 0 && type != ApiSearchType.user)) {
      throw ArgumentError('Invalid search options');
    }
    final all = type == ApiSearchType.all;
    // All/v2 ranks mixed modules but ignores video order/duration in live
    // responses. Subsequent pages contain only the independently ranked videos.
    if (all && page > 1) {
      return search(
        keyword,
        type: ApiSearchType.video,
        page: page,
        order: order,
        duration: duration,
        context: context,
      );
    }
    final data = await api.requestWbiJson(
      all
          ? '/x/web-interface/wbi/search/all/v2'
          : '/x/web-interface/wbi/search/type',
      {
        if (!all) 'search_type': _types[type] ?? '',
        'keyword': keyword.trim(),
        'page': '$page',
        'page_size': '20',
        'order': all
            ? 'totalrank'
            : type == ApiSearchType.user && order == 'totalrank'
            ? ''
            : order,
        if (type == ApiSearchType.user) ...{
          'order_sort': '$orderSort',
          'user_type': '$userType',
        },
        if (all || type == ApiSearchType.video)
          'duration': all ? '0' : '$duration',
        if (type == ApiSearchType.live) 'cover_type': 'user_cover',
        'highlight': '1',
      },
      _endpoint,
      context: context,
    );
    final counts = <ApiSearchType, int>{};
    final items = <ApiSearchItem>[];
    final pageInfo = _optionalMap(data['pageinfo']);
    for (final entry in _types.entries) {
      final key = entry.key == ApiSearchType.live ? 'live_room' : entry.value;
      final total = _int(_optionalMap(pageInfo[key])['numResults']);
      if (total != null && total >= 0) counts[entry.key] = total;
    }
    int? pages;
    if (all) {
      for (final raw in _list(
        data['result'],
        nullIfEmpty: counts.isNotEmpty && counts.values.every((v) => v == 0),
      ).take(30)) {
        final group = _map(raw);
        final groupType = _text(group['result_type']);
        final category = _category(groupType);
        // Ads, topic cards and future modules are not search content types.
        if (category == null) continue;
        items.addAll(_items(category, group['data']));
      }
      // Use the same video source on every page, including default relevance.
      final videoPage = await search(
        keyword,
        type: ApiSearchType.video,
        order: order,
        duration: duration,
        context: context,
      );
      items.removeWhere((item) => item is ApiSearchVideo);
      items.addAll(videoPage.items);
      counts.addAll(videoPage.counts);
      return ApiSearchPage(
        items: items,
        counts: counts,
        hasMore: videoPage.hasMore,
      );
    } else if (type == ApiSearchType.live) {
      final result = _map(data['result']);
      final info = _optionalMap(pageInfo['live_room']);
      items.addAll(
        _items(
          type,
          result['live_room'],
          nullIfEmpty: _int(info['numResults']) == 0,
        ),
      );
      pages = _int(info['numPages']);
    } else {
      final total = _int(data['numResults']);
      if (total != null && total >= 0) counts[type] = total;
      items.addAll(_items(type, data['result'], nullIfEmpty: total == 0));
      pages = _int(data['numPages']);
    }
    final pageable = items.length;
    return ApiSearchPage(
      items: items,
      counts: counts,
      hasMore: pageable > 0 && (pages == null ? pageable >= 20 : page < pages),
    );
  }

  static ApiSearchType? _category(String type) => switch (type) {
    'video' => ApiSearchType.video,
    'media_bangumi' => ApiSearchType.bangumi,
    'media_ft' => ApiSearchType.film,
    'live_room' => ApiSearchType.live,
    'article' => ApiSearchType.article,
    'bili_user' => ApiSearchType.user,
    _ => null,
  };

  static Iterable<ApiSearchItem> _items(
    ApiSearchType type,
    Object? raw, {
    bool nullIfEmpty = false,
  }) sync* {
    for (final value in _list(raw, nullIfEmpty: nullIfEmpty).take(100)) {
      final item = _map(value);
      switch (type) {
        case ApiSearchType.video:
          // The video endpoint also embeds live advertisements without BVIDs.
          if (_text(item['bvid']).isEmpty &&
              _text(item['type']).isNotEmpty &&
              _text(item['type']) != 'video') {
            continue;
          }
          yield ApiSearchVideo(_video(item));
        case ApiSearchType.user:
          final mid = _id(item['mid']);
          final official = _optionalMap(item['official_verify']);
          yield ApiSearchUser(
            mid: mid,
            name: _requiredText(item['uname']),
            avatarUrl: _uri(item['upic']),
            signature: _clean(
              _text(official['desc']).isNotEmpty
                  ? official['desc']
                  : item['usign'],
            ),
            fans: _int(item['fans']),
            videoCount: _int(item['videos']),
            level: _int(item['level']),
            verifyType: _int(official['type']),
            videos: _list(item['res'] ?? const [], nullIfEmpty: true)
                .take(6)
                .map(
                  (v) => _video({
                    ..._map(v),
                    'mid': mid,
                    'author': _text(item['uname']),
                  }),
                )
                .toList(),
          );
        case ApiSearchType.bangumi || ApiSearchType.film:
          yield ApiSearchMedia(
            seasonId: _id(item['season_id']),
            title: _requiredText(item['title']),
            type: type,
            coverUrl: _uri(item['cover']),
            description: _clean(item['desc']),
            areas: _clean(item['areas']),
            styles: _clean(item['styles']),
            updateText: _clean(_optionalMap(item['new_ep'])['index_show']),
            badge: _clean(item['angle_title']),
            score: _number(_optionalMap(item['media_score'])['score']),
          );
        case ApiSearchType.live:
          final status = _int(item['live_status']);
          yield ApiSearchLive(
            roomId: _id(item['roomid']),
            title: _requiredText(item['title']),
            author: _clean(item['uname']),
            authorMid: _optionalId(item['uid'] ?? item['mid']),
            coverUrl: _uri(
              _text(item['user_cover']).isEmpty
                  ? item['cover']
                  : item['user_cover'],
            ),
            area: _clean(item['cate_name']),
            online: _int(item['online']),
            isLive: status == null ? null : status == 1,
          );
        case ApiSearchType.article:
          final images = _list(item['image_urls'] ?? const []);
          yield ApiSearchArticle(
            id: _id(item['id']),
            title: _requiredText(item['title']),
            author: _clean(item['author']),
            authorMid: _optionalId(item['mid']),
            coverUrl: _uri(images.firstOrNull),
            description: _clean(item['desc']),
            category: _clean(item['category_name']),
            views: _int(item['view']),
            likes: _int(item['like']),
            replies: _int(item['reply']),
            publishedAt: _date(item['pub_time'] ?? item['pubdate']),
          );
        case ApiSearchType.all:
          throw StateError('All is a query, not an item type');
      }
    }
  }

  static ApiVideoSummary _video(Map<String, Object?> item) {
    final bvid = _text(item['bvid']);
    if (!RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(bvid)) _fail();
    final rawDuration = item['duration'];
    var seconds = _int(rawDuration);
    if (seconds == null && rawDuration is String) {
      final parts = rawDuration.split(':');
      if (parts.length >= 2 &&
          parts.length <= 3 &&
          parts.every((v) => int.tryParse(v) != null)) {
        seconds = parts.fold<int>(
          0,
          (total, part) => total * 60 + int.parse(part),
        );
      }
    }
    return ApiVideoSummary(
      bvid: bvid,
      title: _requiredText(item['title']),
      coverUrl: _uri(item['pic']),
      ownerName: _clean(item['author']),
      ownerMid: _optionalId(item['mid']),
      ownerAvatarUrl: _uri(item['upic']),
      duration: Duration(seconds: seconds ?? 0),
      playCount: _int(item['play']),
      danmakuCount: _int(item['video_review'] ?? item['danmaku']),
      publishedAt: _date(item['pubdate']),
    );
  }

  static Never _fail() =>
      throw const ApiFailure(ApiFailureCategory.protocol, _endpoint);
  static Map<String, Object?> _map(Object? value) =>
      value is Map<String, Object?> ? value : _fail();
  static Map<String, Object?> _optionalMap(Object? value) =>
      value is Map<String, Object?> ? value : const {};
  static List<Object?> _list(Object? value, {bool nullIfEmpty = false}) =>
      value is List<Object?>
      ? value
      : value == null && nullIfEmpty
      ? const []
      : _fail();
  static String _text(Object? v) => v is String ? v : '';
  static int? _int(Object? v) => v is int
      ? v
      : v is String
      ? int.tryParse(v)
      : null;
  static double? _number(Object? v) => v is num
      ? v.toDouble()
      : v is String
      ? double.tryParse(v)
      : null;
  static String? _optionalId(Object? v) {
    final text = v is int ? '$v' : _text(v);
    return RegExp(r'^[1-9][0-9]*$').hasMatch(text) ? text : null;
  }

  static String _id(Object? v) => _optionalId(v) ?? _fail();
  static String _requiredText(Object? v) {
    final text = _clean(v);
    return text.isEmpty ? _fail() : text;
  }

  static Uri? _uri(Object? value) {
    final text = _text(value);
    final uri = Uri.tryParse(text.startsWith('//') ? 'https:$text' : text);
    return uri != null &&
            const {'http', 'https'}.contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty
        ? uri.replace(scheme: 'https')
        : null;
  }

  static DateTime? _date(Object? value) {
    final seconds = _int(value);
    return seconds == null || seconds <= 0 || seconds > 253402300799
        ? null
        : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  /// Strip markup before decoding entities so encoded user text stays literal.
  static String _clean(Object? v) =>
      _text(v).replaceAll(RegExp(r'<[^>]*>'), '').replaceAllMapped(
        RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos|nbsp);'),
        (m) {
          final entity = m[1] ?? '';
          final code = entity.startsWith('#x')
              ? int.tryParse(entity.substring(2), radix: 16)
              : entity.startsWith('#')
              ? int.tryParse(entity.substring(1))
              : null;
          if (code != null &&
              code > 0 &&
              code <= 0x10ffff &&
              !(code >= 0xd800 && code <= 0xdfff)) {
            return String.fromCharCode(code);
          }
          return const {
                'amp': '&',
                'lt': '<',
                'gt': '>',
                'quot': '"',
                'apos': "'",
                'nbsp': ' ',
              }[entity] ??
              m[0] ??
              '';
        },
      ).trim();
}
