import '../api_client.dart';
import '../models.dart';
import '../models/dynamic_models.dart';
import '../models/dynamic_topic_models.dart';
import '../mappers/dynamic_post_parser.dart';

final class DynamicTopicClient {
  const DynamicTopicClient(this.api);
  final BiliApiClient api;

  Future<ApiDynamicTopicDetail> detail(
    String id, {
    ApiRequestContext? context,
  }) async {
    _validate(id);
    const endpoint = 'dynamic_topic_detail';
    final data = await api.requestJson(
      Uri.https('app.bilibili.com', '/x/topic/web/details/top', {
        'topic_id': id,
        'source': 'Web',
      }),
      endpoint,
      context: context,
    );
    final top = _map(data['top_details']);
    final item = _map(top['topic_item']);
    final actualId = _id(item['id']);
    final name = _text(item['name']);
    if (actualId != id || name.isEmpty) {
      throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    final creator = _map(top['topic_creator']);
    return ApiDynamicTopicDetail(
      id: id,
      name: name,
      description: _text(item['description']),
      viewCount: _count(item['view']),
      discussCount: _count(item['discuss']),
      creatorId: _id(creator['uid']),
      creatorName: _text(creator['name']),
      creatorAvatar: _uri(creator['face']),
      favoriteCount: _count(item['fav']),
      isFavorite: item['is_fav'] == true || item['is_fav'] == 1,
    );
  }

  Future<void> favorite(
    String id,
    bool favorite, {
    ApiRequestContext? context,
  }) async {
    _validate(id);
    await api.submitForm(
      favorite ? '/x/topic/fav/sub/add' : '/x/topic/fav/sub/cancel',
      'dynamic_topic_favorite',
      {'topic_id': id},
      context: context,
    );
  }

  Future<void> report(
    String id,
    String reason, {
    ApiRequestContext? context,
  }) async {
    _validate(id);
    if (reason.trim().isEmpty || reason.runes.length > 1000) {
      throw ArgumentError('Invalid topic report');
    }
    await api.submitForm('/x/topic/report', 'dynamic_topic_report', {
      'topic_id': id,
      'reason': reason,
    }, context: context);
  }

  Future<ApiDynamicTopicPage> feed(
    String id, {
    int sort = 0,
    String? cursor,
    bool folded = false,
    ApiRequestContext? context,
  }) async {
    _validate(id);
    if (sort < 0 || sort > 255 || cursor != null && cursor.length > 2048) {
      throw ArgumentError('Invalid topic query');
    }
    final endpoint = folded ? 'dynamic_topic_fold' : 'dynamic_topic_feed';
    final data = await api.requestJson(
      Uri.https(
        'api.bilibili.com',
        folded
            ? '/x/topic/web/details/fold'
            : '/x/polymer/web-dynamic/v1/feed/topic',
        {
          'topic_id': id,
          'sort_by': '$sort',
          'source': 'Web',
          if (!folded) ...{
            'page_size': '20',
            'features': 'itemOpusStyle',
            if (cursor != null && cursor.isNotEmpty) 'offset': cursor,
          },
        },
      ),
      endpoint,
      context: context,
    );
    final page = data['topic_card_list'];
    if (data.containsKey('topic_card_list') && page == null) {
      return ApiDynamicTopicPage(posts: const [], hasMore: false);
    }
    if (page is! Map<String, Object?> || page['items'] is! List<Object?>) {
      throw ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    final posts = <ApiDynamicPost>[];
    var foldDescription = '';
    for (final raw in (page['items']! as List<Object?>).take(50)) {
      final item = _map(raw);
      if (item['dynamic_card_item'] case final Map<String, Object?> post) {
        posts.add(parseDynamicPost(post, endpoint));
      } else if (item['dynamic_card_item'] != null) {
        throw ApiFailure(ApiFailureCategory.protocol, endpoint);
      }
      final fold = _map(item['fold_card_item']);
      if (fold.isNotEmpty) {
        foldDescription = _text(
          fold['fold_desc'],
          fallback: '查看折叠的动态（${_count(fold['fold_count'])}）',
        );
      }
    }
    final config = _map(page['topic_sort_by_conf']);
    final sorts = <ApiDynamicTopicSort>[];
    final rawSorts = config['all_sort_by'];
    if (rawSorts is List<Object?>) {
      for (final raw in rawSorts.take(8)) {
        final value = _map(raw);
        final id = _integer(value['sort_by']);
        final name = _text(value['sort_name']);
        if (id != null &&
            id >= 0 &&
            id <= 255 &&
            name.isNotEmpty &&
            !sorts.any((s) => s.id == id)) {
          sorts.add(ApiDynamicTopicSort(id, name));
        }
      }
    }
    final next = page['offset'];
    if (next != null && (next is! String || next.length > 2048)) {
      throw ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    return ApiDynamicTopicPage(
      posts: posts,
      hasMore: page['has_more'] == true || page['has_more'] == 1,
      nextCursor: next is String && next.isNotEmpty ? next : null,
      sorts: sorts,
      selectedSort: _integer(config['show_sort_by']),
      foldDescription: foldDescription,
    );
  }

  static void _validate(String id) {
    if (_id(id) == null) throw ArgumentError.value(id, 'topicId');
  }
}

Map<String, Object?> _map(Object? value) =>
    value is Map<String, Object?> ? value : const {};
String _text(Object? value, {String fallback = ''}) =>
    value is String && value.isNotEmpty
    ? value.substring(0, value.length.clamp(0, 32768))
    : fallback;
String? _id(Object? value) {
  final text = value is int
      ? '$value'
      : value is String
      ? value
      : '';
  return text.length <= 128 && RegExp(r'^[1-9][0-9]*$').hasMatch(text)
      ? text
      : null;
}

int? _integer(Object? value) => value is int
    ? value
    : value is String
    ? int.tryParse(value)
    : null;
int _count(Object? value) =>
    (_integer(value) ?? 0).clamp(0, 0x7fffffffffffffff);
Uri? _uri(Object? value) {
  if (value is! String || value.length > 8192) return null;
  final uri = Uri.tryParse(value.startsWith('//') ? 'https:$value' : value);
  return uri != null &&
          ['http', 'https'].contains(uri.scheme) &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? uri.replace(scheme: 'https')
      : null;
}
