import 'dart:convert';
import '../api_client.dart';
import '../mappers/dynamic_post_parser.dart';
import '../models.dart';
import '../models/dynamic_models.dart';
import '../models/dynamic_management_models.dart';
import '../models/dynamic_composer_models.dart';

final class DynamicClient {
  const DynamicClient(this.api);
  final BiliApiClient api;

  Future<void> remove(String id, {ApiRequestContext? context}) async {
    _id(id);
    await api.submitDynamicJson(
      '/x/dynamic/feed/operate/remove',
      'dynamic_remove',
      {'dyn_id_str': id},
      context: context,
    );
  }

  Future<void> pin(String id, bool pinned, {ApiRequestContext? context}) async {
    _id(id);
    await api.submitDynamicJson(
      pinned ? '/x/dynamic/feed/space/set_top' : '/x/dynamic/feed/space/rm_top',
      'dynamic_pin',
      {'dyn_str': id},
      context: context,
    );
  }

  Future<void> visibility(
    String id,
    bool onlySelf, {
    ApiRequestContext? context,
  }) async {
    _id(id);
    await api.submitDynamicJson(
      '/x/dynamic/feed/dyn/private_pub_setting',
      'dynamic_visibility',
      {
        'object_id': jsonEncode({'dyn_id': id}),
        'action': onlySelf ? 'private_pub' : 'public_pub',
      },
      context: context,
    );
  }

  Future<void> report(
    String id,
    String author,
    int reason,
    String description, {
    ApiRequestContext? context,
  }) async {
    _id(id);
    _id(author);
    if (!const {0, 1, 3, 4, 5, 8, 9, 10, 12, 13}.contains(reason) ||
        description.runes.length > 500 ||
        (reason == 0 && description.trim().isEmpty)) {
      throw ArgumentError('Invalid report');
    }
    await api.submitDynamicForm(
      '/x/dynamic/feed/dynamic_report/add',
      'dynamic_report',
      {
        'accused_uid': author,
        'dynamic_id': id,
        'reason_type': '$reason',
        'reason_desc': description,
      },
      context: context,
    );
  }

