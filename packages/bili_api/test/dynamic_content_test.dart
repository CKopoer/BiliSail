import 'dart:convert';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

import 'dynamic_post_test.dart' show DynamicTransport, post;

Map<String, Object?> richPost({
  Map<String, Object?> major = const {},
  Map<String, Object?> additional = const {},
  List<Object?> nodes = const [],
  Map<String, Object?>? topic,
}) {
  final value = post(major: major, nodes: nodes);
  final modules = value['modules']! as Map<String, Object?>;
  final content = modules['module_dynamic']! as Map<String, Object?>;
  content['additional'] = additional;
  if (topic != null) content['topic'] = topic;
  modules['module_tag'] = {'text': '置顶'};
  modules['module_dispute'] = {'desc': '内容声明'};
  return value;
}

Future<ApiDynamicPost> load(
  Map<String, Object?> value, {
  bool home = true,
}) async {
  final api = BiliApiClient(transport: DynamicTransport([value]));
  if (home) {
    return (await HomeClient(api).load(
      channel: 'dynamic',
      section: '全部',
      page: 1,
    )).items.single.dynamicPost!;
  }
  return (await ProfileClient(api).loadDynamics('2')).items.single.dynamicPost!;
}

void main() {
  for (final home in [true, false]) {
    test(
      'typed reservation retains exact identity and action state in ${home ? "feed" : "space"}',
      () async {
        final card = (await load(
          richPost(
            additional: {
              'type': 'ADDITIONAL_TYPE_RESERVE',
              'reserve': {
                'rid': '9007199254740993123',
                'title': '直播预约',
                'reserve_total': '42',
                'desc1': {'text': '明天20点'},
                'desc2': {'text': '42人预约'},
                'button': {
                  'type': 2,
                  'status': 1,
                  'check': {'text': '取消预约'},
                  'uncheck': {'text': '立即预约', 'disable': '1'},
                },
              },
            },
          ),
          home: home,
        )).contentCards.single;
        final r = card.reservation!;
        expect(
          (r.id, r.status, r.type, r.total),
          ('9007199254740993123', 1, 2, 42),
        );
        expect(
          (r.description, r.checkedText, r.uncheckedText),
          ('42人预约', '取消预约', '立即预约'),
        );
        expect((r.disabled, r.ended, r.hasJump), (true, false, false));
        expect(card.description, '明天20点');
      },
    );
  }
  test(
    'malformed reservation identity and counts never become writable',
    () async {
      for (final (rid, total) in <(Object?, Object?)>[
        (null, 1),
        (1.0, 1),
        ('0', 1),
        ('12', -1),
        ('12', 1.0),
        ('12', null),
      ]) {
        final card = (await load(
          richPost(
            additional: {
              'type': 'ADDITIONAL_TYPE_RESERVE',
              'reserve': {
                'rid': rid,
                'reserve_total': total,
                'button': {'type': 2, 'status': 1},
              },
            },
          ),
        )).contentCards.single;
        expect(card.reservation, isNull);
      }
    },
  );
  for (final home in [true, false]) {
    test(
      'poll identities override unrelated links in ${home ? "home" : "space"}',
      () async {
        final value = await load(
          richPost(
            nodes: [
              {
                'type': 'RICH_TEXT_NODE_TYPE_VOTE',
                'rid': '9007199254740993123',
                'text': '正文投票',
                'jump_url': 'https://t.bilibili.com/123',
              },
            ],
            additional: {
              'type': 'ADDITIONAL_TYPE_VOTE',
              'vote': {
                'vote_id': '9007199254740993123',
                'desc': '投票标题后备',
                'jump_url': 'https://t.bilibili.com/123',
              },
            },
          ),
          home: home,
        );
        final card = value.contentCards.single;
        expect(card.kind, ApiDynamicCardKind.vote);
        expect(card.title, '投票标题后备');
        expect(card.url?.path, '/vote/h5/index/');
        expect(card.url?.queryParameters['vote_id'], '9007199254740993123');
        expect(card.actionUrl, card.url);
        expect(value.spans.single.linkUrl, card.url);
      },
    );
  }
  test(
    'a rich topic rid takes precedence over an unrelated jump URL',
    () async {
      final value = await load(
        richPost(
          nodes: [
            {
              'type': 'RICH_TEXT_NODE_TYPE_TOPIC',
              'rid': '12',
              'text': '#话题#',
              'jump_url': 'https://m.bilibili.com/topic-detail?topic_id=99',
            },
          ],
        ),
      );
      expect(value.spans.single.linkUrl?.host, 'www.bilibili.com');
      expect(value.spans.single.linkUrl?.queryParameters['topic_id'], '12');
    },
  );
  for (final home in [true, false]) {
    for (final (status, type, label) in const <(Object?, Object?, String)>[
      (1, 2, '预约'),
      (2, 2, '已预约'),
      (1, 1, '已预约'),
      (1, 3, '预约'),
      (3, 3, '已预约'),
      ('1', '2', '预约'),
      (null, 2, '查看详情'),
      (1, null, '查看详情'),
      (null, null, '查看详情'),
      (0, 0, '查看详情'),
      ('1万', '1万', '查看详情'),
      (1.0, 1, '查看详情'),
      (-1, 2, '查看详情'),
    ]) {
      test(
        '${home ? 'feed' : 'space'} reservation status=$status type=$type shows $label',
        () async {
          final value = await load(
            richPost(
              additional: {
                'type': 'ADDITIONAL_TYPE_RESERVE',
                'reserve': {
                  'title': '视频预约',
                  'button': {
                    'status': status,
                    'type': type,
                    'check': {'text': '已预约'},
                    'uncheck': {'text': '预约'},
                  },
                },
              },
            ),
            home: home,
          );
          expect(value.contentCards.single.actionLabel, label);
        },
      );
    }
  }
  test(
    'known reservation state uses matching default labels when text is omitted',
    () async {
      for (final (status, label) in [(1, '预约'), (2, '已预约')]) {
        final value = await load(
          richPost(
            additional: {
              'type': 'ADDITIONAL_TYPE_RESERVE',
              'reserve': {
                'title': '视频预约',
                'button': {'status': status, 'type': 2},
              },
            },
          ),
        );
        expect(value.contentCards.single.actionLabel, label);
      }
    },
  );
  test('reservation jump text takes priority over a state label', () async {
    final value = await load(
      richPost(
        additional: {
          'type': 'ADDITIONAL_TYPE_RESERVE',
          'reserve': {
            'title': '视频预约',
            'button': {
              'status': 1,
              'type': 2,
              'jump_style': {'text': '观看视频'},
              'jump_url': 'https://www.bilibili.com/video/BV1234567890',
              'check': {'text': '已预约'},
              'uncheck': {'text': '预约'},
            },
          },
        },
      ),
    );
    expect(value.contentCards.single.actionLabel, '观看视频');
    expect(value.contentCards.single.actionUrl?.path, '/video/BV1234567890');
  });
  test(
    'a topic without an id retains its name as a search destination',
    () async {
      final value = await load(richPost(topic: {'name': '只有名称的话题'}));
      expect(value.topic?.id, isNull);
      expect(value.topic?.url?.host, 'search.bilibili.com');
      expect(value.topic?.url?.queryParameters['keyword'], '只有名称的话题');
    },
  );
  test('a tied match preserves both zero scores in server order', () async {
    final value = await load(
      richPost(
        additional: {
          'type': 'ADDITIONAL_TYPE_MATCH',
          'match': {
            'match_info': {
              'title': '赛事',
              'left_team': {'name': '蓝队'},
              'right_team': {'name': '红队'},
              'center_top': [0, 0],
            },
          },
        },
      ),
    );
    expect(value.contentCards.single.detail, '蓝队 · 0 · 0 · 红队');
  });
  test(
    'official space, course and short-link cards keep their destinations',
    () async {
      for (final (key, url) in [
        ('medialist', 'https://space.bilibili.com/12/lists/34'),
        ('courses', 'https://m.bilibili.com/cheese/play/ep12'),
        ('common', 'https://show.bilibili.com/platform/detail.html?id=12'),
        ('ugc_season', 'https://b23.tv/abc123'),
      ]) {
        final value = await load(
          richPost(
            major: {
              key: {'title': '内容', 'jump_url': url},
            },
          ),
        );
        expect(value.contentCards.single.url.toString(), url);
      }
    },
  );

  test(
    'finished reservations and missing module data remain readable',
    () async {
      final value = await load(
        richPost(
          additional: {
            'type': 'ADDITIONAL_TYPE_RESERVE',
            'reserve': {
              'title': '预约',
              'state': -1,
              'button': {
                'status': 1,
                'type': 1,
                'check': {'text': '已预约'},
              },
            },
          },
        ),
      );
      expect(value.contentCards.single.badge, '已结束');
      expect(value.contentCards.single.actionLabel, '查看详情');
      final malformed = await load(
        richPost(
          additional: {
            'type': 'ADDITIONAL_TYPE_MATCH',
            'match': ['invalid'],
          },
        ),
      );
      expect(malformed.contentCards.single.title, '赛事');
      expect(malformed.contentCards.single.url?.host, 't.bilibili.com');
    },
  );
  for (final home in [true, false]) {
    test(
      '${home ? 'feed' : 'space'} topic, goods and original keep separate identities',
      () async {
        final original = richPost(
          topic: {'id': '9007199254740993123', 'name': '话题名称'},
          additional: {
            'type': 'ADDITIONAL_TYPE_GOODS',
            'goods': {
              'head_text': '好物推荐',
              'items': [
                {
                  'name': '商品甲',
                  'price': '¥19.90',
                  'cover': '//i0.hdslb.com/goods.png',
                  'jump_url':
                      'https://mall.bilibili.com/detail.html?itemsId=12',
                  'jump_desc': '去看看',
                },
                {
                  'name': '商品乙',
                  'price': '¥29',
                  'jump_url': 'https://shop.example.test/item/2',
                },
              ],
            },
          },
        );
        final value = await load(
          post(id: '10', original: original),
          home: home,
        );
        final orig = value.original!;
        expect(value.topic, isNull);
        expect(orig.topic?.id, '9007199254740993123');
        expect(
          orig.topic?.url.toString(),
          'https://www.bilibili.com/v/topic/detail?topic_id=9007199254740993123',
        );
        expect(orig.contentCards.map((e) => e.kind), [
          ApiDynamicCardKind.goods,
          ApiDynamicCardKind.goods,
        ]);
        expect(orig.contentCards.first.description, '¥19.90');
        expect(orig.contentCards.first.actionLabel, '去看看');
        expect(orig.contentCards.first.coverUrl?.scheme, 'https');
        expect(orig.contentCards.last.url?.host, 'shop.example.test');
        expect(orig.badge, '置顶');
        expect(orig.notice, '内容声明');
        expect(() => orig.contentCards.clear(), throwsUnsupportedError);
      },
    );
  }

  for (final (key, kind) in [
    ('article', ApiDynamicCardKind.article),
    ('pgc', ApiDynamicCardKind.pgc),
    ('courses', ApiDynamicCardKind.course),
    ('ugc_season', ApiDynamicCardKind.season),
    ('music', ApiDynamicCardKind.music),
    ('medialist', ApiDynamicCardKind.medialist),
    ('common', ApiDynamicCardKind.common),
    ('upower_common', ApiDynamicCardKind.common),
  ]) {
    test('$key retains its major card alongside additions', () async {
      final value = await load(
        richPost(
          major: {
            key: {
              'id': '12',
              'epid': '21',
              'title': '卡片标题',
              'cover': '//i0.hdslb.com/cover.png',
              'desc': '卡片说明',
              'label': '音乐标签',
              'stat': {'play': 123, 'danmaku': '4'},
              'badge': {'text': '会员'},
            },
          },
          additional: {
            'type': 'ADDITIONAL_TYPE_VOTE',
            'vote': {'vote_id': '33', 'title': '你的选择', 'join_num': 1234},
          },
        ),
      );
      expect(value.contentCards.map((e) => e.kind), [
        kind,
        ApiDynamicCardKind.vote,
      ]);
      expect(value.contentCards.first.title, '卡片标题');
      expect(value.contentCards.first.badge, '会员');
      expect(value.contentCards.first.detail, '123播放 · 4弹幕');
      expect(value.contentCards.last.description, '1234人参与');
      expect(value.contentCards.last.url?.queryParameters['vote_id'], '33');
      if (key == 'pgc') {
        expect(value.contentCards.first.url?.path, '/bangumi/play/ep21');
      }
      if (key == 'music') {
        expect(value.contentCards.first.url?.path, '/audio/au12');
      }
    });
  }

  for (final (key, type, kind) in [
    ('ugc', 'UGC', ApiDynamicCardKind.ugc),
    ('reserve', 'RESERVE', ApiDynamicCardKind.reservation),
    ('upower_lottery', 'UPOWER_LOTTERY', ApiDynamicCardKind.lottery),
    ('match', 'MATCH', ApiDynamicCardKind.match),
    ('common', 'COMMON', ApiDynamicCardKind.common),
  ]) {
    test('$type includes description, secondary action and state', () async {
      final value = await load(
        richPost(
          additional: {
            'type': 'ADDITIONAL_TYPE_$type',
            key: {
              'title': '附加标题',
              'desc1': {'text': '明天开始'},
              'desc2': {'text': '第二行'},
              'desc3': {'text': '奖品'},
              'reserve_total': '230',
              'jump_url': 'https://www.bilibili.com/opus/12',
              'button': {
                'status': 1,
                'check': {'text': '已预约'},
                'jump_url': 'https://www.bilibili.com/opus/13',
                'type': 1,
              },
              'match_info': {
                'left_team': {'name': '蓝队'},
                'right_team': {'name': '红队'},
                'center_top': ['2', '1'],
                'center_bottom': '已结束',
              },
            },
          },
        ),
      );
      final card = value.contentCards.single;
      expect(card.kind, kind);
      expect(card.description, contains('明天开始'));
      expect(card.actionLabel, '已预约');
      expect(card.actionUrl?.path, '/opus/13');
      if (kind == ApiDynamicCardKind.match) {
        expect(card.detail, '蓝队 · 2 · 1 · 红队 · 已结束');
      }
      if (kind == ApiDynamicCardKind.reservation) {
        expect(card.detail, contains('230人预约'));
      }
    });
  }

  test('live JSON and subscription keep primary and attached goods', () async {
    final value = await load(
      richPost(
        major: {
          'subscription_new': {
            'live_rcmd': {
              'content': jsonEncode({
                'live_play_info': {
                  'room_id': '123',
                  'title': '直播标题',
                  'area_name': '游戏',
                  'live_status': 1,
                },
              }),
            },
          },
        },
        additional: {
          'type': 'ADDITIONAL_TYPE_GOODS',
          'goods': {
            'items': [
              {'name': '商品'},
            ],
          },
        },
      ),
    );
    expect(value.contentCards.map((e) => e.kind), [
      ApiDynamicCardKind.live,
      ApiDynamicCardKind.goods,
    ]);
    expect(value.contentCards.first.url?.host, 'live.bilibili.com');
  });

  test(
    'rich nodes keep orig_text and actionable BV, goods, vote and topic links',
    () async {
      final value = await load(
        richPost(
          nodes: [
            {
              'type': 'RICH_TEXT_NODE_TYPE_BV',
              'rid': 'BV1234567890',
              'text': '视频',
            },
            {
              'type': 'RICH_TEXT_NODE_TYPE_GOODS',
              'text': '商品',
              'jump_url': 'https://mall.bilibili.com/item/1',
            },
            {
              'type': 'RICH_TEXT_NODE_TYPE_TOPIC',
              'rid': '12',
              'orig_text': '#话题#',
            },
            {'type': 'RICH_TEXT_NODE_TYPE_VOTE', 'rid': '13', 'text': '投票'},
            {'type': 'RICH_TEXT_NODE_TYPE_LOTTERY', 'orig_text': '抽奖'},
            {
              'type': 'RICH_TEXT_NODE_TYPE_EMOJI',
              'emoji': {
                'text': '[表情]',
                'webp_url': '//i0.hdslb.com/emoji.webp',
              },
            },
          ],
        ),
      );
      expect(value.spans.map((e) => e.text), [
        '视频',
        '商品',
        '#话题#',
        '投票',
        '抽奖',
        '[表情]',
      ]);
      expect(value.spans.first.linkUrl?.path, '/video/BV1234567890');
      expect(value.spans[1].kind, ApiDynamicTextKind.link);
      expect(value.spans[2].linkUrl?.queryParameters['topic_id'], '12');
      expect(value.spans[3].linkUrl?.queryParameters['vote_id'], '13');
      expect(value.spans[4].linkUrl?.path, '/h5/lottery/result');
      expect(value.spans.last.kind, ApiDynamicTextKind.emoji);
    },
  );

  test(
    'unknown modules remain readable and goods have bounded safe destinations',
    () async {
      final value = await load(
        richPost(
          major: {
            'type': 'MAJOR_TYPE_FUTURE',
            'future': {'title': '未知'},
          },
          additional: {
            'type': 'ADDITIONAL_TYPE_GOODS',
            'goods': {
              'items': List.generate(
                30,
                (index) => {
                  'name': '商品$index',
                  'jump_url': index == 0
                      ? 'javascript:alert(1)'
                      : 'https://user:secret@evil.test/item',
                },
              ),
            },
          },
        ),
      );
      expect(value.contentCards, hasLength(11));
      expect(value.contentCards.first.kind, ApiDynamicCardKind.unknown);
      expect(value.contentCards.first.url?.host, 't.bilibili.com');
      expect(
        value.contentCards
            .skip(1)
            .every((e) => e.url == null && e.actionUrl == null),
        isTrue,
      );
      final malformed = await load(
        richPost(additional: {'type': 'ADDITIONAL_TYPE_NEW', 'future': []}),
      );
      expect(malformed.contentCards.single.kind, ApiDynamicCardKind.unknown);
    },
  );
}
