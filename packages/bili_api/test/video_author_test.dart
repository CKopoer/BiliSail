import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  test(
    'author totals use the matching MID and preserve missing counts',
    () async {
      final transport = _Transport();
      final client = VideoAuthorClient(BiliApiClient(transport: transport));
      final author = await client.load('9007199254740993');
      expect(transport.uri?.path, '/x/web-interface/card');
      expect(transport.uri?.queryParameters, {'mid': '9007199254740993'});
      expect(author.mid, '9007199254740993');
      expect(author.followerCount, 70700);
      expect(author.likeCount, 214000);
      expect(author.following, true);
      transport.data.remove('like_num');
      transport.data['follower'] = -1;
      final missing = await client.load('9007199254740993');
      expect(missing.likeCount, isNull);
      expect(missing.followerCount, isNull);
      transport.data['card'] = {'mid': '2'};
      await expectLater(
        client.load('9007199254740993'),
        throwsA(isA<ApiFailure>()),
      );
    },
  );

  test('missing relationship is not treated as not followed', () async {
    final transport = _Transport()..data.remove('following');
    await expectLater(
      VideoAuthorClient(
        BiliApiClient(transport: transport),
      ).load('9007199254740993'),
      throwsA(isA<ApiFailure>()),
    );
  });

  test('follow and unfollow use scoped CSRF and a single POST', () async {
    final transport = _Transport();
    final jar = ApiCookieJar()
      ..receive(Uri.https('api.bilibili.com', '/'), [
        'SESSDATA=fixture; Path=/; Secure',
        'bili_jct=fixture-csrf; Path=/; Secure',
      ]);
    final client = VideoAuthorClient(
      BiliApiClient(transport: transport, cookieJar: jar),
    );
    await client.follow('9007199254740993', true);
    expect(transport.uri?.path, '/x/relation/modify');
    expect(transport.fields, {
      'fid': '9007199254740993',
      'act': '1',
      're_src': '14',
      'csrf': 'fixture-csrf',
    });
    await client.follow('9007199254740993', false);
    expect(transport.fields['act'], '2');
    transport.status = 503;
    await expectLater(
      client.follow('9007199254740993', true),
      throwsA(isA<ApiFailure>()),
    );
    expect(transport.posts, 3);
    final guest = VideoAuthorClient(BiliApiClient(transport: transport));
    await expectLater(
      guest.follow('9007199254740993', true),
      throwsA(isA<ApiFailure>()),
    );
    expect(transport.posts, 3);
  });

  test('session change discards late author data', () async {
    final session = _Session();
    final transport = _Transport()..pending = Completer<void>();
    final client = VideoAuthorClient(
      BiliApiClient(transport: transport, sessionProvider: session),
    );
    final future = client.load('9007199254740993');
    session.epoch++;
    transport.pending!.complete();
    await expectLater(
      future,
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.cancelled,
        ),
      ),
    );
  });
}

final class _Session implements ApiSessionProvider {
  int epoch = 0;
  @override
  int get sessionEpoch => epoch;
}

final class _Transport implements ApiTransport, ApiFormTransport {
  Uri? uri;
  Map<String, String> fields = {};
  int posts = 0, status = 200;
  Completer<void>? pending;
  final Map<String, Object?> data = {
    'card': {'mid': '9007199254740993'},
    'following': true,
    'follower': 70700,
    'like_num': '214000',
  };
  ApiHttpResponse response(Object? value) => ApiHttpResponse(
    status,
    Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': value}))),
    {},
  );
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    this.uri = uri;
    await pending?.future;
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
    this.uri = uri;
    this.fields = fields;
    posts++;
    return response(null);
  }
}
