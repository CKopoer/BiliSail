import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

const _bvid = 'BV1q6ad6NEVK';
const _charging = {
  'is_upower_exclusive': true,
  'is_upower_play': false,
  'is_upower_preview': true,
  'rights': {'pay': 0, 'ugc_pay': 0, 'arc_pay': 0},
};

void main() {
  final cases = <(Map<String, Object?>, ApiVideoAccessKind, bool?)>[
    (_charging, ApiVideoAccessKind.chargingExclusive, false),
    (
      {..._charging, 'is_upower_play': true},
      ApiVideoAccessKind.chargingExclusive,
      true,
    ),
    ({'is_upower_exclusive': 1}, ApiVideoAccessKind.chargingExclusive, null),
    ({'is_upower_exclusive': '1'}, ApiVideoAccessKind.chargingExclusive, null),
    ({'is_charging_arc': true}, ApiVideoAccessKind.chargingExclusive, null),
    (
      {
        'badge': {'text': '充电专属'},
      },
      ApiVideoAccessKind.chargingExclusive,
      null,
    ),
    (
      {
        'rights': {'ugc_pay': 1},
      },
      ApiVideoAccessKind.paid,
      null,
    ),
    (
      {
        'rights': {'arc_pay': 1},
      },
      ApiVideoAccessKind.paid,
      null,
    ),
    (
      {
        'rights': {'pay': 1},
      },
      ApiVideoAccessKind.paid,
      null,
    ),
    ({'is_pay': 1}, ApiVideoAccessKind.paid, null),
    (
      {
        'rights': {'elec': 1},
      },
      ApiVideoAccessKind.normal,
      null,
    ),
    ({'is_upower_exclusive': false}, ApiVideoAccessKind.normal, null),
    ({'is_upower_exclusive': 'false'}, ApiVideoAccessKind.normal, null),
    ({}, ApiVideoAccessKind.normal, null),
  ];
  for (var i = 0; i < cases.length; i++) {
    test('detail and shared lists preserve access flags case $i', () async {
      final (fields, kind, entitlement) = cases[i];
      final transport = _Transport(access: fields);
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      final detail = await api.getVideoDetail(_bvid);
      final related = await api.getRelatedVideos(_bvid);
      expect(detail.access.kind, kind);
      expect(detail.access.canWatch, entitlement);
      expect(related.single.access.kind, kind);
      expect(related.single.access.canWatch, entitlement);
    });
  }

  test(
    'watch later and search retain content classification without guessing rights',
    () async {
      final api = BiliApiClient(transport: _Transport(access: _charging));
      addTearDown(api.close);
      final home = await HomeClient(
        api,
      ).load(channel: 'watchLater', section: 'all', page: 1);
      final search = await SearchClient(
        api,
      ).search('测试', type: ApiSearchType.video);
      expect(
        home.items.single.access.kind,
        ApiVideoAccessKind.chargingExclusive,
      );
      expect(
        (search.items.single as ApiSearchVideo).video.access.kind,
        ApiVideoAccessKind.chargingExclusive,
      );
    },
  );

  test('space submissions use their is_charging_arc field', () async {
    final api = BiliApiClient(
      transport: _Transport(access: {'is_charging_arc': true}),
    );
    addTearDown(api.close);
    final page = await ProfileClient(api).loadVideos('490505561', page: 1);
    expect(
      page.items.single.video?.access.kind,
      ApiVideoAccessKind.chargingExclusive,
    );
    expect(page.items.single.video?.access.canWatch, isNull);
  });

  for (final play in <Map<String, Object?>>[
    {},
    {
      'dash': {'video': []},
    },
    {
      'dash': {'audio': []},
    },
    {
      'dash': {'video': [], 'audio': []},
    },
    {'code': -404},
  ]) {
    test(
      'blocked charging playback identifies permission instead of unavailable: $play',
      () async {
        final transport = _Transport(access: _charging, play: play);
        final api = BiliApiClient(transport: transport);
        addTearDown(api.close);
        await expectLater(
          api.getPlayInfo(_bvid, '42328985110'),
          throwsA(
            isA<ApiFailure>()
                .having(
                  (e) => e.category,
                  'category',
                  ApiFailureCategory.permission,
                )
                .having(
                  (e) => e.videoAccessKind,
                  'access',
                  ApiVideoAccessKind.chargingExclusive,
                )
                .having((e) => e.businessCode, 'business', play['code']),
          ),
        );
        expect(transport.details, 1);
      },
    );
  }
  test('ordinary and entitled missing streams remain unavailable', () async {
    for (final fields in <Map<String, Object?>>[
      {},
      {..._charging, 'is_upower_play': true},
    ]) {
      final api = BiliApiClient(transport: _Transport(access: fields));
      addTearDown(api.close);
      await expectLater(
        api.getPlayInfo(_bvid, '42328985110'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.unavailable,
          ),
        ),
      );
    }
  });
  test('paid videos without streams report purchase requirement', () async {
    final api = BiliApiClient(
      transport: _Transport(
        access: {
          'rights': {'ugc_pay': 1},
        },
      ),
    );
    addTearDown(api.close);
    await expectLater(
      api.getPlayInfo(_bvid, '42328985110'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.videoAccessKind,
          'access',
          ApiVideoAccessKind.paid,
        ),
      ),
    );
  });
  test(
    'full DASH playback keeps the successful path without a detail request',
    () async {
      final transport = _Transport(access: _charging, play: _dash);
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      final info = await api.getPlayInfo(_bvid, '42328985110');
      expect(info.dashVideo, hasLength(1));
      expect(info.dashAudio, hasLength(1));
      expect(transport.details, 0);
    },
  );
  test(
    'trials cannot become complete playback but hover retains the preview marker',
    () async {
      final transport = _Transport(
        access: _charging,
        play: {..._dash, 'is_preview': 1},
      );
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      await expectLater(
        api.getPlayInfo(_bvid, '42328985110'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.videoAccessKind,
            'access',
            ApiVideoAccessKind.chargingExclusive,
          ),
        ),
      );
      final hover = await api.getVideoPreviewInfo(_bvid, '42328985110');
      expect(hover.isPreview, true);
    },
  );
  test('cancelled entitlement reads cannot return a paywall failure', () async {
    final cancellation = ApiCancellation();
    final api = BiliApiClient(
      transport: _Transport(access: _charging, onDetail: cancellation.cancel),
    );
    addTearDown(api.close);
    await expectLater(
      api.getPlayInfo(
        _bvid,
        '42328985110',
        context: ApiRequestContext(cancellation: cancellation),
      ),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.cancelled,
        ),
      ),
    );
  });
  for (final code in [-101, -412, 62002]) {
    test(
      'authentication risk and deletion errors $code do not probe entitlement',
      () async {
        final transport = _Transport(access: _charging, play: {'code': code});
        final api = BiliApiClient(transport: transport);
        addTearDown(api.close);
        await expectLater(
          api.getPlayInfo(_bvid, '42328985110'),
          throwsA(isA<ApiFailure>()),
        );
        expect(transport.details, 0);
      },
    );
  }
}

