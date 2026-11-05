import 'dart:convert';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

import 'message_client_test.dart' show Transport, response, cookies;

void main() {
  late Transport transport;
  late MessageCenterClient client;
  setUp(() {
    transport = Transport();
    client = MessageCenterClient(
      BiliApiClient(transport: transport, cookieJar: cookies()),
    );
  });
  test(
    'message settings preserve exact Web enum values and unknown keys are absent',
    () async {
      transport.handler = (_) => {
        'msg_notify': 3,
        'set_comment': 1,
        'set_at': 2,
        'set_like': 5,
        'receive_unfollow_msg': 0,
        'show_unfollowed_msg': 1,
        'ai_intercept': 1,
      };
      final result = await client.settings();
      expect(result.values[ApiMessageSetting.notification], 3);
      expect(result.values[ApiMessageSetting.like], 5);
      expect(result.values, hasLength(7));
      await client.setSetting(ApiMessageSetting.like, 0);
      expect(transport.fields['set_like'], '0');
      expect(transport.fields['csrf'], 'csrf-fixture');
      expect(transport.uri?.path, '/link_setting/v1/link_setting/set');
      await expectLater(
        client.setSetting(ApiMessageSetting.like, 1),
        throwsArgumentError,
      );
      expect(transport.posts, 1);
    },
  );
  test(
    'blocked word limits and add/delete content match Web contract',
    () async {
      transport.handler = (_) => {
        'words': [
          {'content': '屏蔽词'},
          {'content': '广告'},
        ],
        'max_words_size': 200,
        'max_word_length': 20,
      };
      final result = await client.blockedWords();
      expect(result.words, ['屏蔽词', '广告']);
      expect(result.limit, 200);
      expect(result.wordLength, 20);
      await client.addBlockedWord('中文 & + %');
      expect(transport.uri?.path, '/x/im/link_setting/add_block_word');
      expect(transport.fields['content'], '中文 & + %');
      await client.removeBlockedWord('中文 & + %');
      expect(transport.uri?.path, '/x/im/link_setting/del_block_word');
    },
  );
  test('chat settings separate push, block and DND semantics', () async {
    transport.handler = (uri) => uri.path == '/x/relation'
        ? {'attribute': 128}
        : {'show_push_setting': 1, 'push_setting': 0};
    final result = await client.chatSettings('123');
    expect(result.contentPush, isTrue);
    expect(result.showContentPush, isTrue);
    expect(result.blocked, isTrue);
    await client.setContentPush('123', false);
    expect(transport.fields['setting'], '1');
    expect(transport.uri?.path, '/link_setting/v1/link_setting/set_push_ss');
    await client.setBlocked('123', false);
    expect(transport.fields['act'], '6');
    await client.setBlocked('123', true);
    expect(transport.fields['act'], '5');
  });
  test(
    'report is one explicit form with escaped JSON and supported reason',
    () async {
      await client.reportConversation('9007199254740993123', 4, '广告骚扰');
      expect(transport.uri?.path, '/x/bplus/im/report/add');
      expect(transport.fields['accused_uid'], '9007199254740993123');
      expect(transport.fields['reason_type'], '4');
      expect(transport.fields['module'], '607');
      expect(jsonDecode(transport.fields['comment'] ?? ''), {
        'group_id': 0,
        'msg_key': '',
      });
      expect(jsonDecode(transport.fields['extra'] ?? ''), {'msg_keys': []});
      expect(transport.posts, 1);
      await expectLater(
        client.reportConversation('123', 0, ''),
        throwsArgumentError,
      );
      expect(transport.posts, 1);
    },
  );
  test(
    'people lists preserve large IDs, bounded pages and recent fan order',
    () async {
      transport.handler = (_) => {
        'total': 101,
        'list': [
          {'mid': '9007199254740993123', 'uname': '早', 'mtime': 10},
          {'mid': '456', 'uname': '新', 'mtime': 20},
        ],
      };
      final result = await client.people('123', ApiMessagePeopleKind.fans);
      expect(result.items.map((e) => e.name), ['新', '早']);
      expect(result.items.last.mid, '9007199254740993123');
      expect(result.hasMore, isTrue);
      expect(result.nextCursor, '2');
      expect(transport.uri?.path, '/x/relation/followers');
      await expectLater(
        client.people('123', ApiMessagePeopleKind.fans, cursor: '11'),
        throwsArgumentError,
      );
    },
  );
  test(
    'assistant discovery uses server session identities and groups',
    () async {
      transport.handler = (_) => {
        'has_more': 1,
        'session_list': [
          {
            'talker_id': '123',
            'session_type': 1,
            'session_ts': '12345',
            'system_msg_type': 0,
          },
          {
            'talker_id': '844424930131966',
            'session_type': 1,
            'session_ts': '12344',
            'account_info': {'uname': 'UP主助手'},
          },
        ],
      };
      final result = await client.assistantSessions(fanGroups: false);
      expect(result.items.single.system, isTrue);
      expect(result.items.single.userMid, '844424930131966');
      expect(result.items.single.sessionType, 1);
      expect(result.nextCursor, '12344');
      transport.handler = (_) => {
        'has_more': 0,
        'session_list': [
          {
            'talker_id': '456',
            'session_type': 2,
            'session_ts': '12343',
            'group_name': '测试应援团',
          },
        ],
      };
      final groups = await client.assistantSessions(fanGroups: true);
      expect(groups.items.single.sessionType, 2);
      expect(groups.items.single.title, '测试应援团');
      expect(transport.uri?.queryParameters['session_type'], '2');
    },
  );
  test(
    'settings writes never retry uncertain failures or leak host-only credentials',
    () async {
      transport.postResult = response(null, status: 503);
      await expectLater(
        client.setSetting(ApiMessageSetting.notification, 3),
        throwsA(isA<ApiFailure>()),
      );
      await expectLater(
        client.addBlockedWord('广告'),
        throwsA(isA<ApiFailure>()),
      );
      await expectLater(
        client.reportConversation('123', 4, '广告骚扰'),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.posts, 3);
      final scoped = MessageCenterClient(
        BiliApiClient(
          transport: transport,
          cookieJar: cookies(domain: 'api.bilibili.com'),
        ),
      );
      await expectLater(
        scoped.setContentPush('123', false),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.posts, 3);
    },
  );
}
