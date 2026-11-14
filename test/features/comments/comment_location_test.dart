import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/comment_target.dart';
import 'package:bilisail/domain/content_link.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/comments/application/comments_controller.dart';
import 'package:bilisail/features/comments/data/api_comments_repository.dart';
import 'package:bilisail/features/comments/domain/comments_repository.dart';
import 'package:bilisail/shared/ui/comments_panel.dart';
import 'package:bilisail/shared/ui/content_link_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../messages/message_fakes.dart';

const _root = CommentEntry(
  id: '200',
  author: '甲',
  message: '原评论',
  replyCount: 60,
);
const _reply = CommentEntry(
  id: '242',
  author: '乙',
  message: '通知对应的回复',
  rootId: '200',
);
const _location = CommentLocation('200', replyId: '242');
const _located = LocatedCommentThread(
  root: _root,
  page: CommentPage(
    items: [
      CommentEntry(id: '241', author: '丙', message: '同页回复'),
      _reply,
    ],
    hasMore: true,
  ),
  pageNumber: 3,
);

void main() {
  late AuthFake auth;
  late _Repository repository;
  late ProviderContainer container;
  final provider = videoCommentsControllerProvider('170001');
  setUp(() async {
    auth = AuthFake();
    repository = _Repository();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        videoCommentsRepositoryProvider.overrideWithValue(repository),
      ],
    );
    container.listen(provider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() async {
    container.dispose();
    await auth.stream.close();
  });

  test(
    'locates a reply with its root and continues from the matched page',
    () async {
      final controller = container.read(provider.notifier);
      await controller.locate(_location);
      expect(container.read(provider).openRoot?.id, '200');
      expect(container.read(provider).focusedCommentId, '242');
      expect(container.read(provider).replyItems.map((entry) => entry.id), [
        '242',
        '241',
      ]);
      await controller.loadReplies();
      expect(repository.replyPages, [4]);
      controller.closeReplies();
      expect(container.read(provider).focusedCommentId, isNull);
    },
  );

  test('a late locate cannot replace a newer locate', () async {
    final controller = container.read(provider.notifier);
    final pending = Completer<LocatedCommentThread>();
    repository.pending = pending;
    final first = controller.locate(const CommentLocation('100'));
    final cancellation = repository.cancellation;
    repository.pending = null;
    await controller.locate(_location);
    expect(cancellation?.isCancelled, isTrue);
    pending.complete(
      const LocatedCommentThread(
        root: CommentEntry(id: '100', author: '旧', message: '旧'),
        page: CommentPage(items: [], hasMore: false),
        pageNumber: 1,
      ),
    );
    await first;
    expect(container.read(provider).openRoot?.id, '200');
  });

  test(
    'refresh and account changes reject pending comment locations',
    () async {
      final controller = container.read(provider.notifier);
      for (final accountChange in [false, true]) {
        final pending = Completer<LocatedCommentThread>();
        repository.pending = pending;
        final locating = controller.locate(_location);
        final cancellation = repository.cancellation;
        if (accountChange) {
          repository.sessionEpoch++;
          auth.emit(const AuthState());
          await Future<void>.delayed(Duration.zero);
        } else {
          await controller.load(refresh: true);
        }
        expect(cancellation?.isCancelled, isTrue);
        pending.complete(_located);
        await locating;
        expect(container.read(provider).openRoot, isNull);
      }
    },
  );

  test('missing comments show a failure without inventing a target', () async {
    repository.failure = const AppFailure(AppFailureKind.notFound, '评论已删除');
    await container.read(provider.notifier).locate(_location);
    expect(container.read(provider).message, '评论已删除');
    expect(container.read(provider).openRoot, isNull);
    expect(container.read(provider).loading, isFalse);
  });

  testWidgets(
    'content link opens the matching reply once and marks it visibly',
    (tester) async {
      repository.result = LocatedCommentThread(
        root: CommentEntry(
          id: '200',
          author: '甲',
          message: List.filled(400, '很长的原评论').join(),
          replyCount: 60,
        ),
        page: _located.page,
        pageNumber: 3,
      );
      Widget app([String requestId = '1']) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ContentLinkScope(
              link: ContentLink(comment: _location, requestId: requestId),
              child: const CommentsPanel(
                target: CommentTarget('170001', CommentTargetType.video),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('通知对应的回复').hitTestable(), findsOneWidget);
      expect(find.text('评论详情'), findsOneWidget);
      expect(repository.locates, 1);
      final box = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey(('comment', '242'))),
      );
      expect((box.decoration as BoxDecoration).color, isNotNull);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(repository.locates, 1);
      expect(tester.takeException(), isNull);
      container.read(provider.notifier).closeReplies();
      await tester.pumpAndSettle();
      await tester.pumpWidget(app('2'));
      await tester.pumpAndSettle();
      expect(repository.locates, 2);
      expect(find.text('通知对应的回复').hitTestable(), findsOneWidget);
    },
  );

  for (final found in [true, false]) {
    test(
      'repository directly locates beyond 500 replies found=$found',
      () async {
        final transport = _Transport((uri) {
          if (uri.path.endsWith('/jump')) {
            expect(uri.queryParameters, {
              'oid': '170001',
              'type': '1',
              'rpid': '242',
            });
            return {
              'replies': [_comment('200')],
              'page': {'rt_num': 60},
            };
          }
          expect(uri.queryParameters['pn'], '30');
          return {
            'root': _comment('200'),
            'replies': [_comment(found ? '242' : '300')],
            'page': {'count': 10000, 'size': 20},
          };
        });
        final requests = ApiRequests();
        final api = BiliApiClient(
          transport: transport,
          sessionProvider: requests,
        );
        addTearDown(api.close);
        final data = ApiCommentsRepository(
          api,
          requests,
          accountScope: () => 'guest',
        );
        final result = data.locate('170001', _location, RequestCancellation());
        if (found) {
          final thread = await result;
          expect(thread.pageNumber, 30);
          expect(thread.root.id, '200');
          expect(thread.page.items.single.id, '242');
        } else {
          await expectLater(
            result,
            throwsA(
              isA<AppFailure>().having(
                (e) => e.kind,
                'kind',
                AppFailureKind.notFound,
              ),
            ),
          );
        }
        expect(transport.uris.map((uri) => uri.path), [
          '/x/v2/reply/jump',
          '/x/v2/reply/reply',
        ]);
        expect(transport.uris.last.queryParameters['root'], '200');
      },
    );
  }

  test('repository direct location cancels across account epochs before the target page', () async {
    final requests = ApiRequests();
    final transport = _Transport((uri) {
      requests.advanceSession();
      return {
        'replies': [_comment('200')],
        'page': {'rt_num': 60},
      };
    });
    final api = BiliApiClient(transport: transport, sessionProvider: requests);
    addTearDown(api.close);
    final data = ApiCommentsRepository(
      api,
      requests,
      accountScope: () => 'guest',
    );
    final cancellation = RequestCancellation();
    await expectLater(
      data.locate('170001', _location, cancellation),
      throwsA(
        isA<AppFailure>().having(
          (e) => e.kind,
          'kind',
          AppFailureKind.cancelled,
        ),
      ),
    );
    expect(cancellation.isCancelled, isTrue);
    expect(transport.uris, hasLength(1));
  });
}

