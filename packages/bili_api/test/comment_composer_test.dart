import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

ApiHttpResponse response(Object? data, {int status = 200}) => ApiHttpResponse(
  status,
  Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
  const {},
);

void main() {
  late _Transport transport;
  late BiliApiClient api;
  setUp(() {
    transport = _Transport();
    api = BiliApiClient(
      transport: transport,
      cookieJar: ApiCookieJar()
        ..receive(Uri.https('api.bilibili.com', '/'), [
          'SESSDATA=fixture; Path=/; Secure',
          'bili_jct=fixture-csrf; Path=/; Secure',
        ]),
    );
  });
  test(
    'all comment identities preserve image, mention, sync and raw text fields',
    () async {
      final picture = ApiCommentPicture(
        Uri.parse('https://i0.hdslb.com/bfs/new_dyn/a.png'),
        10,
        20,
        3,
      );
      for (final type in [1, 11, 12, 14, 17, 33]) {
        await api.addVideoComment(
          '9007199254740993',
          '@读者 中文 &+=%/#',
          commentType: type,
          pictures: [picture],
          mentions: {'读者': '9007199254740993'},
          syncToDynamic: true,
        );
        expect(transport.fields['oid'], '9007199254740993');
        expect(transport.fields['type'], '$type');
        expect(transport.fields['message'], '@读者 中文 &+=%/#');
        expect(jsonDecode(transport.fields['pictures']!), [picture.toJson()]);
        expect(transport.fields['at_name_to_mid'], '{"读者":9007199254740993}');
        expect(transport.fields['sync_to_dynamic'], '1');
        expect(transport.fields['csrf'], 'fixture-csrf');
      }
      await api.addVideoComment('42', '', pictures: [picture]);
      expect(transport.fields.containsKey('sync_to_dynamic'), false);
      expect(transport.fields.containsKey('at_name_to_mid'), false);
      await expectLater(
        api.addVideoComment('42', '回复', rootId: '10', pictures: [picture]),
        throwsArgumentError,
      );
      await expectLater(
        api.addVideoComment('42', 'x', pictures: List.filled(10, picture)),
        throwsArgumentError,
      );
      expect(transport.posts, 7);
    },
  );

  test(
    'mention search decodes deduplicated groups without losing long IDs',
    () async {
      final users = await api.searchCommentMentions('读者 &+');
      expect(users.single.mid, '9007199254740993');
      expect(users.single.name, '读者');
      expect(transport.uri?.queryParameters['keyword'], '读者 &+');
      expect(transport.uri?.path, '/x/polymer/web-dynamic/v1/mention/search');
    },
  );

  test(
    'uploads use authenticated multipart metadata and validate the returned CDN image',
    () async {
      final picture = await api.uploadCommentPicture(
        Uint8List.fromList([1, 2, 3]),
        'image/png',
      );
      expect(picture.width, 10);
      expect(picture.height, 20);
      expect(transport.uri?.path, '/x/dynamic/feed/draw/upload_bfs');
      expect(transport.fields, {
        'category': 'daily',
        'biz': 'new_dyn',
        'csrf': 'fixture-csrf',
      });
      expect(transport.headers['Cookie'], contains('SESSDATA=fixture'));
      transport.uploadResponse = response({
        'image_url': 'https://invalid.example/a.png',
        'image_width': 10,
        'image_height': 20,
      });
      await expectLater(
        api.uploadCommentPicture(Uint8List(3), 'image/png'),
        throwsA(isA<ApiFailure>()),
      );
    },
  );

  test(
    'guest, cancelled and invalid uploads make no transport request',
    () async {
      final guest = BiliApiClient(transport: transport);
      await expectLater(
        guest.uploadCommentPicture(Uint8List(3), 'image/png'),
        throwsA(isA<ApiFailure>()),
      );
      await expectLater(
        api.uploadCommentPicture(Uint8List(0), 'image/png'),
        throwsArgumentError,
      );
      final cancellation = ApiCancellation()..cancel();
      await expectLater(
        api.uploadCommentPicture(
          Uint8List(3),
          'image/png',
          context: ApiRequestContext(cancellation: cancellation),
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.posts, 0);
    },
  );

  test('upload failures and redirects are single attempts', () async {
    for (final status in [302, 503]) {
      transport.uploadResponse = response(null, status: status);
      await expectLater(
        api.uploadCommentPicture(Uint8List(3), 'image/png'),
        throwsA(isA<ApiFailure>()),
      );
    }
    expect(transport.posts, 2);
  });

  test(
    'Dio serializes multipart with one file and does not follow redirects',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final dio = DioApiTransport();
      addTearDown(() async {
        dio.close();
        await server.close(force: true);
      });
      var posts = 0;
      final requestBody = Completer<String>();
      server.listen((request) async {
        posts++;
        final body = await utf8.decoder.bind(request).join();
        requestBody.complete(body);
        expect(request.headers.contentType?.mimeType, 'multipart/form-data');
        request.response.statusCode = 302;
        request.response.headers.set('location', '/redirect');
        await request.response.close();
      });
      final result = await dio.postMultipart(
        Uri.parse('http://127.0.0.1:${server.port}/upload'),
        fields: {'csrf': 'fixture'},
        bytes: Uint8List.fromList([65, 66]),
        mimeType: 'image/png',
        headers: {},
        timeout: const Duration(seconds: 3),
      );
      expect(result.statusCode, 302);
      final body = await requestBody.future;
      expect(body, contains('name="file_up"; filename="comment.png"'));
      expect(body, contains('content-type: image/png'));
      expect(body, contains('name="csrf"'));
      expect(posts, 1);
    },
  );
}

class _Transport
    implements ApiTransport, ApiFormTransport, ApiMultipartTransport {
  int posts = 0;
  Uri? uri;
  Map<String, String> fields = {}, headers = {};
  ApiHttpResponse uploadResponse = response({
    'image_url': 'https://i0.hdslb.com/bfs/new_dyn/a.png',
    'image_width': 10,
    'image_height': 20,
  });
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    this.uri = uri;
    return response({
      'groups': [
        {
          'items': [
            {'uid': '9007199254740993', 'name': '读者'},
          ],
        },
        {
          'items': [
            {'uid': '9007199254740993', 'name': '读者'},
          ],
        },
      ],
    });
  }

  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    posts++;
    this.uri = uri;
    this.fields = fields;
    this.headers = headers;
    return response({
      'reply': {
        'rpid': '10',
        'content': {
          'message': fields['message'],
          if (fields['pictures'] case final String pictures)
            'pictures': jsonDecode(pictures),
        },
        'member': {'uname': '我'},
      },
    });
  }

  @override
  Future<ApiHttpResponse> postMultipart(
    Uri uri, {
    required Map<String, String> fields,
    required Uint8List bytes,
    required String mimeType,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    posts++;
    this.uri = uri;
    this.fields = fields;
    this.headers = headers;
    return uploadResponse;
  }
}
