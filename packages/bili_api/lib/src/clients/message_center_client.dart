import 'dart:convert';

import '../api_client.dart';
import '../models.dart';
import '../models/message_center_models.dart';
import '../models/message_models.dart';

final class MessageCenterClient {
  const MessageCenterClient(this.api);
  final BiliApiClient api;
  static const _vc = 'api.vc.bilibili.com';

  Future<ApiMessageCenterSettings> settings({
    ApiRequestContext? context,
  }) async {
    const endpoint = 'message_center_settings';
    final data = await _get(
      _vc,
      '/link_setting/v1/link_setting/get',
      endpoint,
      {
        'msg_notify': '1',
        'show_unfollowed_msg': '1',
        'build': '0',
        'mobi_app': 'web',
      },
      context,
    );
    final values = <ApiMessageSetting, int>{};
    for (final setting in ApiMessageSetting.values) {
      final value = data[setting.field];
      if (value is int && setting.allowedValues.contains(value)) {
        values[setting] = value;
      }
    }
    if (values.isEmpty) _fail(endpoint);
    return ApiMessageCenterSettings(Map.unmodifiable(values));
  }

  Future<void> setSetting(
    ApiMessageSetting setting,
    int value, {
    ApiRequestContext? context,
  }) async {
    if (!setting.allowedValues.contains(value)) {
      throw ArgumentError('Invalid message setting');
    }
    await api.submitMessageForm(
      '/link_setting/v1/link_setting/set',
      'message_center_set_setting',
      {setting.field: '$value', 'build': '0', 'mobi_app': 'web'},
      context: context,
    );
  }

  Future<ApiMessageBlockedWords> blockedWords({
    ApiRequestContext? context,
  }) async {
    const endpoint = 'message_center_blocked_words';
    final data = await _get(
      _vc,
      '/x/im/link_setting/get_block_words',
      endpoint,
      {},
      context,
    );
    final words = _list(data['words'], endpoint);
    return ApiMessageBlockedWords(
      List.unmodifiable(
        {
          for (final raw in words)
            if (_map(raw, endpoint)['content'] case final String word
                when word.isNotEmpty && word.length <= 400)
              word,
        }.take(500),
      ),
      limit: _limit(data['max_words_size'], 200, 500),
      wordLength: _limit(data['max_word_length'], 20, 200),
    );
  }

  Future<void> addBlockedWord(String word, {ApiRequestContext? context}) =>
      _word(word, true, context);
  Future<void> removeBlockedWord(String word, {ApiRequestContext? context}) =>
      _word(word, false, context);
  Future<void> _word(String word, bool add, ApiRequestContext? context) async {
    if (word.trim().isEmpty || word.runes.length > 200) {
      throw ArgumentError('Invalid blocked word');
    }
    await api.submitMessageForm(
      '/x/im/link_setting/${add ? 'add' : 'del'}_block_word',
      'message_center_${add ? 'add' : 'remove'}_word',
      {'content': word},
      context: context,
    );
  }

  Future<ApiPage<ApiMessagePerson>> people(
    String ownMid,
    ApiMessagePeopleKind kind, {
    String? cursor,
    ApiRequestContext? context,
  }) async {
    _mid(ownMid);
    final page = int.tryParse(cursor ?? '1');
    if (page == null || page < 1 || page > 10) {
      throw ArgumentError('Invalid people cursor');
    }
    final segment = switch (kind) {
      ApiMessagePeopleKind.fans => 'followers',
      ApiMessagePeopleKind.contacts => 'followings',
      ApiMessagePeopleKind.blocked => 'blacks',
    };
    final endpoint = 'message_center_$segment';
    final data =
        await _get('api.bilibili.com', '/x/relation/$segment', endpoint, {
          if (kind != ApiMessagePeopleKind.blocked) 'vmid': ownMid,
          'pn': '$page',
          'ps': '50',
          'order': 'desc',
        }, context);
    final rows = _list(data['list'], endpoint).toList();
    if (kind == ApiMessagePeopleKind.fans) {
      rows.sort(
        (a, b) => _mtime(
          _map(b, endpoint)['mtime'],
        ).compareTo(_mtime(_map(a, endpoint)['mtime'])),
      );
    }
    final total = data['total'];
    final more =
        rows.isNotEmpty &&
        page < 10 &&
        (total is int ? page * 50 < total : rows.length == 50);
    return ApiPage(
      List.unmodifiable(
        rows.map((raw) {
          final row = _map(raw, endpoint);
          final mid = '${row['mid']}';
          _mid(mid);
          return ApiMessagePerson(
            mid: mid,
            name: _text(row['uname']),
            sign: _text(row['sign']),
            avatarUrl: _image(row['face']),
          );
        }),
      ),
      hasMore: more,
      nextCursor: more ? '${page + 1}' : null,
    );
  }

  Future<ApiChatMessageSettings> chatSettings(
    String mid, {
    ApiRequestContext? context,
  }) async {
    _mid(mid);
    const endpoint = 'message_center_chat_settings';
    final data = await _get(
      _vc,
      '/link_setting/v1/link_setting/get_session_ss',
      endpoint,
      {'talker_uid': mid, 'build': '0', 'mobi_app': 'web'},
      context,
    );
    final relation = await _get(
      'api.bilibili.com',
      '/x/relation',
      'message_center_chat_relation',
      {'fid': mid},
      context,
    );
    final attribute = relation['attribute'];
    if (attribute is! int) _fail(endpoint);
    final show = data['show_push_setting'] == 1;
    if (show && data['push_setting'] != 0 && data['push_setting'] != 1) {
      _fail(endpoint);
    }
    return ApiChatMessageSettings(
      contentPush: data['push_setting'] == 0,
      showContentPush: show,
      blocked: (attribute & 128) != 0,
    );
  }

