import 'dart:async';

import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/comment_target.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/comments/application/comments_controller.dart';
import 'package:bilisail/features/comments/domain/comments_repository.dart';
import 'package:bilisail/shared/ui/comments_panel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _video = CommentTarget('42', CommentTargetType.video);
const _dynamic = CommentTarget('43', CommentTargetType.dynamic);

void main() {
  for (final target in [_video, _dynamic]) {
    for (final replies in [false, true]) {
      testWidgets(
        '${target.type.name} ${replies ? 'replies' : 'comments'} load once near bottom and stop at the end',
        (tester) async {
          final pending = Completer<CommentPage>();
          final repo = _Comments();
          if (replies) {
            repo.onReplies = (page) =>
                page == 1 ? Future.value(_page(1)) : pending.future;
          } else {
            repo.onLoad = (page) =>
                page == 1 ? Future.value(_page(1)) : pending.future;
          }
          final container = await _mount(tester, repo, target: target);
          final provider = commentsProviderFor(target);
          if (replies) {
            await container
                .read(provider.notifier)
                .openReplies(container.read(provider).items.first);
            await tester.pumpAndSettle();
          }
          final calls = replies ? repo.replyPages : repo.pages;
          expect(calls, [1]);

          await tester.drag(find.byType(ListView), const Offset(0, -6000));
          await tester.pump(const Duration(milliseconds: 100));
          expect(calls, [1, 2]);
          if (!replies) expect(repo.cursors, [null, 'next-1']);
          await _bottom(tester);
          await _wheel(tester);
          expect(calls, [1, 2]);

          pending.complete(_page(2, more: false));
          await tester.pumpAndSettle();
          final state = container.read(provider);
          expect(replies ? state.replyItems : state.items, hasLength(40));
          await _bottom(tester);
          await _wheel(tester);
          expect(calls, [1, 2]);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final replies in [false, true]) {
    testWidgets(
      'short ${replies ? 'reply' : 'comment'} pages fill the viewport without a gesture',
      (tester) async {
        final repo = _Comments();
        Future<CommentPage> shortPage(int page) async =>
            _page(page, count: 1, more: page < 3);
        if (replies) {
          repo.onReplies = shortPage;
        } else {
          repo.onLoad = shortPage;
        }
        final container = await _mount(tester, repo, height: 900);
        if (replies) {
          await container
              .read(commentsProviderFor(_video).notifier)
              .openReplies(
                container.read(commentsProviderFor(_video)).items.first,
              );
          await tester.pumpAndSettle();
        }
        expect(replies ? repo.replyPages : repo.pages, [1, 2, 3]);
        expect(find.text('没有更多了'), findsOneWidget);
        expect(
          tester
              .widget<ListView>(find.byType(ListView))
              .controller!
              .position
              .maxScrollExtent,
          0,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${replies ? 'reply' : 'comment'} failure waits for explicit retry',
      (tester) async {
        final repo = _Comments();
        var fail = true;
        Future<CommentPage> page(int number) async {
          if (number == 2 && fail) {
            throw const AppFailure(AppFailureKind.network, '网络暂不可用');
          }
          return _page(number, more: number == 1);
        }

        if (replies) {
          repo.onReplies = page;
        } else {
          repo.onLoad = page;
        }
        final container = await _mount(tester, repo);
        final provider = commentsProviderFor(_video);
        if (replies) {
          await container
              .read(provider.notifier)
              .openReplies(container.read(provider).items.first);
          await tester.pumpAndSettle();
        }
        await _bottom(tester);
        await tester.pumpAndSettle();
        final calls = replies ? repo.replyPages : repo.pages;
        expect(calls, [1, 2]);
        await _bottom(tester);
        await _wheel(tester);
        await tester.pumpAndSettle();
        expect(calls, [1, 2]);
        final failed = container.read(provider);
        expect(replies ? failed.replyLoadFailed : failed.loadFailed, isTrue);

        fail = false;
        await tester.tap(find.text('重试加载'));
        await tester.pumpAndSettle();
        expect(calls, [1, 2, 2]);
        final recovered = container.read(provider);
        expect(
          replies ? recovered.replyLoadFailed : recovered.loadFailed,
          isFalse,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'hidden comments wait for activation before filling short pages',
    (tester) async {
      final active = ValueNotifier(false);
      addTearDown(active.dispose);
      final repo = _Comments()
        ..onLoad = (page) async => _page(page, count: 1, more: page == 1);
      await _mount(tester, repo, active: active);
      expect(repo.pages, [1]);
      active.value = true;
      await tester.pumpAndSettle();
      expect(repo.pages, [1, 2]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'resizing a viewport loads more when its bottom becomes visible',
    (tester) async {
      final repo = _Comments();
      await _mount(tester, repo);
      expect(repo.pages, [1]);
      tester.view.physicalSize = const Size(900, 4000);
      await tester.pumpAndSettle();
      expect(repo.pages, [1, 2]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('duplicate reply pages terminate automatic pagination', (
    tester,
  ) async {
    final repo = _Comments()..onReplies = (_) async => _page(1, count: 1);
    final container = await _mount(tester, repo);
    final provider = commentsProviderFor(_video);
    await container
        .read(provider.notifier)
        .openReplies(container.read(provider).items.first);
    await tester.pumpAndSettle();
    expect(repo.replyPages, [1, 2]);
    expect(container.read(provider).replyHasMore, isFalse);
    await _wheel(tester);
    await tester.pumpAndSettle();
    expect(repo.replyPages, [1, 2]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'closing replies while loading does not reopen or page the old root',
    (tester) async {
      final pending = Completer<CommentPage>();
      final repo = _Comments()
        ..onReplies = (page) =>
            page == 1 ? Future.value(_page(1)) : pending.future;
      final container = await _mount(tester, repo);
      final provider = commentsProviderFor(_video);
      final controller = container.read(provider.notifier);
      await controller.openReplies(container.read(provider).items.first);
      await tester.pumpAndSettle();
      await _bottom(tester);
      expect(repo.replyPages, [1, 2]);
      controller.closeReplies();
      pending.complete(_page(2, count: 1));
      await tester.pumpAndSettle();
      expect(container.read(provider).openRoot, isNull);
      expect(container.read(provider).replyItems, isEmpty);
      expect(repo.replyPages, [1, 2]);
      expect(repo.pages, [1]);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<ProviderContainer> _mount(
  WidgetTester tester,
  _Comments repo, {
  CommentTarget target = _video,
  ValueNotifier<bool>? active,
  double height = 700,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(390, height);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final panel = CommentsPanel(target: target);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_Guest.new),
        commentsRepositoryProvider(target.type).overrideWithValue(repo),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: active == null
              ? panel
              : ValueListenableBuilder(
                  valueListenable: active,
                  builder: (_, value, child) =>
                      WorkspaceActivity(active: value, child: child!),
                  child: panel,
                ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(CommentsPanel)));
}

Future<void> _bottom(WidgetTester tester) async {
  final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
  scroll.jumpTo(scroll.position.maxScrollExtent);
  await tester.pump();
  await tester.pump();
}

Future<void> _wheel(WidgetTester tester) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: tester.getCenter(find.byType(ListView)),
      scrollDelta: const Offset(0, 300),
    ),
  );
  await tester.pump();
}

CommentPage _page(int page, {int count = 20, bool more = true}) => CommentPage(
  items: List.generate(
    count,
    (index) => CommentEntry(
      id: '$page-$index',
      author: '用户',
      message: '评论 $page-$index',
      replyCount: 100,
    ),
  ),
  hasMore: more,
  nextCursor: 'next-$page',
);

class _Guest extends AuthController {
  @override
  AuthState build() => const AuthState();
}

class _Comments extends Fake implements CommentsRepository {
  final pages = <int>[], replyPages = <int>[];
  final cursors = <String?>[];
  Future<CommentPage> Function(int)? onLoad, onReplies;

  @override
  String get accountScope => 'guest';
  @override
  int get sessionEpoch => 0;
  @override
  Future<CommentPage> load(
    String oid,
    int page,
    CommentSort sort,
    RequestCancellation cancellation, {
    String? cursor,
  }) {
    pages.add(page);
    cursors.add(cursor);
    return onLoad?.call(page) ?? Future.value(_page(page, more: page == 1));
  }

  @override
  Future<CommentPage> replies(
    String oid,
    String rootId,
    int page,
    RequestCancellation cancellation,
  ) {
    replyPages.add(page);
    return onReplies?.call(page) ?? Future.value(_page(page, more: page == 1));
  }
}
