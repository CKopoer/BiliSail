import 'dart:math';
import 'dart:typed_data';

import '../api_client.dart';
import '../models.dart';
import '../models/dynamic_composer_models.dart';

final class DynamicPublishClient {
  const DynamicPublishClient(this.api);
  final BiliApiClient api;

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
    ApiRequestContext? context,
  }) => api.uploadDynamicPicture(bytes, mimeType, context: context);

  Future<String> create({
    required String mid,
    required String text,
    List<ApiDynamicPicture> pictures = const [],
    ApiDynamicComposeTopic? topic,
    ApiRequestContext? context,
  }) async {
    if (_id(mid) == null ||
        text.runes.length > 1000 ||
        (text.trim().isEmpty && pictures.isEmpty) ||
        pictures.length > 9 ||
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
            'contents': [
              {'raw_text': text, 'type': 1, 'biz_id': ''},
            ],
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