class _Repository extends Fake
    implements CommentsRepository, CommentLocationRepository {
  @override
  String accountScope = 'user:1';
  @override
  int sessionEpoch = 1;
  int locates = 0;
  final replyPages = <int>[];
  Completer<LocatedCommentThread>? pending;
  RequestCancellation? cancellation;
  Object? failure;
  LocatedCommentThread result = _located;
  @override
  Future<LocatedCommentThread> locate(
    String oid,
    CommentLocation location,
    RequestCancellation cancellation,
  ) async {
    locates++;
    this.cancellation = cancellation;
    final error = failure;
    if (error != null) throw error;
    return pending?.future ?? Future.value(result);
  }

  @override
  Future<CommentPage> load(
    String oid,
    int page,
    CommentSort sort,
    RequestCancellation cancellation, {
    String? cursor,
  }) async => const CommentPage(items: [], hasMore: false);
  @override
  Future<CommentPage> replies(
    String oid,
    String rootId,
    int page,
    RequestCancellation cancellation,
  ) async {
    replyPages.add(page);
    return const CommentPage(items: [], hasMore: false);
  }
}

Map<String, Object?> _comment(String id) => {
  'oid_str': '170001',
  'type': 1,
  'rpid_str': id,
  'member': {'mid': '7', 'uname': '作者'},
  'content': {'message': '回复'},
  'root': id == '200' ? 0 : 200,
};

class _Transport implements ApiTransport {
  _Transport(this.handler);
  final Object Function(Uri) handler;
  final uris = <Uri>[];
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    uris.add(uri);
    return ApiHttpResponse(
      200,
      Uint8List.fromList(
        utf8.encode(jsonEncode({'code': 0, 'data': handler(uri)})),
      ),
      const {},
    );
  }
}
