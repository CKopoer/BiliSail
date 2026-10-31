import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test('danmaku form retains RGB and uses microsecond rnd values', () async {
    final adapter = _CaptureAdapter();
    final transport = DioApiTransport(dio: Dio()..httpClientAdapter = adapter);
    addTearDown(transport.close);
    final api = BiliApiClient(
      transport: transport,
      cookieJar: ApiCookieJar()
        ..receive(Uri.https('api.bilibili.com', '/'), [
          'SESSDATA=fixture-session; Path=/; Secure',
          'bili_jct=fixture-csrf; Path=/; Secure',
        ]),
    );
    var now = DateTime.utc(2026, 10, 31, 1, 2, 3, 123, 456);
    final client = VideoActionsClient(api, clock: () => now);
    final timestamps = <String>{};
    for (final mode in [1, 4, 5]) {
      for (final color in [0, 0xffffff, 0xff6699, 0xffd700, 0x00a1d6]) {
        final id = await client.sendDanmaku(
          'BV1234567890',
          '42',
          '中文 &+=%/#',
          const Duration(milliseconds: 12345),
          mode: mode,
          color: color,
        );
        final (options, body) = adapter.requests.last;
        final fields = Uri.splitQueryString(body);
        expect(options.uri, Uri.https('api.bilibili.com', '/x/v2/dm/post'));
        expect(options.method, 'POST');
        expect(options.contentType, Headers.formUrlEncodedContentType);
        expect(options.followRedirects, isFalse);
        expect(fields, {
          'bvid': 'BV1234567890',
          'oid': '42',
          'type': '1',
          'msg': '中文 &+=%/#',
          'progress': '12345',
          'mode': '$mode',
          'color': '$color',
          'fontsize': '25',
          'pool': '0',
          'plat': '1',
          'rnd': '${now.microsecondsSinceEpoch}',
          'csrf': 'fixture-csrf',
        });
        expect(id, '9007199254740993');
        expect(timestamps.add(fields['rnd']!), isTrue);
        now = now.add(const Duration(microseconds: 1));
      }
    }
    expect(adapter.requests, hasLength(15));
  });
}

final class _CaptureAdapter implements HttpClientAdapter {
  final requests = <(RequestOptions, String)>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = BytesBuilder(copy: false);
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.add(chunk);
      }
    }
    requests.add((options, utf8.decode(bytes.takeBytes())));
    return ResponseBody.fromString(
      '{"code":0,"data":{"dmid_str":"9007199254740993"}}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
