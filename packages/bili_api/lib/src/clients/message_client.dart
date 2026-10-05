import 'dart:convert';

import '../api_client.dart';
import '../models.dart';
import '../models/message_models.dart';

/// Web Cookie inbox. IDs, sequences and microsecond cursors stay decimal strings.
final class MessageClient {
  const MessageClient(this.api);
  final BiliApiClient api;
  static const _vc = 'api.vc.bilibili.com';

  Future<Map<String, Object?>> _get(
    String host,
    String path,
    String endpoint,
    Map<String, String> query,
    ApiRequestContext? context,
  ) =>
      api.requestJson(Uri.https(host, path, query), endpoint, context: context);

  Future<Map<ApiInboxSection, int>> unread({ApiRequestContext? context}) async {
    const e = 'message_unread';
    final data = await _get(
      'api.bilibili.com',
      '/x/msgfeed/unread',
      e,
      {},
      context,
    );
    return Map.unmodifiable({
      ApiInboxSection.private: _count(data['chat']),
      ApiInboxSection.replies: _count(data['reply']),
      ApiInboxSection.mentions: _count(data['at']),
      ApiInboxSection.likes: _count(data['like']),
      ApiInboxSection.system: _count(data['sys_msg']),
    });
  }

  Future<ApiPage<ApiInboxEntry>> sessions({
    String? cursor,
    ApiRequestContext? context,
  }) async {
    const e = 'message_sessions';
    if (cursor != null) _decimal(cursor, e);
    final data =
        await _get(_vc, '/session_svr/v1/session_svr/get_sessions', e, {
          'session_type': '1',
          'group_fold': '1',
          'unfollow_fold': '0',
          'sort_rule': '2',
          'build': '0',
          'mobi_app': 'web',
          if (cursor != null) 'end_ts': cursor,
        }, context);
    if (!data.containsKey('session_list')) _fail(e);
    final raw = _list(data['session_list'], e, nullable: true);
    final rows = raw.map((v) => _map(v, e)).toList();
    final mids =
        rows
            .where(
              (v) =>
                  v['session_type'] == 1 && _count(v['system_msg_type']) == 0,
            )
            .map((v) => _decimal(v['talker_id'], e))
            .toSet();
    final users = <String, Map<String, Object?>>{};
    if (mids.isNotEmpty) {
      final cards = await _get(
        'api.bilibili.com',
        '/x/polymer/pc-electron/v1/user/cards',
        'message_users',
        {'uids': mids.join(',')},
        context,
      );
      final values =
          cards['list'] is List<Object?>
              ? _list(cards['list'], 'message_users')
              : cards.values.toList();
      for (final value in values) {
        final user = _map(value, 'message_users');
        users[_decimal(user['mid'], 'message_users')] = user;
      }
    }
    final entries = rows
        .map((row) {
          final mid = _decimal(row['talker_id'], e);
          final type = _number(row['session_type'], e);
          final system = _count(row['system_msg_type']) != 0;
          final account = _optionalMap(row['account_info']);
          final user = users[mid] ?? account;
          final last = row['last_msg'];
          final message = last == null ? null : _message(_map(last, e), e);
          return ApiInboxEntry(
            id: '$type:$mid',
            userMid: mid,
            sessionType: type,
            system: system,
            title:
                _text(user['name']).isNotEmpty
                    ? _text(user['name'])
                    : _text(account['uname']).isNotEmpty
                    ? _text(account['uname'])
                    : _text(row['group_name']).isNotEmpty
                    ? _text(row['group_name'])
                    : '用户 $mid',
            text: message?.text ?? '暂无消息',
            avatarUrl: _uri(
              user['face'] ??
                  account['pic_url'] ??
                  account['pic'] ??
                  row['group_cover'],
            ),
            time: message?.time,
            unread: _count(row['unread_count']),
            lastSequence:
                row['max_seqno'] == null
                    ? message?.sequence
                    : _decimal(row['max_seqno'], e, zero: true),
          );
        })
        .toList(growable: false);
    final next =
        rows.isEmpty ? null : _decimal(rows.last['session_ts'], e, zero: true);
    return _page(entries, _yes(data['has_more']), next, cursor);
  }

  Future<ApiPage<ApiPrivateMessage>> thread(
    String mid,
    int type, {
    String? cursor,
    ApiRequestContext? context,
  }) async {
    const e = 'message_thread';
    _decimal(mid, e);
    if (type != 1 && type != 2) throw ArgumentError('Invalid session type');
    if (cursor != null) _decimal(cursor, e, zero: true);
    final data =
        await _get(_vc, '/svr_sync/v1/svr_sync/fetch_session_msgs', e, {
          'talker_id': mid,
          'session_type': '$type',
          'size': '30',
          'sender_device_id': '1',
          'build': '0',
          'mobi_app': 'web',
          if (cursor != null) 'end_seqno': cursor,
        }, context);
    if (!data.containsKey('messages')) _fail(e);
    final messages =
        _list(
          data['messages'],
          e,
          nullable: true,
        ).map((v) => _message(_map(v, e), e)).toList();
    messages.sort(
      (a, b) => BigInt.parse(a.sequence).compareTo(BigInt.parse(b.sequence)),
    );
    final next = messages.isEmpty ? null : messages.first.sequence;
    return _page(messages, _yes(data['has_more']), next, cursor);
  }