  Future<ApiPage<ApiInboxEntry>> assistantSessions({
    required bool fanGroups,
    String? cursor,
    ApiRequestContext? context,
  }) async {
    const endpoint = 'message_center_assistants';
    if (cursor != null && !RegExp(r'^[0-9]+$').hasMatch(cursor)) {
      throw ArgumentError('Invalid session cursor');
    }
    final data =
        await _get(_vc, '/session_svr/v1/session_svr/get_sessions', endpoint, {
          'session_type': fanGroups ? '2' : '1',
          'group_fold': '0',
          'unfollow_fold': '0',
          'sort_rule': '2',
          'size': '20',
          'build': '0',
          'mobi_app': 'web',
          'end_ts': ?cursor,
        }, context);
    final rows = _list(
      data['session_list'],
      endpoint,
    ).map((v) => _map(v, endpoint)).toList();
    final entries = <ApiInboxEntry>[];
    for (final row in rows) {
      final mid = '${row['talker_id']}';
      _mid(mid);
      final account = row['account_info'] is Map<String, Object?>
          ? row['account_info'] as Map<String, Object?>
          : const <String, Object?>{};
      final title = _text(
        account['name'] ?? account['uname'] ?? row['group_name'],
      );
      if (!fanGroups &&
          row['system_msg_type'] != 1 &&
          row['system_msg_type'] != 2 &&
          row['system_msg_type'] != 7 &&
          !{'844424930131966', '844424930131964'}.contains(mid) &&
          !title.contains('助手')) {
        continue;
      }
      final type = row['session_type'];
      if (type != (fanGroups ? 2 : 1)) continue;
      entries.add(
        ApiInboxEntry(
          id: '$type:$mid',
          title: title.isEmpty
              ? fanGroups
                    ? '粉丝团 $mid'
                    : '系统助手'
              : title,
          text: fanGroups ? '粉丝团会话' : '系统助手会话',
          userMid: mid,
          avatarUrl: _image(
            account['face'] ??
                account['pic_url'] ??
                account['pic'] ??
                row['group_cover'],
          ),
          sessionType: type as int,
          system: true,
          unread: row['unread_count'] is int
              ? (row['unread_count'] as int).clamp(0, 2147483647)
              : 0,
        ),
      );
    }
    final last = rows.lastOrNull?['session_ts'];
    final next = last is String || last is int ? '$last' : null;
    final valid =
        next != null && RegExp(r'^[0-9]+$').hasMatch(next) && next != cursor;
    return ApiPage(
      List.unmodifiable(entries),
      hasMore: data['has_more'] == 1 && valid,
      nextCursor: valid ? next : null,
    );
  }

  Future<void> setContentPush(
    String mid,
    bool enabled, {
    ApiRequestContext? context,
  }) async {
    _mid(mid);
    await api.submitMessageForm(
      '/link_setting/v1/link_setting/set_push_ss',
      'message_center_set_push',
      {
        'talker_uid': mid,
        'setting': enabled ? '0' : '1',
        'build': '0',
        'mobi_app': 'web',
      },
      context: context,
    );
  }

  Future<void> setBlocked(
    String mid,
    bool blocked, {
    ApiRequestContext? context,
  }) async {
    _mid(mid);
    await api.submitForm('/x/relation/modify', 'message_center_set_blocked', {
      'fid': mid,
      'act': blocked ? '5' : '6',
      're_src': '118',
    }, context: context);
  }

  Future<void> reportConversation(
    String mid,
    int reason,
    String text, {
    ApiRequestContext? context,
  }) async {
    _mid(mid);
    if (reason < 0 ||
        reason > 6 ||
        text.trim().isEmpty ||
        text.runes.length > 160) {
      throw ArgumentError('Invalid report');
    }
    await api.submitMessageForm(
      '/x/bplus/im/report/add',
      'message_center_report',
      {
        'biz_code': '4',
        'accused_uid': mid,
        'object_id': mid,
        'reason_type': '$reason',
        'reason_desc': text,
        'module': '607',
        'comment': jsonEncode({'group_id': 0, 'msg_key': ''}),
        'extra': jsonEncode({'msg_keys': <String>[]}),
      },
      context: context,
    );
  }

  Future<Map<String, Object?>> _get(
    String host,
    String path,
    String endpoint,
    Map<String, String> query,
    ApiRequestContext? context,
  ) =>
      api.requestJson(Uri.https(host, path, query), endpoint, context: context);
  Never _fail(String endpoint) =>
      throw ApiFailure(ApiFailureCategory.protocol, endpoint);
  Map<String, Object?> _map(Object? value, String endpoint) =>
      value is Map<String, Object?> ? value : _fail(endpoint);
  List<Object?> _list(Object? value, String endpoint) => value == null
      ? const []
      : value is List<Object?> && value.length <= 500
      ? value
      : _fail(endpoint);
  String _text(Object? value) => value is String
      ? value.length > 4000
            ? value.substring(0, 4000)
            : value
      : '';
  int _limit(Object? value, int fallback, int cap) =>
      value is int && value > 0 ? value.clamp(1, cap) : fallback;
  int _mtime(Object? value) => value is int ? value : 0;
  void _mid(String value) {
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(value)) {
      throw ArgumentError('Invalid user ID');
    }
  }

  Uri? _image(Object? value) {
    if (value is! String || value.length > 8192) return null;
    final uri = Uri.tryParse(value.startsWith('//') ? 'https:$value' : value);
    return uri != null &&
            {'https', 'http'}.contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty
        ? uri.replace(scheme: 'https')
        : null;
  }
}
