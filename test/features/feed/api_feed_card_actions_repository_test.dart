import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/data/api_feed_repository.dart';
import 'package:bilisail/features/feed/data/api_home_repository.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/video/domain/video_actions_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const _entry = HomeEntry(
  id: 'aid:42',
  aid: '9007199254740993123',
  title: '失效视频',
  kind: HomeEntryKind.video,
);
const _feedback = RecommendationFeedback(
  aid: '42',
  goto: 'av',
  trackId: '',
  ownerMid: '7',
);

void main() {
  late _Transport transport;
  late ApiRequests requests;
  late BiliApiClient api;
  late ApiHomeRepository home;
  late ApiFeedRepository feed;
  var scope = 'user:7';
  setUp(() {
    scope = 'user:7';
    transport = _Transport();
    requests = ApiRequests();
    api = BiliApiClient(
      transport: transport,
      sessionProvider: requests,
      cookieJar: ApiCookieJar()
        ..receive(Uri.https('api.bilibili.com', '/'), [
          'SESSDATA=fixture; Path=/; Secure',
          'bili_jct=fixture-csrf; Path=/; Secure',
        ]),
    );
    home = ApiHomeRepository(
      HomeClient(api),
      requests,
      accountScope: () => scope,
    );
    feed = ApiFeedRepository(api, requests);
  });
  tearDown(() => api.close());
  test(
    'delete repository uses explicit aid even when no playable bvid exists',
    () async {
      await home.removeWatchLater(
        _entry,
        scope: scope,
        cancellation: RequestCancellation(),
      );
      expect(transport.fields['aid'], _entry.aid);
      expect(transport.posts, 1);
    },
  );
  test('feed repository carries Web recommendation context through the write boundary', () async {
    await feed.rejectRecommendation(
      _feedback,
      cancellation: RequestCancellation(),
    );
    expect(transport.fields['id'], '42');
    expect(transport.fields['track_id'], '');
    expect(transport.fields['reason_id'], '1');
    expect(transport.posts, 1);
  });
  test(
    'unknown transport outcomes stay unknown for both card mutations',
    () async {
      transport.failure = const ApiFailure(
        ApiFailureCategory.network,
        'fixture',
      );
      await expectLater(
        home.removeWatchLater(
          _entry,
          scope: scope,
          cancellation: RequestCancellation(),
        ),
        throwsA(isA<UnknownWriteOutcome>()),
      );
      await expectLater(
        feed.rejectRecommendation(
          _feedback,
          cancellation: RequestCancellation(),
        ),
        throwsA(isA<UnknownWriteOutcome>()),
      );
      expect(transport.posts, 2);
    },
  );
  test('account transition cancels late deletion instead of classifying it as unknown', () async {
    transport.pending = Completer<ApiHttpResponse>();
    final write = home.removeWatchLater(
      _entry,
      scope: scope,
      cancellation: RequestCancellation(),
    );
    final check = expectLater(
      write,
      throwsA(
        isA<AppFailure>().having(
          (e) => e.kind,
          'kind',
          AppFailureKind.cancelled,
        ),
      ),
    );
    requests.advanceSession();
    scope = 'user:8';
    transport.pending?.complete(_Transport.success);
    await check;
    expect(transport.posts, 1);
  });
}

final class _Transport implements ApiTransport, ApiFormTransport {
  static final success = ApiHttpResponse(
    200,
    Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': null}))),
    const {},
  );
  Map<String, String> fields = {};
  int posts = 0;
  ApiFailure? failure;
  Completer<ApiHttpResponse>? pending;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async => success;
  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    this.fields = fields;
    posts++;
    if (failure case final error?) throw error;
    return pending?.future ?? success;
  }
}
