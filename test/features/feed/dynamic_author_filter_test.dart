import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/dynamic/application/dynamic_composer_controller.dart';
import 'package:bilisail/features/feed/application/dynamic_authors_controller.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/presentation/dynamic_author_filter.dart';
import 'package:bilisail/features/feed/presentation/feed_screen.dart';
import 'package:bilisail/features/feed/presentation/home_content.dart';
import 'package:bilisail/shared/ui/smooth_scroll_behavior.dart';
import 'package:bilisail/shared/ui/dynamic_compose_dialog.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/dynamic_author_fakes.dart';
import '../../support/dynamic_composer_fakes.dart';
import '../../support/dynamic_fakes.dart';

void main() {
  for (final (width, scale, wide) in [
    (320.0, 1.0, false),
    (375.0, 2.0, false),
    (768.0, 1.0, false),
    (960.0, 2.0, false),
    (1280.0, 1.0, true),
    (1440.0, 2.0, true),
  ]) {
    testWidgets('author choices adapt at $width / $scale', (tester) async {
      _size(tester, width);
      final repository = DynamicAuthorRepository();
      final selected = ValueNotifier(HomeChannel.dynamic);
      addTearDown(selected.dispose);
      await tester.pumpWidget(_app(repository, selected, scale: scale));
      await tester.pumpAndSettle();
      final filter = tester.widget<DynamicAuthorFilter>(
        find.byType(DynamicAuthorFilter),
      );
      expect(filter.wide, wide);
      final compose = find.byKey(const ValueKey('dynamic-compose'));
      final sections = find.byKey(const ValueKey('home-section-strip-dynamic'));
      expect(compose.hitTestable(), findsOneWidget);
      expect(tester.getCenter(compose).dy, tester.getCenter(sections).dy);
      expect(
        tester
            .widget<DynamicComposeButton>(find.byType(DynamicComposeButton))
            .compact,
        width < 480 + (scale - 1) * 13 * 8,
      );
      expect(
        find.descendant(of: find.byType(CustomScrollView), matching: compose),
        findsNothing,
      );
      final choice = find.byKey(const ValueKey('dynamic-author-1'));
      final content = find.byType(HomeContent);
      expect(
        wide
            ? tester.getRect(choice).right < tester.getRect(content).left
            : tester.getRect(choice).bottom < tester.getRect(content).top,
        isTrue,
      );
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(repository.feedCalls.single.authorId, const UserId('1'));
      expect(find.text('筛选 1 图文 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'tab changes preserve selector state and position without duplicate reads',
    (tester) async {
      _size(tester, 375);
      final repository = DynamicAuthorRepository();
      final selected = ValueNotifier(HomeChannel.dynamic);
      addTearDown(selected.dispose);
      await tester.pumpWidget(_app(repository, selected));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dynamic-author-1')));
      await tester.pumpAndSettle();
      final filter = find.byType(DynamicAuthorFilter);
      final filterState = tester.state(filter);
      final scroll = find.descendant(
        of: filter,
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scroll).position;
      position.jumpTo(650);
      await tester.pumpAndSettle();
      final firstFeed = repository.feedCalls.single;
      final contentPosition = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      contentPosition.jumpTo(150);
      await tester.pumpAndSettle();
      selected.value = HomeChannel.videoDynamic;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dynamic-compose')), findsNothing);
      expect(tester.state(filter), same(filterState));
      expect(tester.state<ScrollableState>(scroll).position, same(position));
      expect(position.pixels, 650);
      expect(repository.authorCalls, hasLength(1));
      expect(repository.feedCalls, hasLength(2));
      expect(repository.feedCalls.last.query.channel, HomeChannel.videoDynamic);
      expect(repository.feedCalls.last.authorId, firstFeed.authorId);
      expect(find.text('筛选 1 视频 1'), findsOneWidget);
      selected.value = HomeChannel.dynamic;
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('dynamic-compose')).hitTestable(),
        findsOneWidget,
      );
      expect(repository.feedCalls, hasLength(2));
      expect(contentPosition.pixels, 150);
      // Resizing changes the selector's axis without replacing its owner/feed.
      tester.view.physicalSize = const Size(1280, 900);
      await tester.pumpAndSettle();
      expect(tester.state(filter), same(filterState));
      expect(
        tester.widget<DynamicAuthorFilter>(filter).state.selected?.id,
        const UserId('1'),
      );
      tester.view.physicalSize = const Size(375, 900);
      await tester.pumpAndSettle();
      expect(tester.state<ScrollableState>(scroll).position.pixels, 650);
      expect(repository.feedCalls, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  for (final authorId in [null, const UserId('1')]) {
    testWidgets(
      'publication refreshes the visible dynamic query for $authorId',
      (tester) async {
        _size(tester, 375);
        final repository = DynamicAuthorRepository();
        final composer = DynamicComposerFake();
        final auth = DynamicAuthFake();
        addTearDown(() => auth.stream.close());
        final selected = ValueNotifier(HomeChannel.dynamic);
        addTearDown(selected.dispose);
        await tester.pumpWidget(
          _app(repository, selected, auth: auth, composer: composer),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('home-section-图文')));
        await tester.pumpAndSettle();
        if (authorId != null) {
          await tester.tap(
            find.byKey(ValueKey('dynamic-author-${authorId.value}')),
          );
          await tester.pumpAndSettle();
        }
        final allReads = repository.allReads;
        final filteredReads = repository.feedCalls.length;
        final authorReads = repository.authorCalls.length;
        final compose = find.byKey(const ValueKey('dynamic-compose'));
        final initialTop = tester.getTopLeft(compose).dy;
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(compose).dy, initialTop);
        await tester.tap(compose);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('dynamic-compose-text')),
          '新的动态',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('dynamic-compose-submit')));
        await tester.pumpAndSettle();
        expect(composer.drafts.single.text, '新的动态');
        expect(repository.authorCalls, hasLength(authorReads + 1));
        expect(repository.allReads, allReads + (authorId == null ? 1 : 0));
        expect(
          repository.feedCalls,
          hasLength(filteredReads + (authorId == null ? 0 : 1)),
        );
        if (authorId != null) {
          expect(repository.feedCalls.last.query.section, '图文');
          expect(repository.feedCalls.last.authorId, authorId);
        }
        expect(find.byType(DynamicComposeDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'changing author cancels stale reads and only loads visible content',
    (tester) async {
      _size(tester, 1280);
      final repository = DynamicAuthorRepository()..deferFeeds = true;
      final selected = ValueNotifier(HomeChannel.dynamic);
      addTearDown(selected.dispose);
      await tester.pumpWidget(_app(repository, selected));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dynamic-author-1')));
      await tester.pump();
      final old = repository.feedCalls.single;
      await tester.tap(find.byKey(const ValueKey('dynamic-author-2')));
      await tester.pump();
      await tester.pump();
      expect(old.cancellation.isCancelled, isTrue);
      final latest = repository.feedCalls.last;
      latest.result.complete(repository.content(latest.query, latest.authorId));
      await tester.pumpAndSettle();
      old.result.complete(repository.content(old.query, old.authorId));
      await tester.pumpAndSettle();
      expect(find.text('筛选 2 图文 1'), findsOneWidget);
      expect(find.text('筛选 1 图文 1'), findsNothing);
      selected.value = HomeChannel.videoDynamic;
      for (var i = 0; i < 20 && repository.feedCalls.length == 2; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(repository.feedCalls, hasLength(3));
      final video = repository.feedCalls.last;
      video.result.complete(repository.content(video.query, video.authorId));
      await tester.pumpAndSettle();
      final reads = repository.feedCalls.length;
      await tester.tap(find.byKey(const ValueKey('dynamic-author-3')));
      await tester.pump();
      expect(repository.feedCalls, hasLength(reads + 1));
      expect(repository.feedCalls.last.query.channel, HomeChannel.videoDynamic);
      final pending = repository.feedCalls.last;
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(pending.cancellation.isCancelled, isTrue);
      pending.result.complete(
        repository.content(pending.query, pending.authorId),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'all and image-text tabs share selection and guests have no selector',
    (tester) async {
      _size(tester, 1280);
      final repository = DynamicAuthorRepository();
      final selected = ValueNotifier(HomeChannel.dynamic);
      addTearDown(selected.dispose);
      await tester.pumpWidget(_app(repository, selected));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dynamic-author-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-section-图文')));
      await tester.pumpAndSettle();
      expect(repository.feedCalls.last.query.section, '图文');
      expect(repository.feedCalls.last.authorId, const UserId('2'));
      await tester.tap(find.byKey(const ValueKey('dynamic-author-all')));
      await tester.pumpAndSettle();
      expect(find.text('筛选 全部 图文 1'), findsOneWidget);
      await tester.pumpWidget(_app(repository, selected, signedIn: false));
      await tester.pumpAndSettle();
      expect(find.byType(DynamicAuthorFilter), findsNothing);
      expect(find.text('登录后可查看动态'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('workspace-scoped selectors do not share selection', (
    tester,
  ) async {
    _size(tester, 1280);
    final repository = DynamicAuthorRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [homeRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                for (var i = 0; i < 2; i++)
                  Expanded(
                    child: ProviderScope(
                      overrides: [
                        homeControllerProvider.overrideWith2(
                          HomeController.new,
                        ),
                      ],
                      child: const DynamicFeedLayout(
                        visible: true,
                        isSignedIn: true,
                        child: SizedBox(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final filters = find.byType(DynamicAuthorFilter);
    final first = ProviderScope.containerOf(tester.element(filters.first));
    final second = ProviderScope.containerOf(tester.element(filters.last));
    first
        .read(dynamicAuthorsProvider('user:7').notifier)
        .select(const UserId('1'));
    await tester.pumpAndSettle();
    expect(
      first.read(dynamicAuthorsProvider('user:7')).selected?.id,
      const UserId('1'),
    );
    expect(second.read(dynamicAuthorsProvider('user:7')).selected, isNull);
    expect(tester.takeException(), isNull);
  });
}

void _size(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(
  DynamicAuthorRepository repository,
  ValueNotifier<HomeChannel> selected, {
  double scale = 1,
  bool signedIn = true,
  DynamicAuthFake? auth,
  DynamicComposerFake? composer,
}) => ProviderScope(
  overrides: [
    homeRepositoryProvider.overrideWithValue(repository),
    feedRepositoryProvider.overrideWithValue(_Feed()),
    if (auth != null) authRepositoryProvider.overrideWithValue(auth),
    if (composer != null)
      dynamicComposerRepositoryProvider.overrideWithValue(composer),
  ],
  child: MaterialApp(
    scrollBehavior: const SmoothScrollBehavior(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: AppNoticeHost(child: child!),
    ),
    home: Scaffold(
      body: ValueListenableBuilder(
        valueListenable: selected,
        builder: (_, channel, _) => FeedScreen(
          channel: channel,
          isSignedIn: signedIn,
          onChannelChanged: (value) => selected.value = value,
          channelGroups: const [
            [HomeChannel.dynamic, HomeChannel.videoDynamic],
          ],
        ),
      ),
    ),
  ),
);

final class _Feed implements FeedRepository {
  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required RequestCancellation cancellation,
    String? categoryId,
  }) async => const PageResult(items: [], hasMore: false);
  @override
  Future<PageResult<VideoSummary>> loadPopular({
    required int page,
    required RequestCancellation cancellation,
  }) => loadFeed(page: page, cancellation: cancellation);
  @override
  Future<List<VideoCategory>> loadCategories({
    required RequestCancellation cancellation,
  }) async => [];
}