  Future<ApiPage<ApiInboxEntry>> notifications(
    ApiInboxSection section, {
    String? cursor,
    ApiRequestContext? context,
  }) async {
    if (section == ApiInboxSection.private) throw ArgumentError('Use sessions');
    final name = switch (section) {
      ApiInboxSection.replies => 'reply',
      ApiInboxSection.mentions => 'at',
      ApiInboxSection.likes => 'like',
      _ => 'system',
    };
    final e = 'message_$name';
    final query = <String, String>{
      'platform': 'web',
      'build': '0',
      'mobi_app': 'web',
    };
    if (section == ApiInboxSection.system) {
      query['page_size'] = '20';
      if (cursor != null) {
        throw ArgumentError('System notice pagination is unavailable');
      }
    } else if (cursor != null) {
      final parts = cursor.split(':');
      if (parts.length != 2) throw ArgumentError('Invalid notification cursor');
      query['id'] = _decimal(parts[0], e, zero: true);
      query['${name}_time'] = _decimal(parts[1], e, zero: true);
    }
    final data = await _get(
      section == ApiInboxSection.system
          ? 'message.bilibili.com'
          : 'api.bilibili.com',
      section == ApiInboxSection.system
          ? '/x/sys-msg/query_user_notify'
          : '/x/msgfeed/$name',
      e,
      query,
      context,
    );
    if (section == ApiInboxSection.system) {
      // The live Web endpoint returns an empty data object at the end.
      if (data.isEmpty) return const ApiPage([], hasMore: false);
      if (!data.containsKey('system_notify_list') &&
          !data.containsKey('list')) {
        _fail(e);
      }
      final entries =
          _list(
            data['system_notify_list'] ?? data['list'],
            e,
            nullable: true,
          ).map((value) {
            final row = _map(value, e);
            return ApiInboxEntry(
              id: _decimal(row['id'], e),
              title: _text(row['title']).isEmpty ? '系统通知' : _text(row['title']),
              text: _text(row['content']),
              time: _time(row['time_at']),
              targetUrl: _uri(row['link']),
              system: true,
            );
          }).toList();
      // This endpoint exposes no usable cursor in the verified Web response.
      return ApiPage(List.unmodifiable(entries), hasMore: false);
    }
    final total =
        section == ApiInboxSection.likes ? _map(data['total'], e) : data;
    final latest =
        section == ApiInboxSection.likes
            ? _optionalMap(data['latest'] ?? data['lastest'])
            : const <String, Object?>{};
    final raw = [
      if (cursor == null && latest.containsKey('items'))
        ..._list(latest['items'], e, nullable: true),
      ..._list(total['items'], e, nullable: true),
    ];
    final entries = <String, ApiInboxEntry>{};
    for (final value in raw) {
      final row = _map(value, e), item = _map(_map(value, e)['item'], e);
      final users = row['users'];
      final user =
          row['user'] is Map<String, Object?>
              ? _map(row['user'], e)
              : users is List<Object?> && users.isNotEmpty
              ? _map(users.first, e)
              : const <String, Object?>{};
      final mid = user['mid'] == null ? null : _decimal(user['mid'], e);
      final id = _decimal(row['id'], e);
      final actor = _text(user['nickname'] ?? user['name']);
      final verb = switch (section) {
        ApiInboxSection.replies => '回复了你',
        ApiInboxSection.mentions => '@了你',
        _ => '赞了你',
      };
      entries[id] = ApiInboxEntry(
        id: id,
        title:
            '${actor.isEmpty ? '用户' : actor}${_count(row['counts']) > 1 ? '等${_count(row['counts'])}人' : ''}$verb',
        text: [
          _text(item['source_content']),
          _text(item['title'] ?? item['desc']),
        ].where((v) => v.isNotEmpty).toSet().join('\n'),
        userMid: mid,
        avatarUrl: _uri(user['avatar'] ?? user['face']),
        time: _time(row['${name}_time']),
        targetUrl: _uri(item['uri']),
      );
    }
    final c = _map(total['cursor'], e);
    final next =
        '${_decimal(c['id'], e, zero: true)}:${_decimal(c['time'], e, zero: true)}';
    return _page(entries.values.toList(), !_yes(c['is_end']), next, cursor);
  }

