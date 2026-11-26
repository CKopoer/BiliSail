import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

const _first = 'BV1YdZtYHE6d';
const _second = 'BV1xx411c7mD';
const _unknown = 'BV1234567890';

void main() {
  test(
    'requests distinct BV IDs without Web credentials and matches by BVID',
    () async {
      final transport = _Transport({
        'av1': {'bvid': _first, 'cover43': '//i0.hdslb.com/43.jpg'},
        _second: {
          'bvid': _second,
          'cover43': 'https:/broken.jpg',
          'pic': 'ordinary',
        },
        _unknown: {
          'bvid': _unknown,
          'cover43': 'https://i1.hdslb.com/other.jpg',
        },
      });
      final api = BiliApiClient(transport: transport, prepareWebRequests: true);
      addTearDown(api.close);
      api.cookieJar.receive(Uri.https('api.bilibili.com', '/'), [
        'SESSDATA=fixture; Secure; Path=/',
      ]);
      expect(await api.getVideoCover43Urls([_first, _first, _second]), {
        _first: Uri.parse('https://i0.hdslb.com/43.jpg'),
      });
      expect(
        transport.requests.single,
        Uri.https('api.bilibili.com', '/x/article/cards', {
          'ids': '$_first,$_second',
        }),
      );
      expect(transport.headers.single['Referer'], 'https://www.bilibili.com/');
      expect(transport.headers.single, isNot(contains('Cookie')));
    },
  );

  test(
    'skips empty work, rejects invalid batches and does not retry failures',
    () async {
      final transport = _Transport(null, status: 503);
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      expect(await api.getVideoCover43Urls([]), isEmpty);
      await expectLater(api.getVideoCover43Urls(['av2']), throwsArgumentError);
      await expectLater(
        api.getVideoCover43Urls([
          for (var index = 1; index <= 31; index++)
            'BV${index.toString().padLeft(10, '0')}',
        ]),
        throwsArgumentError,
      );
      expect(transport.requests, isEmpty);
      await expectLater(
        api.getVideoCover43Urls([_first]),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.requests, hasLength(1));
    },
  );
}

final class _Transport implements ApiTransport {
  _Transport(this.data, {this.status = 200});

  final Object? data;
  final int status;
  final requests = <Uri>[];
  final headers = <Map<String, String>>[];

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    requests.add(uri);
    this.headers.add(headers);
    return ApiHttpResponse(
      status,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
      const {},
    );
  }
}
