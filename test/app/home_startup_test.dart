import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/app/router.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/core/storage/credential_store.dart';
import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/data/session_repository.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/presentation/feed_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/input_test_app.dart';

void main() {
  for (final signedIn in [false, true]) {
    testWidgets(
      'startup reloads cancelled recommendations when restored login is $signedIn',
      (tester) async {
        final requests = ApiRequests();
        final credentials = _Credentials();
        final api = BiliApiClient(
          sessionProvider: requests,
          transport: _NavTransport(signedIn),
        );
        final session = SessionRepository(
          api: api,
          requests: requests,
          credentials: credentials,
          onSessionChanged: (_) async {},
        );
        final feed = _FeedRepository(requests);
        final restore = session.restore();
        final router = createBiliRouter(
          accountBuilder: (_) => const SizedBox(),
          playerBuilder: (_, _, _) => const SizedBox(),
        );
        addTearDown(router.dispose);
        addTearDown(() => unawaited(session.dispose()));
        addTearDown(api.close);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWithValue(session),
              sessionEpochProvider.overrideWithValue(
                () => requests.sessionEpoch,
              ),
              feedRepositoryProvider.overrideWithValue(feed),
            ],
            child: InputTestApp.router(routerConfig: router),
          ),
        );
        await tester.pump();
        expect(feed.calls, hasLength(1));
        final oldScope = ProviderScope.containerOf(
          tester.element(find.byType(FeedScreen)),
        );
        credentials.readGate.complete(_savedSession());
        await restore;
        await tester.pump();
        await tester.pump();
        expect(session.current.isSignedIn, signedIn);
        expect(feed.calls, hasLength(2));
        expect(feed.calls.first.cancellation.isCancelled, isTrue);
        final currentScope = ProviderScope.containerOf(
          tester.element(find.byType(FeedScreen)),
        );
        expect(currentScope, isNot(same(oldScope)));
        feed.calls.last.result.complete(_page('启动后的推荐'));
        await tester.pumpAndSettle();
        expect(find.text('启动后的推荐'), findsOneWidget);
        expect(
          currentScope.read(feedControllerProvider).items.isLoading,
          isFalse,
        );
        feed.calls.first.result.complete(_page('过期会话的推荐'));
        await tester.pumpAndSettle();
        expect(find.text('过期会话的推荐'), findsNothing);
        expect(feed.calls, hasLength(2));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        final disposed = session.dispose();
        await tester.pump();
        await disposed;
      },
    );
  }
}

PageResult<VideoSummary> _page(String title) => PageResult(
  items: [
    VideoSummary(
      id: const VideoId('BV1234567890'),
      title: title,
      coverUrl: '',
      author: '测试 UP',
      duration: Duration.zero,
    ),
  ],
  hasMore: false,
);

class _FeedRepository implements FeedRepository {
  _FeedRepository(this.requests);
  final ApiRequests requests;
  final calls =
      <
        ({
          RequestCancellation cancellation,
          Completer<PageResult<VideoSummary>> result,
        })
      >[];

  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) {
    final result = Completer<PageResult<VideoSummary>>();
    calls.add((cancellation: cancellation, result: result));
    return requests.run((_) => result.future, cancellation: cancellation);
  }

  @override
  Future<PageResult<VideoSummary>> loadPopular({
    required int page,
    required RequestCancellation cancellation,
  }) => loadFeed(page: page, categoryId: null, cancellation: cancellation);

  @override
  Future<List<VideoCategory>> loadCategories({
    required RequestCancellation cancellation,
  }) async => [];
}

class _Credentials implements CredentialStore {
  final readGate = Completer<String?>();
  @override
  Future<String?> read() => readGate.future;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> delete() async {}
}

String _savedSession() {
  final jar = ApiCookieJar()
    ..receive(Uri.https('passport.bilibili.com', '/'), [
      'SESSDATA=fake; Domain=.bilibili.com; Path=/; Secure',
    ]);
  return jsonEncode({
    'version': 1,
    'mid': '123',
    'name': '测试用户',
    'cookies': jar.exportForSecureStorage(),
  });
}

class _NavTransport implements ApiTransport {
  _NavTransport(this.signedIn);
  final bool signedIn;
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
            'code': signedIn ? 0 : -101,
            'data': {'isLogin': signedIn, 'mid': 123, 'uname': '测试用户'},
          }),
        ),
      ),
      const {},
    );
  }
}