  Future<void> sendText(
    String sender,
    String receiver,
    String text, {
    ApiRequestContext? context,
  }) async {
    const e = 'message_send';
    _decimal(sender, e);
    _decimal(receiver, e);
    if (text.trim().isEmpty || text.runes.length > 1000) {
      throw ArgumentError('Invalid message');
    }
    await api.submitMessageForm('/web_im/v1/web_im/send_msg', e, {
      'msg[sender_uid]': sender,
      'msg[receiver_id]': receiver,
      'msg[receiver_type]': '1',
      'msg[msg_type]': '1',
      'msg[msg_status]': '0',
      'msg[content]': jsonEncode({'content': text}),
      'msg[timestamp]': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'msg[dev_id]': '0',
      'msg[new_face_version]': '1',
      'from_firework': '0',
      'build': '0',
      'mobi_app': 'web',
    }, context: context);
  }

  Future<void> markRead(
    String mid,
    int type,
    String sequence, {
    ApiRequestContext? context,
  }) async {
    const e = 'message_mark_read';
    _decimal(mid, e);
    _decimal(sequence, e, zero: true);
    if (type != 1 && type != 2) throw ArgumentError('Invalid session type');
    await api.submitMessageForm('/session_svr/v1/session_svr/update_ack', e, {
      'talker_id': mid,
      'session_type': '$type',
      'ack_seqno': sequence,
      'build': '0',
      'mobi_app': 'web',
    }, context: context);
  }

  ApiPrivateMessage _message(Map<String, Object?> row, String e) {
    final type = _number(row['msg_type'], e);
    final sequence = _decimal(row['msg_seqno'], e, zero: true);
    final sender = _decimal(row['sender_uid'], e);
    final revoked =
        _count(row['msg_status']) == 1 ||
        _count(row['msg_status']) == 2 ||
        type == 5;
    // The server may still include recalled text: never decode or display it.
    var content = const <String, Object?>{};
    if (!revoked && row['content'] is String) {
      try {
        content = _map(jsonDecode(row['content'] as String), e);
      } on FormatException {
        _fail(e);
      }
    }
    if (!revoked && type == 1 && content['content'] is! String) _fail(e);
    final image = !revoked && type == 2 ? _uri(content['url']) : null;
    final text =
        revoked
            ? '消息已撤回'
            : type == 2
            ? '[图片]'
            : _text(content['content']).isNotEmpty
            ? _text(content['content'])
            : [
              _text(content['title']),
              _text(content['text']),
            ].where((s) => s.isNotEmpty).join('\n');
    return ApiPrivateMessage(
      // Some notification messages reuse msg_key=0; sequence is unique per thread.
      id: sequence,
      sequence: sequence,
      senderMid: sender,
      type: type,
      time: _time(row['timestamp']),
      text: text.isEmpty ? '暂不支持的消息类型（$type）' : text,
      imageUrl: image,
      targetUrl: revoked ? null : _uri(content['url'] ?? content['jump_uri']),
    );
  }

  ApiPage<T> _page<T>(
    List<T> items,
    bool more,
    String? next,
    String? previous,
  ) => ApiPage(
    List.unmodifiable(items),
    hasMore: more && items.isNotEmpty && next != null && next != previous,
    nextCursor: next,
  );
  Never _fail(String e) => throw ApiFailure(ApiFailureCategory.protocol, e);
  Map<String, Object?> _map(Object? v, String e) =>
      v is Map<String, Object?> ? v : _fail(e);
  Map<String, Object?> _optionalMap(Object? v) =>
      v is Map<String, Object?> ? v : const {};
  List<Object?> _list(Object? v, String e, {bool nullable = false}) =>
      v == null && nullable
          ? const []
          : v is List<Object?> && v.length <= 500
          ? v
          : _fail(e);
  String _decimal(Object? v, String e, {bool zero = false}) {
    if (v is! int && v is! String) _fail(e);
    final s = '$v';
    if (!RegExp(zero ? r'^[0-9]+$' : r'^[1-9][0-9]*$').hasMatch(s)) _fail(e);
    return s;
  }

  int _number(Object? v, String e) => v is int ? v : _fail(e);
  int _count(Object? v) => v is int && v >= 0 ? v : 0;
  bool _yes(Object? v) => v == 1 || v == true;
  String _text(Object? v) => v is String ? v : '';
  DateTime? _time(Object? v) {
    final n = v is int ? v : int.tryParse('$v');
    return n != null && n > 0 && n < 8640000000000
        ? DateTime.fromMillisecondsSinceEpoch(n * 1000)
        : v is String
        ? DateTime.tryParse(v)
        : null;
  }

  Uri? _uri(Object? v) {
    if (v is! String || v.isEmpty) return null;
    final uri = Uri.tryParse(v.startsWith('//') ? 'https:$v' : v);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        !{'http', 'https'}.contains(uri.scheme)) {
      return null;
    }
    return uri.replace(scheme: 'https');
  }
}
