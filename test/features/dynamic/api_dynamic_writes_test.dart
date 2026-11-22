import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/comment_target.dart';
import 'package:bilisail/domain/dynamic_post.dart' show DynamicPost;
import 'package:bilisail/domain/local_image.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/dynamic/data/api_dynamic_composer_repository.dart';
import 'package:bilisail/features/dynamic/data/api_dynamic_repository.dart';
import 'package:bilisail/features/dynamic/data/api_dynamic_topic_repository.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_repository.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_draft.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/dynamic_reservation_fakes.dart';

class _Transport
    implements
        ApiTransport,
        ApiFormTransport,
        ApiJsonTransport,
        ApiMultipartTransport {
  int status = 503, code = 0, posts = 0;
  Completer<ApiHttpResponse>? pending;
  Map<String, Object?>? json;
  Map<String, String>? form;
  Uri? formUri;
  bool hasWbiKeys = true;
  Object? data = const {'dyn_id_str': '123'};
  Future<ApiHttpResponse> result() async {
    posts++;
    return pending?.future ??
        ApiHttpResponse(
          status,
          Uint8List.fromList(
            utf8.encode(jsonEncode({'code': code, 'data': data})),
          ),
          {},
        );
  }

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    expect(uri.path, '/x/web-interface/nav');
    return ApiHttpResponse(
      200,
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'code': 0,
            'data': {
              if (hasWbiKeys)
                'wbi_img': {
                  'img_url': 'https://i0.hdslb.com/bfs/wbi/${'a' * 32}.png',
                  'sub_url': 'https://i0.hdslb.com/bfs/wbi/${'b' * 32}.png',
                },
            },
          }),
        ),
      ),
      const {},
    );
  }

  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) {
    form = fields;
    formUri = uri;
    return result();
  }

  @override
  Future<ApiHttpResponse> postJson(
    Uri uri, {
    required Map<String, Object?> body,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) {
    json = body;
    return result();
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
  }) => result();
}

