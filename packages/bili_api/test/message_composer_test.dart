import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

import 'message_client_test.dart' show cookies, message, response;

void main() {
  late _Transport transport;
  late BiliApiClient api;
  late MessageClient client;
  setUp(() {
    transport = _Transport();
    api = BiliApiClient(transport: transport, cookieJar: cookies());
    client = MessageClient(api);
  });

  test(
    'response and per-message emotes merge with safe URLs and recall isolation',
    () async {
      transport.data = {
        'e_infos': [
          {'text': '[doge]', 'url': '//i0.hdslb.com/doge.png', 'gif_url': ''},
          {'text': '[unsafe]', 'url': 'file:///private'},
        ],
        'messages': [
          {
            ...message(
              sequence: '1',
              content: jsonEncode({'content': '你好[doge][惊讶]'}),
            ),
            'extra': jsonEncode({
              'emoticon': {
                '[惊讶]': {'url': '//i0.hdslb.com/a.png'},
              },
            }),
          },
          message(sequence: '2', status: 1, content: '{private'),
        ],
        'has_more': 0,
      };
      final items = (await client.thread('123', 1)).items;
      expect(items.first.emotes.keys, ['[doge]', '[惊讶]']);
      expect(items.first.emotes['[doge]']?.scheme, 'https');
      expect(items.last.emotes, isEmpty);
      expect(() => items.first.emotes.clear(), throwsUnsupportedError);
    },
  );

  test(
    'reply identity uses source comment ID and preserves large exact IDs',
    () async {
      transport.data = {
        'items': [
          {
            'id': '19',
            'user': {'mid': '123', 'nickname': '用户'},
            'item': {
              'subject_id': '9007199254740993',
              'business_id': 1,
              'source_id': '9007199254740995',
              'target_id': '17',
              'root_id': '9007199254740994',
              'source_content': '回复[doge]',
              'emoticon': {
                '[doge]': {'url': '//i0.hdslb.com/doge.png'},
              },
            },
          },
        ],
        'cursor': {'id': 19, 'time': 0, 'is_end': true},
      };
      final row = (await client.notifications(
        ApiInboxSection.replies,
      )).items.single;
      expect(row.replyContext?.subjectId, '9007199254740993');
      expect(row.replyContext?.parentId, '9007199254740995');
      expect(row.replyContext?.rootId, '9007199254740994');
      expect(row.replyContext?.author, '用户');
      expect(row.emotes.keys, ['[doge]']);
    },
  );

  test(
    'rootless replies use source as root; missing source and hidden replies have no action',
    () async {
      for (final (extra, expected) in [
        (<String, Object?>{'source_id': '15', 'root_id': 0}, '15'),
        (<String, Object?>{'target_id': '15'}, null),
        (<String, Object?>{'source_id': '15', 'hide_reply_button': true}, null),
        (<String, Object?>{'source_id': 1.5}, null),
        (<String, Object?>{'source_id': '15', 'root_id': 1.5}, null),
        (<String, Object?>{'source_id': '15', 'business': '弹幕'}, null),
        (<String, Object?>{'source_id': '15', 'business_id': 999}, null),
      ]) {
        transport.data = {
          'items': [
            {
              'id': '19',
              'user': {'mid': '123'},
              'item': {'subject_id': '42', 'business_id': 1, ...extra},
            },
          ],
          'cursor': {'id': 19, 'time': 0, 'is_end': true},
        };
        final context = (await client.notifications(
          ApiInboxSection.replies,
        )).items.single.replyContext;
        expect(context?.rootId, expected);
      }
    },
  );

  test(
    'IM panel uses its own business and preserves text-only emotes',
    () async {
      transport.data = {
        'packages': [
          {
            'text': '默认',
            'emote': [
              {'text': '[doge]', 'type': 1, 'url': '//i0.hdslb.com/doge.png'},
              {
                'text': '(￣▽￣)',
                'type': 4,
                'url': '//i0.hdslb.com/not-used.png',
              },
            ],
          },
        ],
      };
      final packages = await client.emotes();
      expect(transport.uri?.queryParameters['business'], 'im');
      expect(packages.single.items.first.imageUrl?.scheme, 'https');
      expect(packages.single.items.last.imageUrl, isNull);
      await client.sendText('1', '2', '[doge] 中文 &+%');
      expect(jsonDecode(transport.fields['msg[content]']!), {
        'content': '[doge] 中文 &+%',
      });
    },
  );

  test(
    'private images upload with im business and destination CSRF then send type 2 once',
    () async {
      final picture = await api.uploadMessagePicture(
        Uint8List.fromList([1, 2, 3]),
        'image/png',
      );
      expect(transport.uri?.host, 'api.bilibili.com');
      expect(transport.uri?.path, '/x/dynamic/feed/draw/upload_bfs');
      expect(transport.fields, {'biz': 'im', 'csrf': 'csrf-fixture'});
      expect(transport.headers['Cookie'], contains('SESSDATA=fixture'));
      expect(transport.multipartCalls, 1);
      await client.sendImage('1', '2', picture, mimeType: 'image/png');
      expect(transport.uri?.host, 'api.vc.bilibili.com');
      expect(transport.fields['msg[msg_type]'], '2');
      expect(transport.fields['msg[receiver_id]'], '2');
      final content =
          jsonDecode(transport.fields['msg[content]']!) as Map<String, Object?>;
      expect(content['width'], 100);
      expect(content['height'], 50);
      expect(content['imageType'], 'png');
      expect(content['original'], 1);
      expect(content['size'], 3 / 1024);
      expect(transport.posts, 1);
    },
  );

  test(
    'image upload rejects invalid inputs, credentials, cancellation and untrusted response URLs',
    () async {
      for (final url in [
        'https://evil.example/a.png',
        'https://user@i0.hdslb.com/a.png',
        'https://i0.hdslb.com:8443/a.png',
        'https://i0.hdslb.com/a.png?token=private',
      ]) {
        transport.upload = response({
          'image_url': url,
          'image_width': 100,
          'image_height': 50,
        });
        await expectLater(
          api.uploadMessagePicture(Uint8List(3), 'image/png'),
          throwsA(isA<ApiFailure>()),
        );
      }
      final calls = transport.multipartCalls;
      await expectLater(
        api.uploadMessagePicture(Uint8List(0), 'image/png'),
        throwsArgumentError,
      );
      await expectLater(
        api.uploadMessagePicture(Uint8List(3), 'image/webp'),
        throwsArgumentError,
      );
      await expectLater(
        api.uploadMessagePicture(
          Uint8List(3),
          'image/png',
          context: ApiRequestContext(cancellation: ApiCancellation()..cancel()),
        ),
        throwsA(isA<ApiFailure>()),
      );
      await expectLater(
        BiliApiClient(
          transport: transport,
        ).uploadMessagePicture(Uint8List(3), 'image/png'),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.multipartCalls, calls);
    },
  );

  test('unknown upload and image-send results are never retried', () async {
    for (final status in [302, 503]) {
      transport.upload = response(null, status: status);
      await expectLater(
        api.uploadMessagePicture(Uint8List(3), 'image/png'),
        throwsA(isA<ApiFailure>()),
      );
    }
    expect(transport.multipartCalls, 2);
    transport.form = response(null, status: 503);
    await expectLater(
      client.sendImage(
        '1',
        '2',
        ApiCommentPicture(Uri.https('i0.hdslb.com', '/a.png'), 100, 50, 3),
        mimeType: 'image/png',
      ),
      throwsA(isA<ApiFailure>()),
    );
    expect(transport.posts, 1);
  });
}

final class _Transport
    implements ApiTransport, ApiFormTransport, ApiMultipartTransport {
  Object? data = const {};
  ApiHttpResponse upload = response({
    'image_url': 'https://i0.hdslb.com/a.png',
    'image_width': 100,
    'image_height': 50,
  });
  ApiHttpResponse form = response({});
  Uri? uri;
  Map<String, String> fields = {}, headers = {};
  int multipartCalls = 0, posts = 0;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    this.uri = uri;
    this.headers = headers;
    return response(data);
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
    return form;
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
    multipartCalls++;
    this.uri = uri;
    this.fields = fields;
    this.headers = headers;
    return upload;
  }
}
