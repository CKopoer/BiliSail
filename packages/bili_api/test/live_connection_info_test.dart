import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

const nav = {
  'code': -101,
  'data': {
    'wbi_img': {
      'img_url': 'https://i0.hdslb.com/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png',
      'sub_url': 'https://i0.hdslb.com/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.png',
    },
  },
};
const discovery = {
  'code': 0,
  'data': {
    'token': 'fixture-key',
    'host_list': [
      {'host': 'fixture.chat.bilibili.com', 'wss_port': 2245},
      {'host': 'outside.example', 'wss_port': 443},
    ],
  },
};

final class _Transport implements ApiTransport {
  _Transport({this.cancelFirstPath, this.navGate});
  final String? cancelFirstPath;
  final Future<void>? navGate;
  final calls = <String, int>{};
  final headers = <Uri, Map<String, String>>{};
  bool malformed = false;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    this.headers[uri] = headers;
    final count = calls.update(uri.path, (v) => v + 1, ifAbsent: () => 1);
    if (uri.path == cancelFirstPath && count == 1) {
      await cancellation?.whenCancelled;
      throw const ApiFailure(ApiFailureCategory.cancelled, 'fixture');
    }
    if (uri.path == '/x/web-interface/nav') await navGate;
    final Object value = switch (uri.path) {
      '/x/frontend/finger/spi' => {
        'code': 0,
        'data': {'b_3': 'fixture-device'},
      },
      '/x/web-interface/nav' => nav,
      '/xlive/web-room/v1/index/getDanmuInfo' =>
        malformed
            ? {
                'code': 0,
                'data': {
                  'token': 'fixture-key',
                  'host_list': [
                    {'host': 'outside.example', 'wss_port': 443},
                  ],
                },
              }
            : discovery,
      '/xlive/web-room/v1/dM/gethistory' => {
        'code': 0,
        'data': {
          'room': [
            {
              'nickname': '观众',
              'text': '脱敏文本',
              'timeline': '2026-10-05 20:00:00',
            },
          ],
        },
      },
      _ => throw StateError('Unexpected endpoint'),
    };
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode(value))),
      const {},
    );
  }
}

Future<void> until(bool Function() test) async {
  while (!test()) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'Web discovery signs query and uses stable scoped device and user ID',
    () async {
      final transport = _Transport();
      final api = BiliApiClient(transport: transport);
      api.cookieJar.receive(Uri.https('api.bilibili.com', '/'), [
        'DedeUserID=9007199254740993; Domain=.bilibili.com; Path=/; Secure',
      ]);
      final client = LiveClient(api);
      final info = await client.getConnectionInfo('12');
      expect(info.userId, '9007199254740993');
      expect(info.buvid, 'fixture-device');
      expect(info.hosts.single.port, 2245);
      final requested = transport.headers.keys.firstWhere(
        (u) => u.path.endsWith('getDanmuInfo'),
      );
      expect(requested.host, 'api.live.bilibili.com');
      expect(requested.queryParameters['w_rid'], hasLength(32));
      expect(requested.queryParameters['wts'], isNotNull);
      expect(
        transport.headers[requested]?['Cookie'],
        contains('buvid3=fixture-device'),
      );
      await client.getConnectionInfo('13');
      expect(transport.calls['/x/frontend/finger/spi'], 1);
      expect(transport.calls['/x/web-interface/nav'], 1);
    },
  );
  test(
    'caller cancelling shared device producer does not cancel valid new room',
    () async {
      final transport = _Transport(cancelFirstPath: '/x/frontend/finger/spi');
      final client = LiveClient(BiliApiClient(transport: transport));
      final oldSignal = ApiCancellation(), newSignal = ApiCancellation();
      final old = client.getConnectionInfo(
        '12',
        context: ApiRequestContext(cancellation: oldSignal),
      );
      final oldResult = expectLater(
        old,
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.cancelled,
          ),
        ),
      );
      await until(() => transport.calls['/x/frontend/finger/spi'] == 1);
      final fresh = client.getConnectionInfo(
        '13',
        context: ApiRequestContext(cancellation: newSignal),
      );
      oldSignal.cancel();
      await oldResult;
      expect((await fresh).roomId, '13');
      expect(transport.calls['/x/frontend/finger/spi'], 2);
    },
  );
  test(
    'cancelled room read leaves shared WBI nav available to the current room',
    () async {
      final navGate = Completer<void>();
      final transport = _Transport(navGate: navGate.future);
      final api = BiliApiClient(transport: transport);
      api.cookieJar.receive(Uri.https('api.bilibili.com', '/'), [
        'buvid3=fixture-device; Domain=.bilibili.com; Path=/; Secure',
      ]);
      final client = LiveClient(api);
      final oldSignal = ApiCancellation(), newSignal = ApiCancellation();
      final old = client.getConnectionInfo(
        '12',
        context: ApiRequestContext(cancellation: oldSignal),
      );
      final oldResult = expectLater(
        old,
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.cancelled,
          ),
        ),
      );
      await until(() => transport.calls['/x/web-interface/nav'] == 1);
      final fresh = client.getConnectionInfo(
        '13',
        context: ApiRequestContext(cancellation: newSignal),
      );
      oldSignal.cancel();
      await oldResult;
      navGate.complete();
      expect((await fresh).roomId, '13');
      expect(transport.calls['/x/web-interface/nav'], 1);
    },
  );
  test('no trusted candidate is protocol failure', () async {
    final transport = _Transport()..malformed = true;
    expect(
      LiveClient(BiliApiClient(transport: transport)).getConnectionInfo('12'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.protocol,
        ),
      ),
    );
  });
  test(
    'history Beijing wall time becomes UTC on every host timezone',
    () async {
      final messages = await LiveClient(
        BiliApiClient(transport: _Transport()),
      ).getChatHistory('12');
      expect(messages.single.timestamp, DateTime.utc(2026, 10, 5, 12));
    },
  );
}