void main() {
  late _Transport transport;
  late ApiRequests requests;
  late ApiDynamicComposerRepository composer;
  late ApiDynamicTopicRepository topic;
  setUp(() {
    transport = _Transport();
    requests = ApiRequests();
    final api = BiliApiClient(
      transport: transport,
      sessionProvider: requests,
      cookieJar: ApiCookieJar()
        ..receive(Uri.https('api.bilibili.com', '/'), [
          'SESSDATA=fixture; Domain=.bilibili.com; Path=/; Secure',
          'bili_jct=fixture; Domain=.bilibili.com; Path=/; Secure',
        ]),
    );
    composer = ApiDynamicComposerRepository(
      DynamicPublishClient(api),
      requests,
      accountScope: () => 'user:7',
    );
    topic = ApiDynamicTopicRepository(
      DynamicTopicClient(api),
      requests,
      accountScope: () => 'user:7',
    );
  });
  test(
    'article sharing sends the CV and title after successful WBI preparation',
    () async {
      final repository = ApiDynamicRepository(
        DynamicClient(composer.client.api),
        requests,
        accountScope: () => 'user:7',
      );
      final post = DynamicPost(
        id: '9007199254740993123',
        title: '专栏标题',
        text: '动态摘要',
        authorId: const UserId('10'),
        authorName: '作者',
        commentTarget: const CommentTarget('88', CommentTargetType.article),
      );
      transport.hasWbiKeys = false;
      await expectLater(
        repository.shareMessage(post, const UserId('9'), RequestCancellation()),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.kind,
            'kind',
            AppFailureKind.protocol,
          ),
        ),
      );
      expect(transport.posts, 0);

      transport.hasWbiKeys = true;
      transport.status = 200;
      await repository.shareMessage(
        post,
        const UserId('9'),
        RequestCancellation(),
      );
      expect(transport.posts, 1);
      expect(transport.formUri?.queryParameters['w_sender_uid'], '7');
      expect(transport.formUri?.queryParameters['w_receiver_id'], '9');
      expect(jsonDecode(transport.form!['msg[content]']!), {
        'id': '88',
        'title': '- 哔哩哔哩专栏',
        'headline': '专栏标题',
        'source': 6,
        'author': '作者',
        'author_id': '10',
      });
    },
  );
  test('unknown publication, favorite and report each make one attempt and expose uncertainty', () async {
    await expectLater(
      composer.create(
        mid: '7',
        text: 'x',
        pictures: [],
        cancellation: RequestCancellation(),
      ),
      throwsA(isA<DynamicWriteUncertain>()),
    );
    await expectLater(
      topic.favorite('12', true, RequestCancellation()),
      throwsA(isA<DynamicWriteUncertain>()),
    );
    await expectLater(
      topic.report('12', '广告', RequestCancellation()),
      throwsA(isA<DynamicWriteUncertain>()),
    );
    expect(transport.posts, 3);
  });

  test('reservation repository maps server updates and exposes unknown results without replay', () async {
    final repository = ApiDynamicRepository(
      DynamicClient(composer.client.api),
      requests,
      accountScope: () => 'user:7',
    );
    await expectLater(
      repository.reserve('100', reservation, RequestCancellation()),
      throwsA(isA<DynamicWriteUncertain>()),
    );
    expect(transport.posts, 1);
    transport.status = 200;
    transport.data = {
      'final_btn_status': 2,
      'reserve_update': 99,
      'desc_update': '99人预约',
    };
    final result = await repository.reserve(
      '100',
      reservation,
      RequestCancellation(),
    );
    expect(
      (result.id, result.checked, result.total, result.description),
      (reservation.id, true, 99, '99人预约'),
    );
    transport.data = {'final_btn_status': 1};
    await expectLater(
      repository.reserve('100', result, RequestCancellation()),
      throwsA(isA<DynamicWriteUncertain>()),
    );
    expect(transport.posts, 3);
  });
  test('upload failures are retryable draft errors while authentication rejection stays classified', () async {
    await expectLater(
      composer.upload(
        LocalImage(Uint8List.fromList([1]), 'image/png'),
        RequestCancellation(),
      ),
      throwsA(
        isA<AppFailure>().having((e) => e.kind, 'kind', AppFailureKind.network),
      ),
    );
    transport.status = 200;
    transport.code = -101;
    await expectLater(
      composer.create(
        mid: '7',
        text: 'x',
        pictures: [],
        cancellation: RequestCancellation(),
      ),
      throwsA(
        isA<AppFailure>().having(
          (e) => e.kind,
          'kind',
          AppFailureKind.authentication,
        ),
      ),
    );
  });
  test('a late mutation after session rotation becomes cancellation rather than success or uncertainty', () async {
    transport.pending = Completer<ApiHttpResponse>();
    final pending = composer.create(
      mid: '7',
      text: 'x',
      pictures: [],
      cancellation: RequestCancellation(),
    );
    await Future<void>.delayed(Duration.zero);
    requests.advanceSession();
    transport.pending!.complete(
      ApiHttpResponse(
        200,
        Uint8List.fromList(
          utf8.encode('{"code":0,"data":{"dyn_id_str":"123"}}'),
        ),
        {},
      ),
    );
    await expectLater(
      pending,
      throwsA(
        isA<AppFailure>().having(
          (e) => e.kind,
          'kind',
          AppFailureKind.cancelled,
        ),
      ),
    );
    expect(transport.posts, 1);
  });
  test('repository maps rich ranges, Bili emotes, poll and reserve without DTOs in UI', () async {
    transport.status = 200;
    await composer.create(
      mid: '7',
      text: '😀@用户[doge]',
      pictures: [],
      title: '标题',
      spans: const [
        DynamicTextSpan(
          2,
          5,
          DynamicTextKind.mention,
          id: '9007199254740993123',
        ),
        DynamicTextSpan(5, 11, DynamicTextKind.emote),
      ],
      pollId: '123',
      pollTitle: '投票',
      reserveId: '456',
      cancellation: RequestCancellation(),
    );
    final req = transport.json!['dyn_req'] as Map;
    expect(req['content'], {
      'title': '标题',
      'contents': [
        {'raw_text': '😀', 'type': 1, 'biz_id': ''},
        {'raw_text': '@用户', 'type': 2, 'biz_id': '9007199254740993123'},
        {'raw_text': '[doge]', 'type': 9, 'biz_id': ''},
        {'raw_text': '投票', 'type': 4, 'biz_id': '123'},
      ],
    });
  });
  test('uncertain attachment creation is classified and never automatically retried', () async {
    await expectLater(
      composer.createPoll(
        DynamicPollDraft(
          title: '投票',
          options: const [DynamicPollOption('一'), DynamicPollOption('二')],
          endsAt: DateTime.now().add(const Duration(days: 1)),
        ),
        [],
        '7',
        RequestCancellation(),
      ),
      throwsA(isA<DynamicWriteUncertain>()),
    );
    await expectLater(
      composer.createReserve(
        DynamicReserveDraft('直播', DateTime.now().add(const Duration(days: 1))),
        RequestCancellation(),
      ),
      throwsA(isA<DynamicWriteUncertain>()),
    );
    expect(transport.posts, 2);
  });
}
