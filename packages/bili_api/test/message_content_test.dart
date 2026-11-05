import 'dart:convert';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

import 'message_client_test.dart' show Transport, cookies, message;

void main() {
  late Transport transport;
  late MessageClient client;
  setUp(() {
    transport = Transport();
    client = MessageClient(
      BiliApiClient(transport: transport, cookieJar: cookies()),
    );
  });

  Future<ApiPrivateMessage> parse(int type, Object? content) async {
    transport.handler = (_) => {
      'messages': [message(type: type, content: jsonEncode(content))],
      'has_more': 0,
    };
    return (await client.thread('123', 1)).items.single;
  }

  test(
    'image and custom face preserve dimensions without using image as target',
    () async {
      for (final type in [2, 6]) {
        final item = await parse(type, {
          'url': '//i0.hdslb.com/example.png',
          'width': 320,
          'height': 160,
        });
        expect(item.kind, ApiMessageContentKind.image);
        expect(item.imageUrl?.scheme, 'https');
        expect(item.imageAspectRatio, 2);
        expect(item.targetUrl, isNull);
      }
      final zero = await parse(2, {
        'url': 'https://i0.hdslb.com/example.png',
        'width': 0,
        'height': 0,
      });
      expect(zero.imageAspectRatio, isNull);
    },
  );

  test(
    'share source gives precise typed targets and keeps thumbnail separate',
    () async {
      for (final (source, expected) in [
        (2, 'https://t.bilibili.com/9007199254740993123'),
        (5, 'https://www.bilibili.com/video/av9007199254740993123'),
        (6, 'https://www.bilibili.com/read/cv9007199254740993123'),
        (11, 'https://t.bilibili.com/9007199254740993123'),
        (16, 'https://www.bilibili.com/bangumi/play/ep9007199254740993123'),
      ]) {
        final item = await parse(7, {
          'source': source,
          'id': '9007199254740993123',
          'title': '分享',
          'thumb': '//i0.hdslb.com/cover.jpg',
        });
        expect(item.kind, ApiMessageContentKind.share);
        expect(item.title, '分享');
        expect(item.targetUrl.toString(), expected);
        expect(item.imageUrl?.host, 'i0.hdslb.com');
      }
      final oldShare = await parse(4, {
        'title': '旧分享',
        'url': 'https://www.bilibili.com/video/BV1234567890',
      });
      expect(oldShare.targetUrl?.path, '/video/BV1234567890');
    },
  );

  test(
    'video shares and native targets convert supported AIDs to internal BV links',
    () async {
      final item = await parse(7, {
        'source': 5,
        'id': '170001',
        'title': '视频分享',
      });
      expect(item.targetUrl?.path, '/video/BV17x411w7KC');
      final archive = await parse(11, {'aid': '170001', 'title': '投稿卡片'});
      expect(archive.targetUrl?.path, '/video/BV17x411w7KC');
      for (final url in [
        'bilibili://video/170001',
        'bilibili://video/av170001',
        'bilibili://video/BV17x411w7KC',
      ]) {
        final native = await parse(7, {'title': '分享', 'jump_url': url});
        expect(native.targetUrl?.path, '/video/BV17x411w7KC');
      }
    },
  );

  test(
    'business notification carries details and up to three safe links',
    () async {
      final item = await parse(10, {
        'title': '业务通知',
        'text': '说明',
        'modules': [
          {'title': '状态', 'detail': '已处理'},
          null,
          {'title': 42, 'detail': '补充'},
        ],
        'jump_uri': 'https://www.bilibili.com/account/',
        'jump_text': '查看结果',
        'jump_uri_2': 'javascript:alert(1)',
        'jump_uri_3': '//message.bilibili.com/',
      });
      expect(item.kind, ApiMessageContentKind.notification);
      expect(item.text, '说明');
      expect(item.details.first.label, '状态');
      expect(item.details.first.value, '已处理');
      expect(item.links.map((e) => e.label), ['查看结果', '查看详情']);
      expect(() => item.links.add(item.links.first), throwsUnsupportedError);
    },
  );

  test('video cards include attached text, cover and BV target', () async {
    final item = await parse(11, {
      'title': '投稿',
      'cover': '//i0.hdslb.com/video.jpg',
      'bvid': 'BV1234567890',
      'times': 124,
      'attach_msg': {'content': '附言'},
    });
    expect(item.kind, ApiMessageContentKind.video);
    expect(item.title, '投稿');
    expect(item.text, '附言');
    expect(item.durationSeconds, 124);
    expect(item.targetUrl?.path, '/video/BV1234567890');
    expect(item.imageUrl?.path, '/video.jpg');
  });

  test(
    'article and live cards keep summary, author and navigable content identity',
    () async {
      final article = await parse(12, {
        'rid': '88',
        'title': '专栏标题',
        'summary': '专栏摘要',
        'image_urls': ['bad', '//i0.hdslb.com/article.jpg'],
      });
      expect(article.kind, ApiMessageContentKind.article);
      expect(article.targetUrl?.path, '/read/cv88');
      expect(article.text, '专栏摘要');
      expect(article.imageUrl?.path, '/article.jpg');
      final live = await parse(14, {
        'source': '直播',
        'sourceID': '66',
        'author': '主播',
        'title': '正在直播',
        'cover': '//i0.hdslb.com/live.jpg',
      });
      expect(live.kind, ApiMessageContentKind.commonCard);
      expect(live.targetUrl.toString(), 'https://live.bilibili.com/66');
      expect(live.subtitle, '主播');
    },
  );

  test(
    'picture card has distinct jump action and automatic replies preserve subcards',
    () async {
      final picture = await parse(13, {
        'pic_url': '//i0.hdslb.com/poster.jpg',
        'jump_url': 'https://www.bilibili.com/read/cv88',
      });
      expect(picture.kind, ApiMessageContentKind.pictureCard);
      expect(picture.imageUrl?.path, '/poster.jpg');
      expect(picture.targetUrl?.path, '/read/cv88');
      final reply = await parse(16, {
        'main_title': '自动回复',
        'sub_cards': [
          {
            'field1': '推荐视频',
            'field2': 'UP 主',
            'field3': '更多说明',
            'cover_url': '//i0.hdslb.com/a.jpg',
            'jump_url': 'https://www.bilibili.com/video/BV1234567890',
          },
        ],
      });
      expect(reply.kind, ApiMessageContentKind.autoReply);
      expect(reply.cards.single.title, '推荐视频');
      expect(reply.cards.single.description, 'UP 主\n更多说明');
      expect(reply.cards.single.targetUrl?.path, '/video/BV1234567890');
    },
  );

  test(
    'text tips parse nested JSON while voice and mini program remain readable',
    () async {
      final tip = await parse(18, {
        'content': jsonEncode([
          {'text': '提示一'},
          {'text': '提示二'},
        ]),
      });
      expect(tip.kind, ApiMessageContentKind.notice);
      expect(tip.text, '提示一\n提示二');
      final voice = await parse(3, {
        'duration': 12,
        'url': 'https://example.com/voice.mp3',
      });
      expect(voice.kind, ApiMessageContentKind.voice);
      expect(voice.text, contains('12 秒'));
      expect(voice.targetUrl, isNull);
      final mini = await parse(9, {
        'title': '小程序',
        'description': '内容说明',
        'jump_url': 'https://www.bilibili.com/',
      });
      expect(mini.kind, ApiMessageContentKind.miniProgram);
      expect(mini.text, '内容说明');
    },
  );

  test(
    'both recall types and statuses suppress malformed residual payload completely',
    () async {
      for (final (type, status) in [(5, 0), (8, 0), (11, 1), (10, 2)]) {
        transport.handler = (_) => {
          'messages': [message(type: type, status: status, content: '{secret')],
          'has_more': 0,
        };
        final item = (await client.thread('123', 1)).items.single;
        expect(item.kind, ApiMessageContentKind.withdrawn);
        expect(item.text, '消息已撤回');
        expect(item.title, isEmpty);
        expect(item.imageUrl, isNull);
        expect(item.targetUrl, isNull);
        expect(item.cards, isEmpty);
        expect(item.details, isEmpty);
        expect(item.links, isEmpty);
      }
    },
  );

  test(
    'broken rich messages do not hide valid neighbors but identity remains strict',
    () async {
      transport.handler = (_) => {
        'messages': [
          message(sequence: '1', type: 10, content: '{broken'),
          message(sequence: '2'),
        ],
        'has_more': 0,
      };
      final page = await client.thread('123', 1);
      expect(page.items.length, 2);
      expect(page.items.first.kind, ApiMessageContentKind.unsupported);
      expect(page.items.last.text, '中文 & + %');
      transport.handler = (_) => {
        'messages': [
          {...message(), 'msg_seqno': 1.5},
        ],
        'has_more': 0,
      };
      await expectLater(client.thread('123', 1), throwsA(isA<ApiFailure>()));
    },
  );

  test(
    'rich content limits bound display allocation and reject unsafe targets',
    () async {
      final item = await parse(16, {
        'main_title': 'a' * 20000,
        'sub_cards': List.generate(
          100,
          (i) => {'title': '$i', 'jump_url': 'file:///private'},
        ),
        'jump_uri': 'https://www.bilibili.com.evil.example/',
      });
      expect(item.title.length, 16000);
      expect(item.cards.length, 20);
      expect(item.links, isEmpty);
      expect(item.cards.every((c) => c.targetUrl == null), isTrue);
      for (final url in [
        'javascript:alert(1)',
        'file:///tmp/file',
        'https://user:password@www.bilibili.com/',
        'https://evil.example/BV1234567890',
      ]) {
        final bad = await parse(7, {'title': '分享', 'jump_url': url});
        expect(bad.targetUrl, isNull);
      }
      final native = await parse(7, {
        'title': '专栏',
        'jump_url': 'bilibili://article/88',
      });
      expect(native.targetUrl?.path, '/read/cv88');
    },
  );

  test(
    'interaction notice preserves reply and original context separately',
    () async {
      transport.handler = (_) => {
        'items': [
          {
            'id': '9',
            'user': {'mid': '123', 'nickname': '用户'},
            'reply_time': 1700000000,
            'item': {
              'source_content': '新回复',
              'target_reply_content': '原评论',
              'title': '原视频',
              'image': '//i0.hdslb.com/source.jpg',
              'native_uri': 'bilibili://video/170001',
            },
          },
        ],
        'cursor': {'id': 9, 'time': 1700000000, 'is_end': true},
      };
      final item = (await client.notifications(
        ApiInboxSection.replies,
      )).items.single;
      expect(item.text, '新回复');
      expect(item.sourceText, '原评论');
      expect(item.sourceTitle, '原视频');
      expect(item.sourceImageUrl?.path, '/source.jpg');
      expect(item.targetUrl?.path, '/video/BV17x411w7KC');
    },
  );

  test(
    'notification markup becomes readable text with a safe explicit link',
    () async {
      const html =
          '<p>你好 &amp; 欢迎</p><a href="https://www.bilibili.com/video/BV17x411w7KC">查看</a><script>secret()</script>';
      final business = await parse(10, {'title': '通知', 'text': html});
      expect(business.text, '你好 & 欢迎\n查看');
      expect(business.links.single.url.path, '/video/BV17x411w7KC');
      transport.handler = (_) => {
        'system_notify_list': [
          {'id': 9, 'title': '通知', 'content': html},
        ],
      };
      final notice = (await client.notifications(
        ApiInboxSection.system,
      )).items.single;
      expect(notice.text, '你好 & 欢迎\n查看');
      expect(notice.targetUrl?.path, '/video/BV17x411w7KC');
    },
  );

  test(
    'text links are explicit, bounded, safe and preserve literal user text',
    () async {
      final item = await parse(1, {
        'content':
            '看这里 https://www.bilibili.com/video/BV17x411w7KC。 <原文> https://evil.example/secret',
      });
      expect(item.text, contains('<原文>'));
      expect(item.links.single.url.path, '/video/BV17x411w7KC');
      final bounded = await parse(1, {'content': '${'a' * 15999}🙂尾巴'});
      expect(bounded.text.length, 15999);
      expect(bounded.text.runes.last, 97);
    },
  );

  test(
    'sessions retain precise top timestamp and do-not-disturb flags',
    () async {
      transport.handler = (uri) => uri.path.endsWith('/cards')
          ? {
              '123': {'mid': '123', 'name': '用户'},
            }
          : {
              'session_list': [
                {
                  'talker_id': '123',
                  'session_type': 1,
                  'session_ts': '1700000000000000',
                  'top_ts': '9007199254740993123',
                  'is_dnd': 1,
                  'last_msg': message(),
                },
              ],
              'has_more': 0,
            };
      final item = (await client.sessions()).items.single;
      expect(item.pinned, isTrue);
      expect(item.muted, isTrue);
    },
  );
}