  Future<ApiDynamicInteraction> interaction(
    String oid,
    int type, {
    ApiRequestContext? context,
  }) async {
    _id(oid);
    if (type <= 0) throw ArgumentError('Invalid comment type');
    const endpoint = 'dynamic_interaction';
    final data = await api.requestJson(
      Uri.https('api.bilibili.com', '/x/v2/reply/subject/interaction-status', {
        'oid': oid,
        'type': '$type',
        'web_location': '333.1369',
      }),
      endpoint,
      context: context,
    );
    final selection = data['up_reply_selection'], reply = data['up_reply'];
    if (selection is! Map<String, Object?> ||
        reply is! Map<String, Object?> ||
        selection['can_modify'] is! bool ||
        reply['can_modify'] is! bool ||
        selection['status'] is! int ||
        reply['status'] is! int) {
      throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    return ApiDynamicInteraction(
      canSelect: selection['can_modify'] as bool,
      selected: selection['status'] == 1,
      canComment: reply['can_modify'] as bool,
      comments: reply['status'] == 1,
    );
  }

  Future<void> setInteraction(
    String oid,
    int type,
    int action, {
    ApiRequestContext? context,
  }) async {
    _id(oid);
    if (type <= 0 || action < 1 || action > 4) {
      throw ArgumentError('Invalid interaction action');
    }
    await api.submitDynamicForm(
      '/x/v2/reply/subject/modify',
      'dynamic_interaction_modify',
      {'oid': oid, 'type': '$type', 'action': '$action'},
      context: context,
    );
  }

  Future<bool> publicVisible(String id, {ApiRequestContext? context}) async {
    _id(id);
    final data = await api.publicDynamicDetail(id, context: context);
    final item = data['item'];
    if (item is! Map<String, Object?>) {
      throw const ApiFailure(
        ApiFailureCategory.protocol,
        'dynamic_public_check',
      );
    }
    final post = parseDynamicPost(item, 'dynamic_public_check');
    if (post.id != id) {
      throw const ApiFailure(
        ApiFailureCategory.protocol,
        'dynamic_public_check',
      );
    }
    return !post.unavailable;
  }

  Future<ApiDynamicEditDraft?> editDraft(
    String id, {
    ApiRequestContext? context,
  }) async {
    _id(id);
    const endpoint = 'dynamic_edit_draft';
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
    if (!post.editable || post.authorId == null) return null;
    Map<String, Object?> map(Object? v) =>
        v is Map<String, Object?> ? v : const {};
    final modules = map(item['modules']),
        content = map(modules['module_dynamic']),
        major = map(content['major']),
        opus = map(major['opus']);
    final desc = map(content['desc']);
    final summary =
        (desc['rich_text_nodes'] is List<Object?> || desc['text'] is String)
        ? desc
        : map(opus['summary']);
    final rows = summary['rich_text_nodes'];
    final contents = <ApiDynamicContent>[];
    if (rows is List<Object?> && rows.isNotEmpty) {
      if (rows.length > 1000) return null;
      for (final row in rows) {
        final n = map(row);
        final text = n['orig_text'] ?? n['text'];
        if (text is! String) return null;
        final type = switch (n['type']) {
          'RICH_TEXT_NODE_TYPE_AT' => 2,
          'RICH_TEXT_NODE_TYPE_VOTE' => 4,
          'RICH_TEXT_NODE_TYPE_EMOJI' => 9,
          _ => 1,
        };
        final rid = n['rid'];
        final biz = rid is int
            ? '$rid'
            : rid is String
            ? rid
            : '';
        if ((type == 2 || type == 4) && !_validId(biz)) return null;
        contents.add(ApiDynamicContent(text, type, id: biz));
      }
    } else {
      contents.add(ApiDynamicContent(post.text, 1));
    }
    final pictures = <ApiDynamicPicture>[];
    if (contents.fold<int>(0, (length, c) => length + c.text.runes.length) >
            1000 ||
        post.title.runes.length > 20) {
      return null;
    }
    final imageRows = map(major['draw'])['items'] ?? opus['pics'];
    if (imageRows is List<Object?>) {
      if (imageRows.length > 18) return null;
      for (final row in imageRows) {
        final p = map(row);
        final raw = p['url'] ?? p['src'];
        final u = raw is String
            ? Uri.tryParse(raw.startsWith('//') ? 'https:$raw' : raw)
            : null;
        final w = p['width'], h = p['height'], s = p['size'];
        if (u == null ||
            u.scheme != 'https' ||
            u.hasQuery ||
            u.userInfo.isNotEmpty ||
            !(u.host.endsWith('.hdslb.com') ||
                u.host.endsWith('.biliimg.com')) ||
            w is! int ||
            h is! int ||
            w <= 0 ||
            h <= 0 ||
            w > 20000 ||
            h > 20000 ||
            w * h > 40000000) {
          return null;
        }
        pictures.add(
          ApiDynamicPicture(
            u,
            w,
            h,
            s is num && s.isFinite && s >= 0 ? s.toDouble() : 0,
          ),
        );
      }
    }
    final reserve = map(map(content['additional'])['reserve'])['rid'];
    final interactionSettings =
        post.commentOid == null || post.commentType == null
        ? null
        : await interaction(
            post.commentOid!,
            post.commentType!,
            context: context,
          );
    return ApiDynamicEditDraft(
      id: id,
      authorId: post.authorId!,
      title: post.title,
      contents: List.unmodifiable(contents),
      pictures: List.unmodifiable(pictures),
      topic: post.topic?.id == null
          ? null
          : ApiDynamicComposeTopic(post.topic!.id!, post.topic!.name),
      repostId: post.original?.id,
      reserveId: reserve is int
          ? '$reserve'
          : reserve is String
          ? reserve
          : null,
      onlySelf: post.onlySelf,
      replyPolicy: interactionSettings == null
          ? 0
          : !interactionSettings.comments
          ? 1
          : interactionSettings.selected
          ? 2
          : 0,
    );
  }

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

  Future<ApiDynamicReservationUpdate> reserve(
    String dynamicId,
    String reserveId,
    int status,
    int total, {
    ApiRequestContext? context,
  }) async {
    _id(dynamicId);
    _id(reserveId);
    if (status < 0 || total < 0) {
      throw ArgumentError('Invalid reservation state');
    }
    const endpoint = 'dynamic_reserve';
    final data = await api
        .submitDynamicJson('/x/dynamic/feed/reserve/click', endpoint, {
          'reserve_id': reserveId,
          'cur_btn_status': status,
          'dynamic_id_str': dynamicId,
          'reserve_total': total,
        }, context: context);
    if (data is! Map<String, Object?> ||
        data['final_btn_status'] is! int ||
        (data['final_btn_status'] as int) < 0 ||
        data['reserve_update'] is! int ||
        (data['reserve_update'] as int) < 0 ||
        data['desc_update'] is! String) {
      throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    return ApiDynamicReservationUpdate(
      data['final_btn_status'] as int,
      data['reserve_update'] as int,
      data['desc_update'] as String,
    );
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