const _dash = {
  'accept_quality': [32],
  'dash': {
    'duration': 504,
    'video': [
      {
        'id': 32,
        'base_url': 'https://cdn.example/video.m4s',
        'codecs': 'avc1.640028',
      },
    ],
    'audio': [
      {
        'id': 30280,
        'base_url': 'https://cdn.example/audio.m4s',
        'codecs': 'mp4a.40.2',
      },
    ],
  },
};

final class _Transport implements ApiTransport {
  _Transport({required this.access, this.play = const {}, this.onDetail});
  final Map<String, Object?> access, play;
  final void Function()? onDetail;
  int details = 0;

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    final video = {
      'aid': '117358337201563',
      'bvid': _bvid,
      'title': '测试视频',
      'pages': [
        {'cid': '42328985110', 'page': 1, 'part': 'P1'},
      ],
      ...access,
    };
    final Object data;
    var code = 0;
    switch (uri.path) {
      case '/x/web-interface/nav':
        data = {
          'wbi_img': {
            'img_url': 'https://i0.hdslb.com/bfs/wbi/${'a' * 32}.png',
            'sub_url': 'https://i0.hdslb.com/bfs/wbi/${'b' * 32}.png',
          },
        };
      case '/x/web-interface/view':
        details++;
        onDetail?.call();
        data = video;
      case '/x/web-interface/archive/related':
        data = [video];
      case '/x/v2/history/toview':
        data = {
          'list': [video],
        };
      case '/x/web-interface/wbi/search/type':
        data = {
          'result': [video],
          'numPages': 1,
          'numResults': 1,
        };
      case '/x/player/wbi/playurl':
        code = play['code'] as int? ?? 0;
        data = play;
      case '/x/space/wbi/arc/search':
        data = {
          'list': {
            'vlist': [video],
          },
          'page': {'count': 1},
        };
      default:
        throw StateError('Unexpected endpoint ${uri.path}');
    }
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': code, 'data': data}))),
      const {},
    );
  }
}
