import 'dart:convert';

import '../api_client.dart';
import '../models.dart';
import '../models/message_models.dart';
import '../video_identifiers.dart';

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
          'end_ts': ?cursor,
        }, context);
    if (!data.containsKey('session_list')) _fail(e);
    final raw = _list(data['session_list'], e, nullable: true);
    final rows = raw.map((v) => _map(v, e)).toList();
    final mids = rows
        .where(
          (v) => v['session_type'] == 1 && _count(v['system_msg_type']) == 0,
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
      final values = cards['list'] is List<Object?>
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
            title: _text(user['name']).isNotEmpty
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
            pinned:
                _yes(row['is_top']) || _positiveDecimal(row['top_ts']) != null,
            muted: _yes(row['is_dnd']),
            lastSequence: row['max_seqno'] == null
                ? message?.sequence
                : _decimal(row['max_seqno'], e, zero: true),
          );
        })
        .toList(growable: false);
    final next = rows.isEmpty
        ? null
        : _decimal(rows.last['session_ts'], e, zero: true);
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
          'end_seqno': ?cursor,
        }, context);
    if (!data.containsKey('messages')) _fail(e);
    final emotes = _emotes(data);
    final messages = _list(
      data['messages'],
      e,
      nullable: true,
    ).map((v) => _message(_map(v, e), e, emotes: emotes)).toList();
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
              text: _systemText(row['content']),
              time: _time(row['time_at']),
              targetUrl:
                  _targetUri(row['link']) ?? _markupTarget(row['content']),
              system: true,
              readCursor: row['cursor'] == null
                  ? null
                  : _decimal(row['cursor'], e),
            );
          }).toList();
      // This endpoint exposes no usable cursor in the verified Web response.
      return ApiPage(List.unmodifiable(entries), hasMore: false);
    }
    final total = section == ApiInboxSection.likes
        ? _map(data['total'], e)
        : data;
    final latest = section == ApiInboxSection.likes
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
      final user = row['user'] is Map<String, Object?>
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
        text: _firstText([
          item['source_content'],
          item['title'],
          item['desc'],
          item['business'],
        ]),
        sourceText: _firstText([
          item['target_reply_content'],
          item['root_reply_content'],
          item['desc'],
        ]),
        sourceTitle: _firstText([item['title'], item['business']]),
        emotes: _matchingEmotes(
          _joinText([
            item['source_content'],
            item['target_reply_content'],
            item['root_reply_content'],
          ]),
          {..._emotes(data), ..._emotes(row), ..._emotes(item)},
        ),
        replyContext:
            section == ApiInboxSection.replies ||
                section == ApiInboxSection.mentions
            ? _replyContext(item, actor, mid)
            : null,
        sourceImageUrl: _uri(
          item['image'] ?? item['cover'] ?? item['cover_url'],
        ),
        userMid: mid,
        avatarUrl: _uri(user['avatar'] ?? user['face']),
        time: _time(row['${name}_time']),
        targetUrl: _targetUri(item['uri'] ?? item['native_uri']),
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

  Future<List<ApiMessageEmotePackage>> emotes({
    ApiRequestContext? context,
  }) async {
    final data = await _get(
      'api.bilibili.com',
      '/x/emote/user/panel/web',
      'message_emotes',
      {'business': 'im'},
      context,
    );
    final packages = data['packages'];
    if (packages is! List<Object?>) _fail('message_emotes');
    return List.unmodifiable(
      packages.take(50).map((value) {
        final package = _optionalMap(value);
        final items = package['emote'];
        return ApiMessageEmotePackage(
          _firstText([package['text'], '表情']),
          List.unmodifiable([
            if (items is List<Object?>)
              for (final value in items.take(200))
                if (_optionalMap(value) case final item
                    when _text(item['text']).isNotEmpty &&
                        _text(item['text']).length <= 100)
                  ApiMessageEmote(
                    _text(item['text']),
                    item['type'] == 4
                        ? null
                        : _uri(item['gif_url']) ?? _uri(item['url']),
                  ),
          ]),
        );
      }),
    );
  }

  Future<void> sendImage(
    String sender,
    String receiver,
    ApiCommentPicture picture, {
    required String mimeType,
    ApiRequestContext? context,
  }) async {
    const endpoint = 'message_send_image';
    _decimal(sender, endpoint);
    _decimal(receiver, endpoint);
    if (picture.width <= 0 ||
        picture.height <= 0 ||
        !picture.sizeKiB.isFinite ||
        picture.sizeKiB <= 0 ||
        picture.sizeKiB > 10240 ||
        _uri(picture.url.toString()) == null ||
        !{'image/jpeg', 'image/png', 'image/gif'}.contains(mimeType)) {
      throw ArgumentError('Invalid message picture');
    }
    await api.submitMessageForm('/web_im/v1/web_im/send_msg', endpoint, {
      'msg[sender_uid]': sender,
      'msg[receiver_id]': receiver,
      'msg[receiver_type]': '1',
      'msg[msg_type]': '2',
      'msg[msg_status]': '0',
      'msg[content]': jsonEncode({
        'url': picture.url.toString(),
        'height': picture.height,
        'width': picture.width,
        'imageType': mimeType.substring('image/'.length) == 'jpeg'
            ? 'jpg'
            : mimeType.substring('image/'.length),
        'original': 1,
        'size': picture.sizeKiB,
      }),
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

  Future<void> markSystemNotificationsRead(
    String cursor, {
    ApiRequestContext? context,
  }) {
    const endpoint = 'message_system_mark_read';
    _decimal(cursor, endpoint);
    return api.acknowledgeSystemNotifications(cursor, context: context);
  }

  ApiPrivateMessage _message(
    Map<String, Object?> row,
    String e, {
    Map<String, Uri> emotes = const {},
  }) {
    final type = _number(row['msg_type'], e);
    final sequence = _decimal(row['msg_seqno'], e, zero: true);
    final sender = _decimal(row['sender_uid'], e);
    final revoked =
        _count(row['msg_status']) == 1 ||
        _count(row['msg_status']) == 2 ||
        type == 5 ||
        type == 8;
    // The server may still include recalled text: never decode or display it.
    final content = revoked
        ? const <String, Object?>{}
        : _payload(row['content']);
    final kind = revoked
        ? ApiMessageContentKind.withdrawn
        : switch (type) {
            1 => ApiMessageContentKind.text,
            2 || 6 => ApiMessageContentKind.image,
            3 => ApiMessageContentKind.voice,
            4 || 7 => ApiMessageContentKind.share,
            9 => ApiMessageContentKind.miniProgram,
            10 => ApiMessageContentKind.notification,
            11 => ApiMessageContentKind.video,
            12 => ApiMessageContentKind.article,
            13 => ApiMessageContentKind.pictureCard,
            14 => ApiMessageContentKind.commonCard,
            16 => ApiMessageContentKind.autoReply,
            18 => ApiMessageContentKind.notice,
            _ => ApiMessageContentKind.unsupported,
          };
    final title = _firstText([
      content['title'],
      content['main_title'],
      content['name'],
    ]);
    final subtitle = _firstText([
      content['author'],
      content['source'],
      content['subtitle'],
    ]);
    final details = <ApiMessageDetail>[
      for (final value in _contentList(content['modules']))
        if (_optionalMap(value) case final module when module.isNotEmpty)
          ApiMessageDetail(
            label: _text(module['title']),
            value: _text(module['detail']),
          ),
    ];
    final cards = <ApiMessageCard>[
      for (final value in _contentList(content['sub_cards']))
        if (_optionalMap(value) case final card when card.isNotEmpty)
          ApiMessageCard(
            title: _firstText([card['field1'], card['title']]),
            description: _joinText([
              card['field2'],
              card['field3'],
              card['desc'],
            ]),
            imageUrl: _uri(card['cover_url'] ?? card['cover']),
            targetUrl: _targetUri(card['jump_url']),
          ),
    ];
    final image = switch (kind) {
      ApiMessageContentKind.image => _uri(content['url'] ?? content['pic_url']),
      ApiMessageContentKind.pictureCard => _uri(
        content['pic_url'] ?? content['url'],
      ),
      ApiMessageContentKind.video ||
      ApiMessageContentKind.commonCard => _uri(content['cover']),
      ApiMessageContentKind.share => _uri(content['thumb'] ?? content['cover']),
      ApiMessageContentKind.article => _firstImage(content['image_urls']),
      _ => null,
    };
    final target = revoked ? null : _messageTarget(content, type);
    final links = <ApiMessageLink>[
      for (final suffix in ['', '_2', '_3'])
        if (_targetUri(content['jump_uri$suffix']) case final url?)
          ApiMessageLink(
            label: _firstText([content['jump_text$suffix'], '查看详情']),
            url: url,
          ),
    ];
    final duration = _duration(
      content['duration'] ?? content['times'] ?? content['length'],
    );
    final attached = _payload(content['attach_msg']);
    final text = revoked
        ? '消息已撤回'
        : switch (kind) {
            ApiMessageContentKind.image => type == 6 ? '[表情]' : '[图片]',
            ApiMessageContentKind.voice =>
              duration == null ? '[语音消息]' : '[语音消息 · $duration 秒]',
            ApiMessageContentKind.notice => _noticeText(content['content']),
            ApiMessageContentKind.text => _text(content['content']),
            ApiMessageContentKind.notification => _systemText(content['text']),
            _ => _joinText([
              content['text'],
              content['summary'],
              content['description'],
              content['desc'],
              attached['content'],
            ]),
          };
    if (!revoked && kind == ApiMessageContentKind.notification) {
      final url = _markupTarget(content['text']);
      if (url != null && !links.any((link) => link.url == url)) {
        links.add(ApiMessageLink(label: '查看详情', url: url));
      }
    }
    if (!revoked && kind == ApiMessageContentKind.text) {
      for (final match in RegExp(
        r'https?://[^\s<>\x00-\x1f]+',
      ).allMatches(text).take(10)) {
        final value = match
            .group(0)
            ?.replaceFirst(RegExp(r'[,.;!?)，。！？）]+$'), '');
        final url = _targetUri(value);
        if (url != null && !links.any((link) => link.url == url)) {
          links.add(ApiMessageLink(label: '打开链接', url: url));
        }
      }
    }
    final missing =
        content.isEmpty || (kind == ApiMessageContentKind.text && text.isEmpty);
    return ApiPrivateMessage(
      // Some notification messages reuse msg_key=0; sequence is unique per thread.
      id: sequence,
      sequence: sequence,
      senderMid: sender,
      type: type,
      time: _time(row['timestamp']),
      text: revoked
          ? text
          : missing
          ? '消息内容暂时无法解析（类型 $type）'
          : text.isNotEmpty
          ? text
          : title.isNotEmpty
          ? title
          : switch (kind) {
              ApiMessageContentKind.notification => '[业务通知]',
              ApiMessageContentKind.share => '[分享消息]',
              ApiMessageContentKind.miniProgram => '[小程序消息]',
              _ => '暂不支持的消息类型（$type）',
            },
      imageUrl: image,
      targetUrl: target,
      kind: missing && !revoked ? ApiMessageContentKind.unsupported : kind,
      title: title,
      subtitle: subtitle,
      cards: List.unmodifiable(cards),
      details: List.unmodifiable(details),
      links: List.unmodifiable(links),
      durationSeconds: duration,
      imageAspectRatio: _aspectRatio(content['width'], content['height']),
      emotes: revoked
          ? const {}
          : _matchingEmotes(
              _joinText([
                text,
                title,
                subtitle,
                for (final card in cards) '${card.title}\n${card.description}',
              ]),
              {...emotes, ..._emotes(row), ..._emotes(content)},
            ),
    );
  }

  ApiMessageReplyContext? _replyContext(
    Map<String, Object?> item,
    String author,
    String? userMid,
  ) {
    // The official message center uses source_id, with root_id || source_id.
    // target_id is the older target; the notification row ID is unrelated.
    if (_yes(item['hide_reply_button']) ||
        item['business'] == '弹幕' ||
        item['danmu'] is Map<String, Object?>) {
      return null;
    }
    final subject = _positiveDecimal(item['subject_id']);
    final parent = _positiveDecimal(item['source_id']);
    final business = item['business_id'];
    if (subject == null ||
        parent == null ||
        business is! int ||
        !{1, 11, 12, 14, 17, 33}.contains(business)) {
      return null;
    }
    final root = item['root_id'];
    if (root != null &&
        root != 0 &&
        root != '0' &&
        _positiveDecimal(root) == null) {
      return null;
    }
    return ApiMessageReplyContext(
      subjectId: subject,
      businessId: business,
      parentId: parent,
      rootId: _positiveDecimal(item['root_id']) ?? parent,
      author: author,
      userMid: userMid,
    );
  }

  Map<String, Uri> _matchingEmotes(String text, Map<String, Uri> emotes) =>
      Map.unmodifiable({
        for (final entry in emotes.entries.take(100))
          if (text.contains(entry.key)) entry.key: entry.value,
      });

  Map<String, Uri> _emotes(Object? value) {
    final result = <String, Uri>{};
    void visit(Object? raw, int depth, {String? token}) {
      if (depth > 4 || result.length >= 100) return;
      if (raw is String) {
        if (token != null) {
          final url = _uri(raw);
          if (url != null && token.isNotEmpty && token.length <= 100) {
            result[token] = url;
          }
        } else {
          if (raw.length <= 131072) {
            try {
              visit(jsonDecode(raw), depth + 1);
            } on FormatException {
              // Optional emoji metadata must not break the surrounding message.
            }
          }
        }
        return;
      }
      if (raw is List<Object?>) {
        for (final child in raw.take(100)) {
          visit(child, depth + 1);
        }
      } else if (raw is Map<String, Object?>) {
        final text = _firstText([raw['text'], raw['emoji'], token]);
        final url =
            _uri(raw['gif_url']) ?? _uri(raw['url']) ?? _uri(raw['uri']);
        if (text.isNotEmpty && text.length <= 100 && url != null) {
          result[text] = url;
        }
        for (final child in raw.entries.take(100)) {
          if (child.key.startsWith('[') && child.key.endsWith(']')) {
            visit(child.value, depth + 1, token: child.key);
          }
        }
        for (final key in ['e_infos', 'emoticon', 'emote', 'emojis', 'extra']) {
          final nested = raw[key];
          if (nested is Map<String, Object?>) {
            visit(nested, depth + 1);
            for (final child in nested.entries.take(100)) {
              if (child.key.startsWith('[') ||
                  child.value is Map<String, Object?>) {
                visit(child.value, depth + 1, token: child.key);
              }
            }
          } else if (nested != null) {
            visit(nested, depth + 1);
          }
        }
      }
    }

    visit(value, 0);
    return result;
  }

  // Payload failure is local to one message. Identity/sequence validation above
  // remains strict so broken content never changes deduplication or read ACKs.
  Map<String, Object?> _payload(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is! String || value.length > 131072) return const {};
    try {
      return _optionalMap(jsonDecode(value));
    } on FormatException {
      return const {};
    }
  }

  List<Object?> _contentList(Object? value) => value is List<Object?>
      ? value.take(20).toList(growable: false)
      : const [];

  String _firstText(List<Object?> values) {
    for (final value in values) {
      final text = _text(value);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  String _joinText(List<Object?> values) =>
      values.map(_text).where((text) => text.isNotEmpty).toSet().join('\n');

  String _noticeText(Object? value) {
    if (value is String && value.length <= 131072) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List<Object?>) value = decoded;
      } on FormatException {
        return _text(value);
      }
    }
    return value is List<Object?>
        ? _joinText(
            _contentList(
              value,
            ).map((part) => _optionalMap(part)['text']).toList(),
          )
        : _text(value);
  }

  Uri? _firstImage(Object? value) {
    for (final image in _contentList(value)) {
      if (_uri(image) case final url?) return url;
    }
    return null;
  }

  String? _positiveDecimal(Object? value) {
    if (value is! String && value is! int) return null;
    final text = '$value';
    return text.length <= 40 && RegExp(r'^[1-9][0-9]*$').hasMatch(text)
        ? text
        : null;
  }

  int? _duration(Object? value) {
    final number = value is int
        ? value
        : value is String
        ? int.tryParse(value)
        : null;
    return number != null && number >= 0 && number <= 86400 ? number : null;
  }

  double? _aspectRatio(Object? width, Object? height) {
    if (width is! num || height is! num || width <= 0 || height <= 0) {
      return null;
    }
    final ratio = width / height;
    return ratio.isFinite && ratio > 0 ? ratio.clamp(0.1, 10.0) : null;
  }

  Uri? _messageTarget(Map<String, Object?> content, int type) {
    if (type == 2 || type == 6 || type == 3) return null;
    final direct = _targetUri(
      content['jump_url'] ?? content['jump_uri'] ?? content['uri'],
    );
    if (direct != null) return direct;
    final bvid = _text(content['bvid']);
    if (RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(bvid)) {
      return Uri.https('www.bilibili.com', '/video/$bvid');
    }
    final id = _positiveDecimal(
      content['id'] ?? content['rid'] ?? content['sourceID'] ?? content['aid'],
    );
    if (id != null) {
      if (type == 11) return _videoTarget(id);
      if (type == 12) return Uri.https('www.bilibili.com', '/read/cv$id');
      if (type == 14 && content['source'] == '直播') {
        return Uri.https('live.bilibili.com', '/$id');
      }
      final source = content['source'];
      switch (source is String ? int.tryParse(source) : source) {
        case 2 || 11:
          return Uri.https('t.bilibili.com', '/$id');
        case 5:
          return _videoTarget(id);
        case 6:
          return Uri.https('www.bilibili.com', '/read/cv$id');
        case 16:
          return Uri.https('www.bilibili.com', '/bangumi/play/ep$id');
      }
    }
    return _targetUri(content['url']);
  }

  Uri? _targetUri(Object? value) {
    if (value is! String || value.length > 8192) return null;
    final parsed = Uri.tryParse(value);
    if (parsed?.scheme == 'bilibili' && parsed != null) {
      final id = parsed.pathSegments.isEmpty ? null : parsed.pathSegments.last;
      if (parsed.host == 'video' &&
          id != null &&
          RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(id)) {
        return Uri.https('www.bilibili.com', '/video/$id');
      }
      final decimal = id?.startsWith('av') == true ? id?.substring(2) : id;
      if (decimal != null && _positiveDecimal(decimal) != null) {
        return switch (parsed.host) {
          'video' => _videoTarget(decimal),
          'article' => Uri.https('www.bilibili.com', '/read/cv$decimal'),
          'dynamic' => Uri.https('t.bilibili.com', '/$decimal'),
          'live' => Uri.https('live.bilibili.com', '/$decimal'),
          _ => null,
        };
      }
      return null;
    }
    final uri = _uri(value);
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    return host == 'bilibili.com' ||
            host.endsWith('.bilibili.com') ||
            host == 'b23.tv'
        ? uri
        : null;
  }

  Uri _videoTarget(String aid) => Uri.https(
    'www.bilibili.com',
    '/video/${VideoIdentifiers.bvidFromAid(aid) ?? 'av$aid'}',
  );

  String _systemText(Object? value) => _text(value)
      .replaceAll(
        RegExp(
          r'<(?:script|style)\b[^>]*>.*?</(?:script|style)>',
          caseSensitive: false,
          dotAll: true,
        ),
        '',
      )
      .replaceAll(
        RegExp(r'<br\s*/?>|</p\s*>|</div\s*>', caseSensitive: false),
        '\n',
      )
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();

  Uri? _markupTarget(Object? value) {
    final text = _text(value);
    final pattern = RegExp(
      "href\\s*=\\s*[\"']([^\"']+)[\"']",
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(text).take(20)) {
      final url = _targetUri(match.group(1)?.replaceAll('&amp;', '&'));
      if (url != null) return url;
    }
    return null;
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
  String _text(Object? v) {
    if (v is! String) return '';
    if (v.length <= 16000) return v;
    // Do not split a surrogate pair when capping server-provided display text.
    final last = v.codeUnitAt(15999);
    return v.substring(0, last >= 0xd800 && last <= 0xdbff ? 15999 : 16000);
  }

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
