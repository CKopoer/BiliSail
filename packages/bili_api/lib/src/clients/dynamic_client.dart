import '../api_client.dart';
import '../mappers/dynamic_post_parser.dart';
import '../models.dart';
import '../models/dynamic_models.dart';

final class DynamicClient {
  const DynamicClient(this.api);
  final BiliApiClient api;

  Future<ApiDynamicPost> detail(String id, {ApiRequestContext? context}) async {
    _id(id);
    const endpoint = 'dynamic_detail';
    final data = await api.requestJson(
      Uri.https('api.bilibili.com', '/x/polymer/web-dynamic/v1/detail', {
        'id': id,
        'features': 'itemOpusStyle',
      }),
      endpoint,
      context: context,
    );
    final item = data['item'];
    if (item is! Map<String, Object?>) {
      throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    final post = parseDynamicPost(item, endpoint);
    if (post.id != id) {
      throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    return post;
  }

  Future<void> like(String id, bool liked, {ApiRequestContext? context}) async {
    _id(id);
    await api.submitDynamicJson('/x/dynamic/feed/dyn/thumb', 'dynamic_like', {
      'dyn_id_str': id,
      'up': liked ? 1 : 2,
    }, context: context);
  }

  Future<String> repost(
    String id,
    String text, {
    ApiRequestContext? context,
  }) async {
    _id(id);
    if (text.runes.length > 1000) throw ArgumentError('Repost text too long');
    const endpoint = 'dynamic_repost';
    final result = await api.submitDynamicJson(
      '/x/dynamic/feed/create/dyn',
      endpoint,
      {
        'dyn_req': {
          'scene': 4,
          'content': {
            'contents': [
              {
                'raw_text': text.trim().isEmpty ? '转发动态' : text,
                'type': 1,
                'biz_id': '',
              },
            ],
          },
          'meta': {
            'app_meta': {'from': 'create.dynamic.web', 'mobi_app': 'web'},
          },
        },
        'web_repost_src': {'dyn_id_str': id},
      },
      context: context,
    );
    final newId = result is Map<String, Object?> ? result['dyn_id_str'] : null;
    if (newId is! String || !_validId(newId)) {
      throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    return newId;
  }

  static bool _validId(String id) =>
      id.length <= 128 && RegExp(r'^[1-9]\d*$').hasMatch(id);
  static void _id(String id) {
    if (!_validId(id)) throw ArgumentError.value(id, 'dynamicId');
  }
}
