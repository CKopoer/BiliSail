import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  test('field 24 preserves known and unknown effects without changing RGB', () {
    for (final effect in [0, 60001, 60002]) {
      final element = [
        8,
        1,
        24,
        1,
        40,
        ..._varint(0x123456),
        58,
        1,
        65,
        ..._varint(24 << 3),
        ..._varint(effect),
      ];
      final decoded = decodeDanmakuSegment(
        Uint8List.fromList([10, ..._varint(element.length), ...element]),
      ).single;
      expect(decoded.color, 0x123456);
      expect(decoded.colorful, effect);
    }
    expect(
      decodeDanmakuSegment(
        Uint8List.fromList([10, 7, 8, 1, 24, 1, 58, 1, 65]),
      ).single.colorful,
      0,
    );
  });

  test(
    'member sends force white RGB and carry colorful only when requested',
    () async {
      final transport = _Transport();
      final api = BiliApiClient(
        transport: transport,
        cookieJar: ApiCookieJar()
          ..receive(Uri.https('api.bilibili.com', '/'), [
            'SESSDATA=fixture; Path=/; Secure',
            'bili_jct=fixture; Path=/; Secure',
          ]),
      );
      final client = VideoActionsClient(api);
      for (final mode in [1, 4, 5]) {
        await client.sendDanmaku(
          'BV1234567890',
          '42',
          'member',
          Duration.zero,
          mode: mode,
          color: 0x123456,
          colorful: true,
        );
        expect(transport.forms.last['color'], '16777215');
        expect(transport.forms.last['colorful'], '60001');
      }
      await client.sendDanmaku(
        'BV1234567890',
        '42',
        'plain',
        Duration.zero,
        color: 1,
      );
      expect(transport.forms.last['color'], '1');
      expect(transport.forms.last.containsKey('colorful'), isFalse);
      expect(transport.forms, hasLength(4));
    },
  );

  test(
    'nav membership uses current server status and defaults to unavailable',
    () async {
      final transport = _Transport();
      final api = BiliApiClient(transport: transport);
      for (final (data, expected) in <(Map<String, Object?>, bool)>[
        ({'vipStatus': 1}, true),
        ({'vipStatus': 0}, false),
        (
          {
            'vipStatus': 0,
            'vip': {'status': 1},
          },
          false,
        ),
        (
          {
            'vip': {'status': 1},
          },
          true,
        ),
        ({}, false),
      ]) {
        transport.nav = {'isLogin': true, 'mid': 1, ...data};
        expect((await api.getNav()).isVip, expected);
      }
    },
  );
}

List<int> _varint(int value) {
  final bytes = <int>[];
  while (value >= 128) {
    bytes.add((value & 127) | 128);
    value >>= 7;
  }
  return [...bytes, value];
}

final class _Transport implements ApiTransport, ApiFormTransport {
  final forms = <Map<String, String>>[];
  Map<String, Object?> nav = {};
  ApiHttpResponse _response(Object data) => ApiHttpResponse(
    200,
    Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
    const {},
  );
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async => _response(nav);
  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    forms.add(Map.of(fields));
    return _response({'dmid_str': '9007199254740993'});
  }
}
