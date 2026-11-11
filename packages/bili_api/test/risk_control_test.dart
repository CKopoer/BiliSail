import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  for (final device in [
    {'b_3': 'only-three'},
    {'b_3': 'three; SESSDATA=injected', 'b_4': 'four'},
  ]) {
    test(
      'invalid server device cannot become cookies: ${device.keys}',
      () async {
        final transport = _Transport((_, _) async => _json(data: device));
        final api = BiliApiClient(
          transport: transport,
          prepareWebRequests: true,
        );
        await expectLater(
          _read(api),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.category,
              'protocol',
              ApiFailureCategory.protocol,
            ),
          ),
        );
        expect(transport.reads, 1);
        expect(transport.activations, 0);
        expect(
          api.cookieJar.headerFor(Uri.https('api.bilibili.com', '/')),
          isNull,
        );
        api.close();
      },
    );
  }

  test('short device waiter deadline does not expire another waiter', () async {
    final started = Completer<void>();
    final pending = Completer<ApiHttpResponse>();
    final transport = _Transport((uri, _) async {
      if (uri.path.endsWith('/spi')) {
        started.complete();
        return pending.future;
      }
      return _json();
    });
    final api = BiliApiClient(transport: transport, prepareWebRequests: true);
    final assertion = expectLater(
      _read(
        api,
        context: ApiRequestContext(
          deadline: DateTime.now().add(const Duration(milliseconds: 50)),
        ),
      ),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'timeout',
          ApiFailureCategory.timeout,
        ),
      ),
    );
    await started.future;
    final other = _read(api);
    await assertion;
    pending.complete(_json(data: {'b_3': 'three', 'b_4': 'four'}));
    await other;
    expect(transport.reads, 2);
    expect(transport.activations, 1);
    api.close();
  });

  test(
    'server Base64 buvid4 is preserved in cookies and secure storage',
    () async {
      const buvid4 = 'Zml4dHVyZQ++/==';
      Map<String, String>? saved;
      final transport = _Transport((uri, headers) async {
        if (uri.path.endsWith('/spi')) {
          return _json(data: {'b_3': 'three', 'b_4': buvid4});
        }
        expect(headers['Cookie'], contains('buvid4=$buvid4'));
        return _json();
      });
      final api = BiliApiClient(
        transport: transport,
        prepareWebRequests: true,
        saveWebDevice: (value) async => saved = value,
      );
      await _read(api);
      expect(saved!['buvid4'], buvid4);
      expect(transport.activations, 1);
      api.close();
    },
  );

  test('closing the client cancels pending device preparation', () async {
    final started = Completer<void>();
    final pending = Completer<ApiHttpResponse>();
    final transport = _Transport((_, _) async {
      started.complete();
      return pending.future;
    });
    final api = BiliApiClient(transport: transport, prepareWebRequests: true);
    final assertion = expectLater(
      _read(api),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'cancelled',
          ApiFailureCategory.cancelled,
        ),
      ),
    );
    await started.future;
    api.close();
    await assertion;
    pending.complete(_json(data: {'b_3': 'three', 'b_4': 'four'}));
    expect(transport.activations, 0);
  });

  for (final code in [-352, -412, -509, -799]) {
    test(
      'business $code stops retries and preserves diagnostic code',
      () async {
        final transport = _Transport((_, _) async => _json(code: code));
        final api = BiliApiClient(transport: transport);
        await expectLater(
          _read(api),
          throwsA(_limited.having((e) => e.businessCode, 'code', code)),
        );
        expect(transport.reads, 1);
      },
    );
  }

  for (final code in [0, -403]) {
    for (final key in ['data', 'result']) {
      test('$code $key voucher is a challenge, never empty success', () async {
        final transport = _Transport(
          (_, _) async => _response({
            'code': code,
            key: {'v_voucher': 'fixture-sensitive-voucher'},
          }),
        );
        final api = BiliApiClient(transport: transport);
        await expectLater(
          api.requestWbiJson('/x/web-interface/wbi/search/type', {
            'keyword': 'test',
          }, 'search'),
          throwsA(
            _limited
                .having((e) => e.requiresVerification, 'verify', true)
                .having(
                  (e) => e.toString(),
                  'redacted',
                  isNot(contains('sensitive')),
                ),
          ),
        );
        expect(transport.reads, 2); // Public key, then search; no WBI refresh.
      });
    }
  }

  test(
    'HTML 412 cooldown ignores queries, expires, and isolates endpoints',
    () async {
      var now = DateTime.utc(2026, 11, 11);
      final transport = _Transport(
        (_, _) async => ApiHttpResponse(
          412,
          Uint8List.fromList(utf8.encode('<html>challenge</html>')),
          const {
            'retry-after': ['60'],
          },
        ),
      );
      final api = BiliApiClient(transport: transport, clock: () => now);
      await expectLater(
        _read(api),
        throwsA(
          _limited.having(
            (e) => e.retryAfter,
            'delay',
            const Duration(seconds: 60),
          ),
        ),
      );
      now = now.add(const Duration(seconds: 10));
      await expectLater(
        _read(api, query: 'different'),
        throwsA(
          _limited.having(
            (e) => e.retryAfter,
            'remaining',
            const Duration(seconds: 50),
          ),
        ),
      );
      expect(transport.reads, 1);
      await expectLater(_read(api, path: '/other'), throwsA(_limited));
      expect(transport.reads, 2);
      now = now.add(const Duration(seconds: 51));
      await expectLater(_read(api), throwsA(_limited));
      expect(transport.reads, 3);
    },
  );

  for (final raw in ['date', 'invalid', '-1', '0']) {
    test('Retry-After $raw is parsed safely', () async {
      final now = DateTime.utc(2026, 11, 11);
      final value = raw == 'date'
          ? HttpDate.format(now.add(const Duration(seconds: 45)))
          : raw;
      final api = BiliApiClient(
        clock: () => now,
        transport: _Transport(
          (_, _) async => _json(
            status: 429,
            headers: {
              'retry-after': [value],
            },
          ),
        ),
      );
      await expectLater(
        _read(api),
        throwsA(
          _limited.having(
            (e) => e.retryAfter,
            'delay',
            Duration(
              seconds: raw == 'date'
                  ? 45
                  : raw == '0'
                  ? 0
                  : 30,
            ),
          ),
        ),
      );
    });
  }

  test(
    'cancelled and old-session responses cannot establish a cooldown',
    () async {
      final session = _Session();
      final pending = Completer<ApiHttpResponse>();
      final transport = _Transport((_, _) => pending.future);
      final api = BiliApiClient(transport: transport, sessionProvider: session);
      final first = expectLater(
        _read(api),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'cancelled',
            ApiFailureCategory.cancelled,
          ),
        ),
      );
      session.sessionEpoch++;
      pending.complete(_json(code: -352));
      await first;
      await expectLater(_read(api), throwsA(_limited));
      expect(transport.reads, 2);
      session.sessionEpoch++;
      await expectLater(_read(api), throwsA(_limited));
      expect(transport.reads, 3);
    },
  );

  test('form writes are sent once, then obey the endpoint cooldown', () async {
    final transport = _Transport((_, _) async => _json());
    transport.mutation = _json(code: -352);
    final api = BiliApiClient(transport: transport);
    api.cookieJar.receive(Uri.https('api.bilibili.com', '/'), [
      'SESSDATA=fixture; Domain=.bilibili.com; Path=/; Secure',
      'bili_jct=fixture_csrf; Domain=.bilibili.com; Path=/; Secure',
    ]);
    Future<Object?> write() => api.submitForm(
      '/x/web-interface/archive/like',
      'like',
      {'aid': '1', 'like': '1'},
    );
    await expectLater(write(), throwsA(_limited));
    await expectLater(write(), throwsA(_limited));
    expect(transport.writes, 1);
  });

  test('App risk responses share classification without Web cookies', () async {
    final transport = _Transport((_, headers) async {
      expect(headers.containsKey('Cookie'), isFalse);
      return _json(status: 412);
    });
    final api = BiliApiClient(transport: transport, prepareWebRequests: true);
    await expectLater(
      api.requestAppJson(
        '/x/v2/feed/index',
        {},
        endpoint: 'app',
        buvid: 'a' * 32,
      ),
      throwsA(_limited),
    );
    expect(transport.reads, 1);
    expect(transport.writes, 0);
  });

  test('concurrent Web reads share device registration and reuse it', () async {
    final spi = Completer<ApiHttpResponse>();
    final started = Completer<void>();
    Map<String, String>? saved;
    final transport = _Transport((uri, headers) async {
      if (uri.path.endsWith('/spi')) {
        started.complete();
        return spi.future;
      }
      expect(headers['Cookie'], contains('buvid3=device-three'));
      expect(headers['Cookie'], contains('buvid4=device-four'));
      return _json();
    });
    final api = BiliApiClient(
      transport: transport,
      prepareWebRequests: true,
      saveWebDevice: (device) async => saved = device,
    );
    final cancellation = ApiCancellation();
    final first = expectLater(
      _read(api, context: ApiRequestContext(cancellation: cancellation)),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'cancelled',
          ApiFailureCategory.cancelled,
        ),
      ),
    );
    await started.future;
    final second = _read(api);
    cancellation.cancel();
    await first;
    spi.complete(_json(data: {'b_3': 'device-three', 'b_4': 'device-four'}));
    await second;
    await _read(api);
    expect(transport.reads, 3); // SPI plus two successful business reads.
    expect(transport.activations, 1);
    expect(saved!.keys, unorderedEquals(['buvid3', 'buvid4', 'b_nut']));
    expect(
      api.cookieJar.headerFor(Uri.https('api.live.bilibili.com', '/')),
      contains('buvid3=device-three'),
    );
    expect(api.cookieJar.headerFor(Uri.https('example.com', '/')), isNull);
    api.close();
  });

  test(
    'restored device avoids rotation; clearing cookies reactivates',
    () async {
      final transport = _Transport((_, headers) async {
        expect(headers['Cookie'], contains('buvid3=stable-three'));
        return _json();
      });
      final api = BiliApiClient(
        transport: transport,
        prepareWebRequests: true,
        loadWebDevice: () async => {
          'buvid3': 'stable-three',
          'buvid4': 'stable-four',
        },
      );
      await _read(api);
      api.cookieJar.clear();
      await _read(api);
      expect(transport.reads, 2);
      expect(transport.activations, 2);
      api.close();
    },
  );

  test(
    'device activation rejection does not send the business request',
    () async {
      final transport = _Transport(
        (_, _) async =>
            _json(data: {'b_3': 'device-three', 'b_4': 'device-four'}),
      );
      transport.mutation = _json(code: -352);
      final api = BiliApiClient(transport: transport, prepareWebRequests: true);
      await expectLater(_read(api), throwsA(_limited));
      expect(transport.reads, 1);
      expect(transport.activations, 1);
      expect(
        api.cookieJar.headerFor(Uri.https('api.bilibili.com', '/')),
        isNull,
      );
      api.close();
    },
  );

  test(
    'account change discards a late device flight and preserves new one',
    () async {
      final session = _Session();
      final old = Completer<ApiHttpResponse>();
      final started = Completer<void>();
      var spiReads = 0;
      final transport = _Transport((uri, _) async {
        if (uri.path.endsWith('/spi')) {
          if (++spiReads == 1) {
            started.complete();
            return old.future;
          }
          return _json(data: {'b_3': 'new-three', 'b_4': 'new-four'});
        }
        return _json();
      });
      final api = BiliApiClient(
        transport: transport,
        sessionProvider: session,
        prepareWebRequests: true,
      );
      final assertion = expectLater(
        _read(api),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'cancelled',
            ApiFailureCategory.cancelled,
          ),
        ),
      );
      await started.future;
      session.sessionEpoch++;
      api.cookieJar.clear();
      await _read(api);
      old.complete(_json(data: {'b_3': 'old-three', 'b_4': 'old-four'}));
      await assertion;
      await _read(api);
      expect(spiReads, 2);
      expect(transport.activations, 1);
      expect(
        api.cookieJar.headerFor(Uri.https('api.bilibili.com', '/')),
        allOf(contains('new-three'), isNot(contains('old-three'))),
      );
      api.close();
    },
  );
}

