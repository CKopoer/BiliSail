import 'dart:async';

import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/feed_screen.dart';
import 'package:bilisail/features/feed/presentation/home_content.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  for (final channel in [
    HomeChannel.dynamic,
    HomeChannel.videoDynamic,
    HomeChannel.bangumi,
    HomeChannel.favorites,
    HomeChannel.watchLater,
  ]) {
    for (final section in channel.sections) {
      testWidgets('${channel.name}/$section fills the initial viewport', (
        tester,
      ) async {
        final repository = _HomeRepository();
        await tester.pumpWidget(_app(repository, channel, section));
        await tester.pumpAndSettle();
        expect(repository.pages(section), [1, 2]);
        expect(find.byTooltip('刷新列表'), findsOneWidget);
        expect(find.text('刷新列表'), findsNothing);
        expect(find.byTooltip('回到顶部'), findsNothing);
        expect(find.text('$section-2-0'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('an empty first page can continue automatically', (tester) async {
    final repository = _HomeRepository(emptyFirst: true);
    await tester.pumpWidget(_app(repository, HomeChannel.dynamic, '全部'));
    await tester.pumpAndSettle();
    expect(repository.pages('全部'), [1, 2]);
    expect(find.text('全部-2-0'), findsOneWidget);
  });

  testWidgets('window growth checks home pagination without scrolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _HomeRepository(itemCount: 15);
    await tester.pumpWidget(_app(repository, HomeChannel.videoDynamic, '最新视频'));
    await tester.pumpAndSettle();
    expect(repository.pages('最新视频'), [1]);
    tester.view.physicalSize = const Size(1920, 1600);
    await tester.pumpAndSettle();
    expect(repository.pages('最新视频'), [1, 2]);
    expect(_position(tester).pixels, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inactive workspace resumes its pending layout check', (
    tester,
  ) async {
    final repository = _HomeRepository();
    final active = ValueNotifier(false);
    addTearDown(active.dispose);
    await tester.pumpWidget(
      _app(repository, HomeChannel.dynamic, '全部', active: active),
    );
    await tester.pumpAndSettle();
    expect(repository.pages('全部'), [1]);
    active.value = true;
    await tester.pumpAndSettle();
    expect(repository.pages('全部'), [1, 2]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a hidden dynamic subtab stops after an in-flight page', (
    tester,
  ) async {
    final repository = _HomeRepository(holdAllPage: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeRepositoryProvider.overrideWithValue(repository),
          feedRepositoryProvider.overrideWithValue(_FeedRepository()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: FeedScreen(channel: HomeChannel.dynamic, isSignedIn: true),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(repository.pages('全部'), [1, 2]);
    await tester.tap(find.byKey(const ValueKey('home-section-视频')));
    await tester.pumpAndSettle();
    repository.allPage.complete(
      const HomePage([], hasMore: true, nextCursor: 'all-page-2'),
    );
    await tester.pumpAndSettle();
    expect(repository.pages('全部'), [1, 2]);
    await tester.tap(find.byKey(const ValueKey('home-section-全部')));
    await tester.pumpAndSettle();
    expect(repository.pages('全部'), [1, 2, 3]);
    expect(find.byTooltip('刷新列表'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed home pagination waits for an explicit retry', (
    tester,
  ) async {
    final repository = _HomeRepository(failPage: true);
    await tester.pumpWidget(_app(repository, HomeChannel.dynamic, '全部'));
    await tester.pumpAndSettle();
    expect(repository.pages('全部'), [1, 2]);
    expect(find.text('下一页暂时不可用'), findsOneWidget);
    tester.view.physicalSize = const Size(1200, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpAndSettle();
    await _wheel(tester, 100);
    await tester.pumpAndSettle();
    expect(repository.pages('全部'), [1, 2]);
    await tester.ensureVisible(find.text('重试'));
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(repository.pages('全部'), [1, 2, 2]);
    expect(find.text('全部-2-0'), findsOneWidget);
  });

  testWidgets(
    'dynamic subtabs retain offsets and refresh only the visible query',
    (tester) async {
      final repository = _HomeRepository(itemCount: 30, hasMore: false);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            homeRepositoryProvider.overrideWithValue(repository),
            feedRepositoryProvider.overrideWithValue(_FeedRepository()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: FeedScreen(channel: HomeChannel.dynamic, isSignedIn: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _wheel(tester, 200);
      await tester.pumpAndSettle();
      final allOffset = _position(tester).pixels;
      await tester.tap(find.byKey(const ValueKey('home-section-视频')));
      await tester.pumpAndSettle();
      await _wheel(tester, 350);
      await tester.pumpAndSettle();
      final videoOffset = _position(tester).pixels;
      await tester.tap(find.byKey(const ValueKey('home-section-图文')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-section-视频')));
      await tester.pumpAndSettle();
      expect(_position(tester).pixels, closeTo(videoOffset, 1));
      await tester.tap(find.byTooltip('刷新列表'));
      await tester.pumpAndSettle();
      expect(_position(tester).pixels, 0);
      expect(repository.pages('视频'), [1, 1]);
      expect(repository.pages('全部'), [1]);
      expect(repository.pages('图文'), [1]);
      await tester.tap(find.byKey(const ValueKey('home-section-全部')));
      await tester.pumpAndSettle();
      expect(_position(tester).pixels, closeTo(allOffset, 1));
      expect(tester.takeException(), isNull);
    },
  );

  for (final channel in [HomeChannel.dynamic, HomeChannel.bangumi]) {
    testWidgets(
      '${channel.name} actions track scrolling and refresh its query',
      (tester) async {
        tester.view.physicalSize = const Size(360, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final section = channel.sections.first;
        final repository = _HomeRepository(itemCount: 30, hasMore: false);
        await tester.pumpWidget(_app(repository, channel, section));
        await tester.pumpAndSettle();
        expect(find.byTooltip('回到顶部'), findsNothing);
        await _wheel(tester, 200);
        await tester.pumpAndSettle();
        expect(find.byTooltip('回到顶部'), findsOneWidget);
        final refreshRect = tester.getRect(find.byTooltip('刷新列表'));
        final topRect = tester.getRect(find.byTooltip('回到顶部'));
        expect(refreshRect.width, 48);
        expect(refreshRect.height, 48);
        expect(refreshRect.right, 340);
        expect(topRect.bottom, 580);
        expect(topRect.top, greaterThan(refreshRect.bottom));
        await tester.tap(find.byTooltip('回到顶部'));
        await tester.pumpAndSettle();
        expect(_position(tester).pixels, 0);
        expect(find.byTooltip('回到顶部'), findsNothing);
        await _wheel(tester, 200);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('刷新列表'));
        await tester.pumpAndSettle();
        expect(repository.pages(section), [1, 1]);
        expect(_position(tester).pixels, 0);
        expect(find.text('刷新列表'), findsNothing);
        expect(find.byTooltip('回到顶部'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Widget _app(
  _HomeRepository repository,
  HomeChannel channel,
  String section, {
  ValueNotifier<bool>? active,
}) => ProviderScope(
  overrides: [homeRepositoryProvider.overrideWithValue(repository)],
  child: MaterialApp(
    home: Scaffold(
      body: active == null
          ? HomeContent(channel: channel, section: section, isSignedIn: true)
          : ValueListenableBuilder(
              valueListenable: active,
              builder: (context, value, child) => WorkspaceActivity(
                active: value,
                child: HomeContent(
                  channel: channel,
                  section: section,
                  isSignedIn: true,
                ),
              ),
            ),
    ),
  ),
);

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

Future<void> _wheel(WidgetTester tester, double delta) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: tester.getCenter(find.byType(CustomScrollView)),
      scrollDelta: Offset(0, delta),
    ),
  );
  await tester.pump();
}

final class _HomeRepository implements HomeRepository {
  _HomeRepository({
    this.itemCount = 1,
    this.hasMore = true,
    this.emptyFirst = false,
    this.holdAllPage = false,
    this.failPage = false,
  });
  final int itemCount;
  final bool hasMore;
  final bool emptyFirst;
  final bool holdAllPage;
  final bool failPage;
  bool _failed = false;
  final calls = <(HomeQuery, int)>[];
  final allPage = Completer<HomePage>();

  List<int> pages(String section) => [
    for (final call in calls)
      if (call.$1.section == section) call.$2,
  ];

  @override
  String get accountScope => 'test-account';

  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    calls.add((query, page));
    if (holdAllPage && query.section == '全部' && page == 2) {
      return allPage.future;
    }
    if (failPage && page == 2 && !_failed) {
      _failed = true;
      throw const AppFailure(AppFailureKind.network, '下一页暂时不可用');
    }
    return HomePage(
      [
        if (!emptyFirst || page != 1)
          for (var i = 0; i < itemCount; i++)
            HomeEntry(
              id: '${query.section}-$page-$i',
              title: '${query.section}-$page-$i',
              kind: query.channel == HomeChannel.dynamic
                  ? HomeEntryKind.dynamic
                  : query.channel == HomeChannel.videoDynamic
                  ? HomeEntryKind.video
                  : HomeEntryKind.season,
              description: query.channel == HomeChannel.dynamic
                  ? '${query.section}-$page-$i'
                  : '',
              dynamicPost: query.channel == HomeChannel.dynamic
                  ? DynamicPost(
                      id: '${query.section}-$page-$i',
                      text: '${query.section}-$page-$i',
                      authorName: '测试作者',
                    )
                  : null,
            ),
      ],
      hasMore: hasMore && page < 2,
      nextCursor: hasMore && page < 2 ? '${query.section}-page-$page' : null,
    );
  }
}

final class _FeedRepository implements FeedRepository {
  @override
  Future<List<VideoCategory>> loadCategories({
    required RequestCancellation cancellation,
  }) async => [];

  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) async => const PageResult(items: [], hasMore: false);

  @override
  Future<PageResult<VideoSummary>> loadPopular({
    required int page,
    required RequestCancellation cancellation,
  }) async => const PageResult(items: [], hasMore: false);
}
