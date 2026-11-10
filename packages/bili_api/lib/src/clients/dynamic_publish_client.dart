import 'dart:math';
import 'dart:typed_data';

import '../api_client.dart';
import '../models.dart';
import '../models/dynamic_composer_models.dart';

final class DynamicPublishClient {
  const DynamicPublishClient(this.api);
  final BiliApiClient api;

  Future<List<ApiDynamicMention>> mentions(
    String keyword, {
    ApiRequestContext? context,
  }) async {
    if (keyword.length > 512) throw ArgumentError('Mention query too long');
    const endpoint = 'dynamic_mentions';
    final data = await api.requestJson(
      Uri.https(
        'api.bilibili.com',
        '/x/polymer/web-dynamic/v1/mention/search',
        {
          if (keyword.isNotEmpty) 'keyword': keyword,
          'web_location': '333.1365',
        },
      ),
      endpoint,
      context: context,
    );
    final groups = data['groups'];
    if (groups is! List<Object?>) {
      throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    final items = <String, ApiDynamicMention>{};
    for (final group in groups.take(20)) {
      if (group is! Map<String, Object?> || group['items'] is! List<Object?>) {
        continue;
      }
      for (final item in (group['items'] as List<Object?>).take(100)) {
        if (item is! Map<String, Object?>) continue;
        final id = _id(item['uid']), name = item['name'];
        if (id == null ||
            name is! String ||
            name.trim().isEmpty ||
            name.length > 100) {
          continue;
        }
        final face = item['face'];
        final avatar = face is String
            ? Uri.tryParse(face.startsWith('//') ? 'https:$face' : face)
            : null;
        items[id] = ApiDynamicMention(
          id,
          name,
          avatar?.scheme == 'https' && avatar?.userInfo == '' ? avatar : null,
        );
        if (items.length == 100) return List.unmodifiable(items.values);
      }
    }
    return List.unmodifiable(items.values);
  }

  Future<String> createPoll({
    required String mid,
    required String title,
    String description = '',
    required List<ApiDynamicPollOption> options,
    required int maxChoices,
    required DateTime endsAt,
    ApiRequestContext? context,
  }) async {
    final duration = endsAt.difference(DateTime.now()).inSeconds;
    final withImages = options.any((o) => o.imageUrl != null);
    if (_id(mid) == null ||
        title.trim().isEmpty ||
        title.runes.length > 100 ||
        description.runes.length > 500 ||
        options.length < 2 ||
        options.length > 20 ||
        maxChoices < 1 ||
        maxChoices > options.length ||
        duration <= 0 ||
        duration > 90 * 86400 ||
        options.any(
          (o) =>
              o.text.trim().isEmpty ||
              o.text.runes.length > 50 ||
              (withImages && (o.imageUrl == null || !_pictureUrl(o.imageUrl!))),
        )) {
      throw ArgumentError('Invalid poll');
    }
    final data = await api.submitDynamicJson(
      '/x/vote/create',
      'dynamic_poll_create',
      {
        'vote_info': {
          'title': title,
          'desc': description,
          'type': withImages ? 1 : 0,
          'choice_cnt': maxChoices,
          'duration': duration,
          'only_fans_level': 0,
          'vote_publisher': int.parse(mid),
          'options': [
            for (final o in options)
              {'opt_desc': o.text, 'img_url': o.imageUrl?.toString() ?? ''},
          ],
        },
      },
      context: context,
    );
    return _createdId(data, 'vote_id', 'dynamic_poll_create');
  }

  Future<String> createReserve({
    required String title,
    required DateTime startsAt,
    bool onlyMembers = false,
    ApiRequestContext? context,
  }) async {
    final duration = startsAt.difference(DateTime.now());
    if (title.trim().isEmpty ||
        title.runes.length > 50 ||
        duration <= Duration.zero ||
        duration > const Duration(days: 90)) {
      throw ArgumentError('Invalid reservation');
    }
    final data = await api.createDynamicReserve({
      'type': '2',
      'sub_type': onlyMembers ? '1' : '0',
      'from': '1',
      'title': title,
      'live_plan_start_time': '${startsAt.millisecondsSinceEpoch ~/ 1000}',
    }, context: context);
    return _createdId(data, 'sid', 'dynamic_reserve_create');
  }

  Future<List<ApiDynamicComposeTopic>> topics(
    String keyword, {
    ApiRequestContext? context,
  }) async {
    if (keyword.length > 512) throw ArgumentError('Topic query too long');
    const endpoint = 'dynamic_compose_topics';
    final data = await api.requestJson(
      Uri.https('app.bilibili.com', '/x/topic/pub/search', {
        'keywords': keyword,
        'content': '',
        'page_size': '20',
        'page_num': '1',
        'web_location': '333.1365',
      }),
      endpoint,
      context: context,
    );
    final items = data['topic_items'];
    if (items != null && items is! List<Object?>) {
      throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    final result = <ApiDynamicComposeTopic>[];
    for (final item in (items as List<Object?>? ?? const []).take(20)) {
      if (item is! Map<String, Object?>) continue;
      final id = _id(item['id']);
      final name = item['name'];
      if (id != null && name is String && name.trim().isNotEmpty) {
        result.add(ApiDynamicComposeTopic(id, name));
      }
    }
    return List.unmodifiable(result);
  }

  Future<ApiDynamicPicture> upload(
    Uint8List bytes,
    String mimeType, {
    bool forPoll = false,
    ApiRequestContext? context,
  }) => api.uploadDynamicPicture(
    bytes,
    mimeType,
    forPoll: forPoll,
    context: context,
  );

  Future<String> create({
    required String mid,
    required String text,
    List<ApiDynamicPicture> pictures = const [],
    ApiDynamicComposeTopic? topic,
    String title = '',
    List<ApiDynamicContent>? contents,
    bool onlySelf = false,
    int replyPolicy = 0,
    DateTime? publishAt,
    String? reserveId,
    ApiRequestContext? context,
  }) async {
    final rich = contents ?? [ApiDynamicContent(text, 1)];
    final raw = rich.map((c) => c.text).join();
    final now = DateTime.now();
    if (_id(mid) == null ||
        title.runes.length > 20 ||
        rich.length > 1000 ||
        raw != text ||
        raw.runes.length > 1000 ||
        rich.any(
          (c) =>
              !const {1, 2, 4, 9}.contains(c.type) ||
              (const {2, 4}.contains(c.type) && _id(c.id) == null),
        ) ||
        (text.trim().isEmpty && pictures.isEmpty && reserveId == null) ||
        pictures.length > 18 ||
        replyPolicy < 0 ||
        replyPolicy > 2 ||
        (reserveId != null && _id(reserveId) == null) ||
        (publishAt != null &&
            (onlySelf ||
                publishAt.isBefore(now.add(const Duration(minutes: 6))) ||
                publishAt.isAfter(now.add(const Duration(days: 7))))) ||
        (topic != null &&
            (_id(topic.id) == null ||
                topic.name.trim().isEmpty ||
                topic.name.length > 512))) {
      throw ArgumentError('Invalid dynamic draft');
    }
    for (final picture in pictures) {
      final uri = picture.url;
      if (uri.scheme != 'https' ||
          uri.port != 443 ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          !(uri.host.endsWith('.hdslb.com') ||
              uri.host.endsWith('.biliimg.com')) ||
          picture.width <= 0 ||
          picture.height <= 0 ||
          picture.width > 20000 ||
          picture.height > 20000 ||
          picture.width * picture.height > 40000000 ||
          !picture.sizeKiB.isFinite ||
          picture.sizeKiB <= 0 ||
          picture.sizeKiB > 10240) {
        throw ArgumentError('Invalid dynamic picture');
      }
    }
    const endpoint = 'dynamic_publish';
    final result = await api.submitDynamicJson(
      '/x/dynamic/feed/create/dyn',
      endpoint,
      {
        'dyn_req': {
          'scene': pictures.isEmpty ? 1 : 2,
          'content': {
            if (title.isNotEmpty) 'title': title,
            'contents': [
              for (final c in rich)
                {'raw_text': c.text, 'type': c.type, 'biz_id': c.id},
            ],
          },
          if (onlySelf || replyPolicy != 0 || publishAt != null)
            'option': {
              if (onlySelf) 'private_pub': 1,
              if (replyPolicy == 1) 'close_comment': 1,
              if (replyPolicy == 2) 'up_choose_comment': 1,
              if (publishAt != null)
                'timer_pub_time': publishAt.millisecondsSinceEpoch ~/ 1000,
            },
          if (reserveId != null)
            'attach_card': {
              'common_card': {
                'type': 14,
                'biz_id': int.parse(reserveId),
                'reserve_source': 0,
                'reserve_lottery': 0,
              },
            },
          if (pictures.isNotEmpty)
            'pics': [
              for (final picture in pictures)
                {
                  'img_src': picture.url.toString(),
                  'img_width': picture.width,
                  'img_height': picture.height,
                  'img_size': picture.sizeKiB,
                },
            ],
          if (topic != null)
            'topic': {
              'id': int.parse(topic.id),
              'name': topic.name,
              'from_source': 'dyn.web.list',
              'from_topic_id': 0,
            },
          'upload_id':
              '${mid}_${DateTime.now().millisecondsSinceEpoch ~/ 1000}_${1000 + Random.secure().nextInt(9000)}',
          'meta': {
            'app_meta': {'from': 'create.dynamic.web', 'mobi_app': 'web'},
          },
        },
      },
      context: context,
    );
    final id = result is Map<String, Object?>
        ? _id(result['dyn_id_str']) ?? _id(result['dyn_id'])
        : null;
    if (id == null) {
      throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    return id;
  }
}

String _createdId(Object? data, String field, String endpoint) {
  final id = data is Map<String, Object?> ? _id(data[field]) : null;
  if (id == null) throw ApiFailure(ApiFailureCategory.protocol, endpoint);
  return id;
}

bool _pictureUrl(Uri uri) =>
    uri.scheme == 'https' &&
    uri.port == 443 &&
    uri.userInfo.isEmpty &&
    !uri.hasQuery &&
    !uri.hasFragment &&
    (uri.host.endsWith('.hdslb.com') || uri.host.endsWith('.biliimg.com'));

String? _id(Object? value) {
  final text = value is int
      ? '$value'
      : value is String
      ? value
      : '';
  return text.length <= 128 &&
          RegExp(r'^[1-9][0-9]*$').hasMatch(text) &&
          int.tryParse(text) != null
      ? text
      : null;
}