final _limited = isA<ApiFailure>().having(
  (e) => e.category,
  'category',
  ApiFailureCategory.rateLimited,
);
Future<Map<String, Object?>> _read(
  BiliApiClient api, {
  String path = '/fixture',
  String query = '',
  ApiRequestContext? context,
}) => api.requestJson(
  Uri.https('api.bilibili.com', path, {'q': query}),
  'fixture',
  context: context,
);

ApiHttpResponse _json({
  int code = 0,
  int status = 200,
  Object? data = const {},
  Map<String, List<String>> headers = const {},
}) => _response({'code': code, 'data': data}, status: status, headers: headers);
ApiHttpResponse _response(
  Object root, {
  int status = 200,
  Map<String, List<String>> headers = const {},
}) => ApiHttpResponse(
  status,
  Uint8List.fromList(utf8.encode(jsonEncode(root))),
  headers,
);

class _Session implements ApiSessionProvider {
  @override
  int sessionEpoch = 0;
}

class _Transport implements ApiTransport, ApiFormTransport, ApiJsonTransport {
  _Transport(this.respond);
  final Future<ApiHttpResponse> Function(Uri, Map<String, String>) respond;
  int reads = 0, writes = 0, activations = 0;
  ApiHttpResponse? mutation;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    reads++;
    if (uri.path == '/x/web-interface/nav') {
      return _json(
        data: {
          'wbi_img': {
            'img_url':
                'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
            'sub_url':
                'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
          },
        },
      );
    }
    return respond(uri, headers);
  }

  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    writes++;
    return mutation ?? _json();
  }

  @override
  Future<ApiHttpResponse> postJson(
    Uri uri, {
    required Map<String, Object?> body,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    activations++;
    expect(uri.path, '/x/internal/gaia-gateway/ExClimbWuzhi');
    expect(headers['Cookie'], contains('buvid3='));
    expect(
      jsonDecode(body['payload'] as String)['3c43']['adca'],
      Platform.operatingSystem,
    );
    return mutation ?? _json();
  }
}
