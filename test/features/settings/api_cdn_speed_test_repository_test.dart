import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/settings/data/api_cdn_speed_test_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ApiRequests requests;
  late BiliApiClient api;
  late ApiCdnSpeedTestRepository repository;
  late HttpServer server;
  late Uri url;
  setUp(() async {
    requests = ApiRequests();
    api = BiliApiClient(transport: _Transport(), sessionProvider: requests);
    repository = ApiCdnSpeedTestRepository(api, requests);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = Uri.parse('http://127.0.0.1:${server.port}/video?key=fixture');
  });
  tearDown(() async {
    api.close();
    await server.close(force: true);
  });
  final cancelled = isA<AppFailure>().having(
    (error) => error.kind,
    'kind',
    AppFailureKind.cancelled,
  );

  test(
    'sample uses the existing video-only profile and carries the current epoch',
    () async {
      requests.advanceSession();
      final sample = await repository.loadSample(
        cancellation: RequestCancellation(),
      );
      expect(sample.sessionEpoch, 1);
      expect(sample.urls.map((url) => url.host), [
        'upos-sz-mirrorhw.bilivideo.com',
      ]);
      expect(() => sample.urls.clear(), throwsUnsupportedError);
    },
  );

  test(
    'bounds a server ignoring Range; public probes never send credentials',
    () async {
      final headers = Completer<HttpHeaders>();
      server.listen((request) async {
        headers.complete(request.headers);
        request.response.headers.contentType = ContentType.binary;
        request.response.add(Uint8List(2 * ApiCdnSpeedTestRepository.maxBytes));
        await request.response.close();
      });
      final result = await repository.measure(
        url,
        sessionEpoch: 0,
        cancellation: RequestCancellation(),
      );
      expect(result.bytes, ApiCdnSpeedTestRepository.maxBytes);
      expect(result.mebibytesPerSecond, greaterThan(0));
      final sent = await headers.future;
      expect(sent.value(HttpHeaders.rangeHeader), 'bytes=0-1048575');
      expect(sent.value(HttpHeaders.cookieHeader), isNull);
      expect(sent.value(HttpHeaders.authorizationHeader), isNull);
      expect(
        sent.value(HttpHeaders.refererHeader),
        'https://www.bilibili.com/',
      );
    },
  );

  for (final mode in ['range', 'forbidden', 'empty', 'badRange', 'html']) {
    test('classifies $mode without leaking the signed address', () async {
      server.listen((request) async {
        request.response.headers.contentType = ContentType.binary;
        if (mode == 'forbidden') {
          request.response.statusCode = 403;
        } else if (mode == 'html') {
          request.response.headers.contentType = ContentType.html;
          request.response.write('<html>fixture</html>');
        } else if (mode != 'empty') {
          request.response.statusCode = 206;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            mode == 'badRange' ? 'bytes 4-7/8' : 'bytes 0-7/8',
          );
          request.response.add(Uint8List(8));
        }
        await request.response.close();
      });
      final future = repository.measure(
        url,
        sessionEpoch: 0,
        cancellation: RequestCancellation(),
      );
      if (mode == 'range') {
        expect((await future).bytes, 8);
      } else {
        await expectLater(
          future,
          throwsA(
            isA<AppFailure>().having(
              (error) => error.message,
              'safe message',
              isNot(contains('fixture')),
            ),
          ),
        );
      }
    });
  }

  test('redirects have a fixed budget and retain no server cookies', () async {
    var count = 0;
    server.listen((request) async {
      count++;
      expect(request.headers.value(HttpHeaders.cookieHeader), isNull);
      request.response
        ..statusCode = 302
        ..headers.set(HttpHeaders.locationHeader, '/redirect')
        ..cookies.add(Cookie('private', 'fixture'));
      await request.response.close();
    });
    await expectLater(
      repository.measure(
        url,
        sessionEpoch: 0,
        cancellation: RequestCancellation(),
      ),
      throwsA(isA<AppFailure>()),
    );
    expect(count, 4);
  });

  for (final accountChange in [false, true]) {
    test(
      'cancels stalled response on ${accountChange ? 'account change' : 'dialog close'}',
      () async {
        final received = Completer<void>();
        server.listen((request) => received.complete());
        final signal = RequestCancellation();
        final operation = repository.measure(
          url,
          sessionEpoch: 0,
          cancellation: signal,
        );
        final assertion = expectLater(operation, throwsA(cancelled));
        await received.future;
        if (accountChange) {
          requests.advanceSession();
        } else {
          signal.cancel();
        }
        await assertion.timeout(const Duration(seconds: 1));
        if (accountChange) {
          await expectLater(
            repository.measure(
              url,
              sessionEpoch: 0,
              cancellation: RequestCancellation(),
            ),
            throwsA(cancelled),
          );
        }
      },
    );
  }

  for (final partial in [false, true]) {
    test(
      'the total deadline also covers a stalled ${partial ? 'body' : 'header'}',
      () async {
        repository = ApiCdnSpeedTestRepository(
          api,
          requests,
          probeTimeout: const Duration(milliseconds: 500),
        );
        server.listen((request) async {
          if (partial) {
            request.response.headers.contentType = ContentType.binary;
            request.response.bufferOutput = false;
            request.response.add(Uint8List(256));
            await request.response.flush();
          }
        });
        final operation = repository.measure(
          url,
          sessionEpoch: 0,
          cancellation: RequestCancellation(),
        );
        if (partial) {
          expect((await operation).bytes, 256);
        } else {
          await expectLater(
            operation,
            throwsA(
              isA<AppFailure>().having(
                (error) => error.kind,
                'kind',
                AppFailureKind.timeout,
              ),
            ),
          );
        }
      },
    );
  }
}

final class _Transport implements ApiTransport {
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    final nav = uri.path.endsWith('/nav');
    if (!nav) {
      expect(uri.path, '/x/player/wbi/playurl');
      expect(uri.queryParameters['qn'], '32');
    }
    final data = nav
        ? {
            'wbi_img': {
              'img_url': 'https://i0.hdslb.com/${'a' * 32}.png',
              'sub_url': 'https://i0.hdslb.com/${'b' * 32}.png',
            },
          }
        : {
            'accept_quality': [32],
            'dash': {
              'duration': 20,
              'video': [
                {
                  'id': 32,
                  'codecs': 'avc1.640028',
                  'base_url': 'https://upos-sz-mirrorhw.bilivideo.com/upgcxcode/v.m4s?key=fixture',
                },
              ],
            },
          };
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
      const {},
    );
  }
}
