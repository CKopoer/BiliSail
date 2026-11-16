import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

const _device = 'XY1234567890ABCDEF1234567890ABCDEF12345';
Map<String, Object?> _entry({Map<String, Object?> extra = const {}}) => {
  'card_goto': 'av',
  'can_play': 1,
  'param': '170001',
  'idx': 1794819840,
  'title': 'App 视频',
  'cover': 'http://i0.hdslb.com/bfs/archive/cover.jpg',
  'args': {'up_id': 42, 'up_name': 'UP', 'tname': '音乐'},
  'player_args': {'aid': 170001, 'cid': 99, 'duration': 180},
  'cover_left_text_1': '1.2万',
  'cover_left_text_2': '23',
  'three_point_v2': [
    {
      'type': 'dislike',
      'reasons': [
        {'id': 1, 'name': '不想看此视频'},
      ],
    },
    {
      'type': 'feedback',
      'reasons': [
        {'id': 7, 'name': '内容不适'},
      ],
    },
  ],
  ...extra,
};
ApiHttpResponse _response(Object? data, {int code = 0, int status = 200}) =>
    ApiHttpResponse(
      status,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': code, 'data': data}))),
      const {},
    );

void main() {
  test(
    'official scenes and raw card anchors are independent of accepted cards',
    () async {
      final transport = _Transport()
        ..entries = [
          _entry(extra: {'idx': '1794819840', 'card_goto': 'ad_av'}),
          _entry(extra: {'idx': 1794819839}),
        ];
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      final client = AppRecommendationClient(api);
      for (final reason in ApiAppRecommendationLoadReason.values) {
        final page = await client.load(
          cursor: '1794819840',
          reason: reason,
          buvid: _device,
        );
        expect(page.items, hasLength(1));
        expect(page.nextCursor, '1794819840');
        expect(transport.uris.last.queryParameters['idx'], '1794819840');
        expect(transport.uris.last.queryParameters['flush'], '${reason.flush}');
        expect(transport.uris.last.queryParameters['pull'], '${reason.pull}');
      }
      transport.entries = [
        _entry(extra: {'idx': '-11', 'can_play': 0}),
      ];
      final filtered = await client.load(buvid: _device);
      expect(filtered.items, isEmpty);
      expect(filtered.nextCursor, '-11');
      expect(filtered.hasMore, isTrue);
      for (final cursor in [
        '1.0',
        'abc',
        '9223372036854775808',
        '-9223372036854775809',
      ]) {
        await expectLater(
          client.load(cursor: cursor, buvid: _device),
          throwsArgumentError,
        );
      }
    },
  );

  test(
    'feed URI trackid decodes once, falls back to track_id and rejects invalid data',
    () async {
      final transport = _Transport()
        ..entries = [
          _entry(
            extra: {
              'uri': 'bilibili://video/170001?trackid=a%252Fb',
              'track_id': 'fallback',
            },
          ),
          _entry(extra: {'track_id': 'fallback'}),
          _entry(extra: {'uri': 'bilibili://video/170001?trackid=a&trackid=b'}),
          _entry(extra: {'track_id': 'bad\r\nvalue'}),
          _entry(extra: {'track_id': 'x' * 2049}),
        ];
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      final page = await AppRecommendationClient(api).load(buvid: _device);
      expect(page.items.map((item) => item.trackId), [
        'a%2Fb',
        'fallback',
        null,
        null,
        null,
      ]);
    },
  );

  test(
    'Android facts are captured once per feed request and trace changes within a session',
    () async {
      final transport = _Transport();
      var reads = 0;
      final api = BiliApiClient(
        transport: transport,
        loadAppDevice: () async {
          reads++;
          return const AppDeviceInfo(
            model: 'Pixel 9',
            osVersion: '16',
            network: 'mobile',
          );
        },
      );
      addTearDown(api.close);
      final client = AppRecommendationClient(api);
      await client.load(buvid: _device);
      await client.load(
        cursor: '1794819840',
        reason: ApiAppRecommendationLoadReason.loadMore,
        buvid: _device,
      );
      expect(reads, 2);
      expect(transport.uris.last.queryParameters['device_name'], 'Pixel 9');
      expect(transport.uris.last.queryParameters['network'], 'mobile');
      expect(transport.uris.last.queryParameters['mobi_app'], 'android_hd');
      expect(transport.headers.last['User-Agent'], contains('model/Pixel 9'));
      expect(
        transport.headers.last['User-Agent'],
        contains('osVer/16 network/1'),
      );
      expect(
        transport.headers.first['session_id'],
        transport.headers.last['session_id'],
      );
      expect(
        transport.headers.first['x-bili-trace-id'],
        isNot(transport.headers.last['x-bili-trace-id']),
      );
      expect(transport.headers.last, isNot(contains('fp_local')));
      expect(transport.headers.last, isNot(contains('bili-http-engine')));
    },
  );

  test(
    'App publication timestamps remain optional and reject invalid values',
    () async {
      final values = <Object?>[
        1793505600,
        '1793505600',
        null,
        0,
        -1,
        1.5,
        'bad',
        8640000000001,
      ];
      final transport = _Transport()
        ..entries = [
          for (final value in values) _entry(extra: {'pubdate': value}),
        ];
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      final page = await AppRecommendationClient(api).load(buvid: _device);
      expect(page.items.length, values.length);
      final date = DateTime.fromMillisecondsSinceEpoch(
        1793505600000,
        isUtc: true,
      );
      expect(page.items.map((item) => item.video.publishedAt), [
        date,
        date,
        null,
        null,
        null,
        null,
        null,
        null,
      ]);
      expect(transport.uris, hasLength(1));
    },
  );

  test(
    'App follow markers do not discard independent recommendation text',
    () async {
      final cases = <(Object?, Object?, String?, bool?)>[
        (' 已关注 ', null, null, true),
        ('新关注', null, null, true),
        (' 3万点赞 ', 1, '3万点赞', true),
        ('关注的人也在看', true, '关注的人也在看', true),
        ('竖屏', null, null, null),
        (' ', null, null, null),
        (null, null, null, null),
        (12, null, null, null),
        ({'content': 12}, null, null, null),
      ];
      final transport = _Transport()
        ..entries = [
          for (final value in cases)
            _entry(extra: {'rcmd_reason': value.$1, 'is_followed': value.$2}),
        ];
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      final page = await AppRecommendationClient(api).load(buvid: _device);
      expect(page.items.length, cases.length);
      for (var index = 0; index < cases.length; index++) {
        final video = page.items[index].video;
        expect(video.recommendationReason, cases[index].$3);
        expect(video.isFollowed, cases[index].$4);
        expect(video.likeCount, isNull);
      }
    },
  );

  test('aid conversion handles known old and new IDs without detail reads', () {
    expect(VideoIdentifiers.bvidFromAid('170001'), 'BV17x411w7KC');
    expect(VideoIdentifiers.bvidFromAid('455017605'), 'BV1Q541167Qg');
    for (final value in ['0', '-1', '1.0', '2251799813685248', 'x']) {
      expect(VideoIdentifiers.bvidFromAid(value), isNull);
    }
    expect(
      VideoIdentifiers.bvidFromAid('117501614627628'),
      matches(r'^BV[0-9A-Za-z]{10}$'),
    );
  });

  test(
    'App profile signs the transmitted values once and never carries Web cookies',
    () async {
      final transport = _Transport();
      final api = BiliApiClient(
        transport: transport,
        clock: () => DateTime.fromMillisecondsSinceEpoch(1234567890000),
      );
      api.cookieJar.receive(Uri.https('app.bilibili.com', '/'), [
        'SESSDATA=fixture-cookie; Domain=bilibili.com; Path=/; Secure',
      ]);
      await api.requestAppJson(
        '/x/v2/feed/index',
        {'text': 'a b%中', 'empty': '', 'sign': 'stale'},
        endpoint: 'app_recommended',
        buvid: _device,
        accessToken: 'fixture-token',
        appAccountMid: '42',
      );
      final uri = transport.uris.single;
      expect(uri.host, 'app.bilibili.com');
      expect(uri.queryParameters['text'], 'a b%中');
      expect(uri.queryParameters['access_key'], 'fixture-token');
      final expected = md5
          .convert(
            utf8.encode(
              'access_key=fixture-token&appkey=dfca71928277209b&empty=&text=a%20b%25%E4%B8%AD&ts=1234567890b5475a8825547a4fc26c7d518eaaa02e',
            ),
          )
          .toString();
      expect(uri.queryParameters['sign'], expected);
      expect(
        transport.headers.single.keys.map((key) => key.toLowerCase()),
        isNot(contains('cookie')),
      );
      final headers = {...transport.headers.single};
      expect(headers.remove('session_id'), matches(r'^[0-9a-f]{8}$'));
      expect(
        headers.remove('x-bili-trace-id'),
        matches(r'^[0-9a-f]{32}:[0-9a-f]{16}:0:0$'),
      );
      expect(headers, {
        'Accept': 'application/json',
        'User-Agent':
            'Mozilla/5.0 BiliDroid/2.0.1 (bbcallen@gmail.com) os/android '
            'model/android_hd mobi_app/android_hd build/2001100 channel/master '
            'innerVer/2001100 osVer/15 network/2',
        'buvid': _device,
        'app-key': 'android_hd',
        'env': 'prod',
        'x-bili-mid': '42',
        'x-bili-aurora-eid': 'VVY',
        'x-bili-aurora-zone': 'sh001',
        'referer': 'https://www.bilibili.com',
      });
      await expectLater(
        api.requestAppJson(
          '/unregistered',
          {},
          endpoint: 'invalid',
          buvid: _device,
        ),
        throwsArgumentError,
      );
      expect(transport.uris.length, 1);
    },
  );

  test(
    'App account headers reject missing tokens and invalid account IDs',
    () async {
      final transport = _Transport();
      final client = AppRecommendationClient(
        BiliApiClient(transport: transport),
      );
      for (final value in [
        (token: null, mid: '42'),
        (token: '', mid: '42'),
        (token: 'fixture-token', mid: '42\r\nInjected: value'),
        (token: 'fixture-token', mid: '0'),
      ]) {
        await expectLater(
          client.load(
            buvid: _device,
            accessToken: value.token,
            appAccountMid: value.mid,
          ),
          throwsArgumentError,
        );
      }
      expect(transport.uris, isEmpty);
    },
  );

  test(
    'App cards map metadata and server reasons, skipping advertisements and invalid identities',
    () async {
      final transport = _Transport()
        ..entries = [
          _entry(extra: {'rcmd_reason': '已关注'}),
          _entry(extra: {'card_goto': 'ad_av'}),
          _entry(extra: {'ad_info': {}}),
          _entry(extra: {'can_play': 0}),
          _entry(extra: {'card_goto': 'ad_web_s'}),
          _entry(extra: {'param': 'invalid', 'player_args': {}}),
        ];
      final page = await AppRecommendationClient(
        BiliApiClient(transport: transport),
      ).load(buvid: _device);
      final item = page.items.single;
      expect(item.video.bvid, 'BV17x411w7KC');
      expect(item.video.coverUrl?.scheme, 'https');
      expect(item.video.previewCid, '99');
      expect(item.video.ownerMid, '42');
      expect(item.video.categoryName, '音乐');
      expect(item.video.playCount, 12000);
      expect(item.video.danmakuCount, 23);
      expect(item.video.duration.inSeconds, 180);
      expect(item.video.isFollowed, isTrue);
      expect(item.video.likeCount, isNull);
      expect(item.video.recommendationReason, isNull);
      expect(item.reasons.map((reason) => (reason.kind, reason.id)), [
        (ApiAppFeedbackKind.dislike, '1'),
        (ApiAppFeedbackKind.feedback, '7'),
      ]);
      expect(page.hasMore, isTrue);
      expect(transport.uris.single.queryParameters['idx'], '0');
      expect(transport.uris.single.queryParameters['pull'], 'true');
      expect(transport.uris.single.queryParameters['splash_id'], '');
      expect(
        transport.uris.single.queryParameters.containsKey('access_key'),
        isFalse,
      );
      expect(transport.headers.single['buvid'], _device);
      expect(transport.headers.single['session_id'], matches(r'^[0-9a-f]{8}$'));
      expect(transport.headers.single.containsKey('x-bili-mid'), isFalse);
      expect(transport.headers.single['x-bili-aurora-eid'], '');
      expect(transport.uris.length, 1);
    },
  );

  test(
    'HD credentials use a coherent feed profile and explicit request scenes',
    () async {
      final transport = _Transport();
      final client = AppRecommendationClient(
        BiliApiClient(
          transport: transport,
          clock: () => DateTime.fromMillisecondsSinceEpoch(1234567890000),
        ),
      );
      for (final page in [1, 3]) {
        await client.load(
          cursor: '${page - 1}',
          reason: page == 1
              ? ApiAppRecommendationLoadReason.initial
              : ApiAppRecommendationLoadReason.loadMore,
          buvid: _device,
          accessToken: 'fixture-token',
          appAccountMid: '42',
        );
        final query = {...transport.uris.last.queryParameters}..remove('sign');
        expect(query, {
          'build': '2001100',
          'c_locale': 'zh_CN',
          'channel': 'master',
          'column': '2',
          'device': 'pad',
          'device_name': 'android_hd',
          'device_type': '0',
          'disable_rcmd': '0',
          'flush': page == 1 ? '0' : '8',
          'fnval': '976',
          'fnver': '0',
          'force_host': '2',
          'fourk': '1',
          'guidance': '0',
          'https_url_req': '1',
          'idx': '${page - 1}',
          'mobi_app': 'android_hd',
          'network': 'wifi',
          'platform': 'android',
          'player_net': '1',
          'pull': page == 1 ? 'true' : 'false',
          'qn': '32',
          'recsys_mode': '0',
          's_locale': 'zh_CN',
          'splash_id': '',
          'statistics':
              '{"appId":5,"platform":3,"version":"2.0.1","abtest":""}',
          'voice_balance': '0',
          'access_key': 'fixture-token',
          'appkey': 'dfca71928277209b',
          'ts': '1234567890',
        });
        // Fixed vectors include splash_id= in the independently encoded input.
        expect(
          transport.uris.last.queryParameters['sign'],
          page == 1
              ? '533f4629ca6f106643e6076213d4f36a'
              : '34011548643b7f5fb2537735efb2f8c7',
        );
      }
    },
  );

  test(
    'playable non-ad cards retain their type and original identity',
    () async {
      final transport = _Transport()
        ..entries = [
          for (final type in [
            'av',
            'vertical_av',
            'bangumi',
            'picture',
            'future_card',
          ])
            _entry(
              extra: {
                'card_goto': type,
                'param': '42',
                'desc_button': {'text': '系列作者'},
                'uri': 'bilibili://following/42',
              },
            ),
          _entry(extra: {'card_goto': 'ad_av'}),
          _entry(extra: {'card_goto': 'ad_web_s'}),
          _entry(extra: {'card_goto': 'future_card', 'ad_info': {}}),
          _entry(extra: {'card_goto': 'bangumi', 'can_play': 0}),
          _entry(extra: {'card_goto': 'picture', 'can_play': null}),
        ];
      final page = await AppRecommendationClient(
        BiliApiClient(transport: transport),
      ).load(buvid: _device);
      expect(page.items.map((item) => item.cardGoto), [
        'av',
        'vertical_av',
        'bangumi',
        'picture',
        'future_card',
      ]);
      expect(page.items.map((item) => item.param).toSet(), {'42'});
      expect(page.items.first.aid, '170001');
      expect(page.items.first.video.bvid, 'BV17x411w7KC');
      expect(
        page.items.skip(1).every((item) => item.video.bvid.isEmpty),
        isTrue,
      );
      expect(page.items.last.video.ownerName, '系列作者');
      expect(
        page.items.last.navigationUri,
        Uri.parse('bilibili://following/42'),
      );
      transport.entries = [
        _entry(extra: {'card_goto': 'bangumi', 'player_args': {}}),
      ];
      final episode = (await AppRecommendationClient(
        BiliApiClient(transport: transport),
      ).load(buvid: _device)).items.single;
      expect(episode.aid, isNull, reason: 'An episode param is not an AV aid');
      expect(episode.video.bvid, isEmpty);
    },
  );

  test(
    'non-video feedback and undo keep the original goto and param',
    () async {
      final transport = _Transport();
      final client = AppRecommendationClient(
        BiliApiClient(transport: transport),
      );
      for (final undo in [false, true]) {
        await client.feedback(
          aid: '42',
          goto: 'bangumi',
          buvid: _device,
          accessToken: 'fixture-token',
          undo: undo,
          reason: const ApiAppFeedbackReason(
            id: '7',
            name: '内容不适',
            kind: ApiAppFeedbackKind.feedback,
          ),
        );
        expect(transport.uris.last.queryParameters['goto'], 'bangumi');
        expect(transport.uris.last.queryParameters['id'], '42');
      }
    },
  );

  test(
    'missing fields stay unknown and a filtered server page retains pagination opportunity',
    () async {
      final transport = _Transport()
        ..entries = [
          _entry(
            extra: {
              'cover_left_text_1': '--',
              'cover_left_text_2': '',
              'rcmd_reason': '很多赞',
            },
          ),
        ];
      final client = AppRecommendationClient(
        BiliApiClient(transport: transport),
      );
      final item = (await client.load(
        cursor: '1',
        reason: ApiAppRecommendationLoadReason.loadMore,
        buvid: _device,
      )).items.single.video;
      expect(item.playCount, isNull);
      expect(item.likeCount, isNull);
      expect(item.isFollowed, isNull);
      expect(transport.uris.last.queryParameters['idx'], '1');
      expect(transport.uris.last.queryParameters['pull'], 'false');
      transport.entries = [
        _entry(extra: {'card_goto': 'ad_av'}),
      ];
      final empty = await client.load(
        cursor: '2',
        reason: ApiAppRecommendationLoadReason.loadMore,
        buvid: _device,
      );
      expect(empty.items, isEmpty);
      expect(empty.hasMore, isTrue);
      transport.entries = [];
      expect(
        (await client.load(
          cursor: '3',
          reason: ApiAppRecommendationLoadReason.loadMore,
          buvid: _device,
        )).hasMore,
        isFalse,
      );
    },
  );

  test(
    'feedback uses its server reason type and never retries an uncertain GET mutation',
    () async {
      final transport = _Transport()..status = 503;
      final client = AppRecommendationClient(
        BiliApiClient(transport: transport),
      );
      const reason = ApiAppFeedbackReason(
        id: '7',
        name: '内容不适',
        kind: ApiAppFeedbackKind.feedback,
      );
      await expectLater(
        client.feedback(
          aid: '170001',
          buvid: _device,
          accessToken: 'fixture-token',
          reason: reason,
          undo: false,
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.uris.length, 1);
      expect(transport.uris.single.queryParameters['feedback_id'], '7');
      expect(transport.headers.single.containsKey('fp_local'), isFalse);
      expect(
        transport.uris.single.queryParameters.containsKey('reason_id'),
        isFalse,
      );
      transport.status = 200;
      await client.feedback(
        aid: '170001',
        buvid: _device,
        accessToken: 'fixture-token',
        undo: true,
      );
      expect(transport.uris.last.path, '/x/feed/dislike/cancel');
      expect(
        transport.uris.last.queryParameters.containsKey('feedback_id'),
        isFalse,
      );
    },
  );

  test(
    'App reads reuse the bounded retry budget; redirects are rejected without following',
    () async {
      final transport = _Transport()..status = 503;
      final api = BiliApiClient(transport: transport);
      await expectLater(
        AppRecommendationClient(api).load(buvid: _device),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.uris.length, 3);
      transport.uris.clear();
      transport.status = 302;
      await expectLater(
        AppRecommendationClient(api).load(buvid: _device),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.uris.length, 1);
    },
  );

  test(
    'epoch and cancellation isolate late responses before decoding',
    () async {
      final transport = _Transport()..pending = Completer<ApiHttpResponse>();
      final session = _Session();
      final api = BiliApiClient(transport: transport, sessionProvider: session);
      final read = AppRecommendationClient(api).load(buvid: _device);
      final check = expectLater(
        read,
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.cancelled,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      session.sessionEpoch++;
      transport.pending!.complete(_response({'items': []}));
      await check;
      final cancellation = ApiCancellation()..cancel();
      await expectLater(
        AppRecommendationClient(api).load(
          buvid: _device,
          context: ApiRequestContext(cancellation: cancellation),
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.uris.length, 1);
    },
  );

  test(
    'QR uses signed single-attempt form posts and validates pending/confirmed identity',
    () async {
      final transport = _Transport();
      final client = AppPassportClient(
        BiliApiClient(transport: transport),
        clock: () => DateTime.utc(2026),
      );
      final code = await client.generate(buvid: _device);
      expect(code.authCode, 'fixture-code');
      expect(transport.posts.single['appkey'], isNotEmpty);
      expect(transport.headers.single.containsKey('fp_local'), isFalse);
      expect(
        (await client.poll(buvid: _device, authCode: code.authCode)).status,
        ApiQrStatus.waitingScan,
      );
      transport.confirmed = true;
      final result = await client.poll(buvid: _device, authCode: code.authCode);
      expect(result.credentials?.mid, '42');
      expect(
        result.credentials?.expiresAt,
        DateTime.utc(2026).add(const Duration(seconds: 3600)),
      );
      transport.status = 503;
      final before = transport.posts.length;
      await expectLater(
        client.generate(buvid: _device),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.posts.length, before + 1);
    },
  );
}

final class _Session implements ApiSessionProvider {
  @override
  int sessionEpoch = 1;
}

final class _Transport implements ApiTransport, ApiFormTransport {
  List<Map<String, Object?>> entries = [];
  final uris = <Uri>[];
  final headers = <Map<String, String>>[];
  final posts = <Map<String, String>>[];
  int status = 200;
  bool confirmed = false;
  Completer<ApiHttpResponse>? pending;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    uris.add(uri);
    this.headers.add(headers);
    return pending?.future ??
        _response(
          uri.path == '/x/v2/feed/index' ? {'items': entries} : null,
          status: status,
        );
  }

  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    posts.add(fields);
    this.headers.add(headers);
    return _response(
      uri.path.endsWith('/auth_code')
          ? {
              'auth_code': 'fixture-code',
              'url': 'https://passport.bilibili.com/fixture',
            }
          : confirmed
          ? {
              'token_info': {
                'mid': 42,
                'access_token': 'fixture-token',
                'expires_in': 3600,
              },
            }
          : null,
      code: uri.path.endsWith('/poll') && !confirmed ? 86039 : 0,
      status: status,
    );
  }
}
