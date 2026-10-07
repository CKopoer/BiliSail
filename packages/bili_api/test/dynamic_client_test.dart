import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

ApiHttpResponse _response(Object? data, {int status = 200}) => ApiHttpResponse(
  status,
  Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
  const {},
);

void main() {
  const id = '9007199254740993123';
  BiliApiClient api(_Transport transport) => BiliApiClient(
    transport: transport,
    cookieJar: ApiCookieJar()
      ..receive(Uri.https('api.bilibili.com', '/'), [
        'SESSDATA=fixture; Path=/; Secure',
        'bili_jct=fixture-csrf; Path=/; Secure',
      ]),
  );

  test(
    'JSON writes preserve string identity, query CSRF and raw content',
    () async {
      final transport = _Transport();
      final client = DynamicClient(api(transport));
      await client.like(id, true);
      expect(transport.uri?.path, '/x/dynamic/feed/dyn/thumb');
      expect(transport.uri?.queryParameters, {'csrf': 'fixture-csrf'});
      expect(transport.jsonBody, {'dyn_id_str': id, 'up': 1});
      await client.like(id, false);
      expect(transport.jsonBody['up'], 2);
      transport.result = _response({'dyn_id_str': '9007199254740993124'});
      expect(await client.repost(id, '中文 &+=%/#'), '9007199254740993124');
      expect(transport.uri?.path, '/x/dynamic/feed/create/dyn');
      expect(transport.jsonBody['web_repost_src'], {'dyn_id_str': id});
      final request = transport.jsonBody['dyn_req'] as Map<String, Object?>;
      expect(request['scene'], 4);
      expect(request['content'], {
        'contents': [
          {'raw_text': '中文 &+=%/#', 'type': 1, 'biz_id': ''},
        ],
      });
      expect(transport.headers['Cookie'], contains('SESSDATA=fixture'));
      expect(transport.posts, 3);
      await client.repost(id, '');
      expect((transport.jsonBody['dyn_req'] as Map)['content'], {
        'contents': [
          {'raw_text': '转发动态', 'type': 1, 'biz_id': ''},
        ],
      });
    },
  );

  test(
    'missing credentials, invalid IDs/types and unsupported paths send nothing',
    () async {
      final transport = _Transport();
      final guest = BiliApiClient(transport: transport);
      await expectLater(
        DynamicClient(guest).like(id, true),
        throwsA(isA<ApiFailure>()),
      );
      await expectLater(
        DynamicClient(api(transport)).repost('1.2', 'text'),
        throwsArgumentError,
      );
      await expectLater(
        guest.getVideoComments(id, commentType: 99),
        throwsArgumentError,
      );
      expect(
        () => guest.submitDynamicJson('/unregistered', 'write', {}),
        throwsArgumentError,
      );
      expect(transport.posts, 0);
    },
  );

  test(
    'unknown writes make one attempt, and session changes discard late success',
    () async {
      final transport = _Transport()..result = _response(null, status: 503);
      final session = _Session();
      final clientApi = api(transport);
      await expectLater(
        DynamicClient(clientApi).repost(id, 'x'),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.posts, 1);
      transport.pending = Completer<ApiHttpResponse>();
      final scoped = BiliApiClient(
        transport: transport,
        cookieJar: clientApi.cookieJar,
        sessionProvider: session,
      );
      final pending = DynamicClient(
        scoped,
      ).like(id, true, context: ApiRequestContext(sessionEpoch: 1));
      await Future<void>.delayed(Duration.zero);
      session.epoch++;
      transport.pending!.complete(_response(null));
      await expectLater(
        pending,
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.cancelled,
          ),
        ),
      );
      expect(transport.posts, 2);
    },
  );

  test(
    'all comment operations retain the same non-video oid/type and reply hierarchy',
    () async {
      final transport = _Transport()
        ..result = _response({
          'reply': {
            'rpid_str': '51',
            'member': {'uname': 'fixture'},
            'content': {'message': 'reply'},
          },
        });
      final client = api(transport);
      for (final type in [11, 12, 14, 17, 33]) {
        await client.getVideoComments(id, commentType: type);
        expect(transport.gets.last.queryParameters['oid'], id);
        expect(transport.gets.last.queryParameters['type'], '$type');
        await client.getVideoReplies(id, '50', commentType: type);
        expect(transport.gets.last.queryParameters['root'], '50');
        expect(transport.gets.last.queryParameters['type'], '$type');
        await client.likeVideoComment(id, '50', true, commentType: type);
        expect(transport.fields['type'], '$type');
        await client.addVideoComment(
          id,
          'reply',
          rootId: '50',
          parentId: '51',
          commentType: type,
        );
        expect(transport.fields['oid'], id);
        expect(transport.fields['type'], '$type');
        expect(transport.fields['root'], '50');
        expect(transport.fields['parent'], '51');
      }
    },
  );

  test(
    'detail trusts the server comment identity and flags, even for opus draws',
    () async {
      final transport = _Transport();
      transport.getData = {
        'item': {
          'id_str': id,
          'type': 'DYNAMIC_TYPE_DRAW',
          'basic': {
            'comment_id_str': '9007199254740993125',
            'comment_type': 17,
            'rid_str': '55',
          },
          'modules': {
            'module_dynamic': {
              'major': {
                'opus': {
                  'summary': {'text': 'fixture'},
                },
              },
            },
            'module_stat': {
              'like': {'status': true, 'count': 3},
              'comment': {'forbidden': true},
              'forward': {'forbidden': true},
            },
          },
        },
      };
      final post = await DynamicClient(api(transport)).detail(id);
      expect(post.commentOid, '9007199254740993125');
      expect(post.commentType, 17);
      expect(post.liked, true);
      expect(post.commentForbidden, true);
      expect(post.repostForbidden, true);
      transport.getData = {
        'item': {'id_str': '10', 'type': 'DYNAMIC_TYPE_NONE'},
      };
      await expectLater(
        DynamicClient(api(transport)).detail(id),
        throwsA(isA<ApiFailure>()),
      );
    },
  );

  test(
    'Dio JSON encodes once and never follows credential-bearing redirects',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final bodies = <String>[];
      final subscription = server.listen((request) async {
        expect(request.headers.contentType?.mimeType, 'application/json');
        bodies.add(await utf8.decoder.bind(request).join());
        request.response.statusCode = 302;
        request.response.headers.set(
          'location',
          'http://127.0.0.1:${server.port}/redirect',
        );
        await request.response.close();
      });
      final transport = DioApiTransport();
      addTearDown(() async {
        transport.close();
        await subscription.cancel();
        await server.close(force: true);
      });
      final response = await transport.postJson(
        Uri.parse('http://127.0.0.1:${server.port}/post'),
        body: {'text': '中文 &+=%/#', 'id': id},
        headers: {},
        timeout: const Duration(seconds: 2),
      );
      expect(response.statusCode, 302);
      expect(bodies, hasLength(1));
      expect(jsonDecode(bodies.single), {'text': '中文 &+=%/#', 'id': id});
    },
  );
}

final class _Session implements ApiSessionProvider {
  int epoch = 1;
  @override
  int get sessionEpoch => epoch;
}

final class _Transport
    implements ApiTransport, ApiFormTransport, ApiJsonTransport {
  final gets = <Uri>[];
  int posts = 0;
  Uri? uri;
  Map<String, Object?> jsonBody = {};
  Map<String, String> fields = {}, headers = {};
  Object? getData = {
    'page': {'count': 0, 'size': 20},
    'replies': [],
  };
  ApiHttpResponse result = _response(null);
  Completer<ApiHttpResponse>? pending;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    gets.add(uri);
    return _response(getData);
  }

  @override
  Future<ApiHttpResponse> postJson(
    Uri uri, {
    required Map<String, Object?> body,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    posts++;
    this.uri = uri;
    jsonBody = body;
    this.headers = headers;
    return pending?.future ?? result;
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
    return result;
  }
}
