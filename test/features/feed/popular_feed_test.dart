import 'dart:async';

import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/domain/popular_feed.dart';
import 'package:bilisail/features/feed/presentation/feed_screen.dart';
import 'package:bilisail/shared/ui/content_section_tabs.dart';
import 'package:bilisail/shared/ui/video_grid.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _Repository repository;
  setUp(() => repository = _Repository());

  Future<void> mount(
    WidgetTester tester, {
    HomeChannel channel = HomeChannel.popular,
    String? section,
    double scale = 1,
    ValueNotifier<bool>? active,
    ValueNotifier<String?>? liveSection,
    ValueChanged<HomeChannel>? onChannelChanged,
  }) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget body(String? current) => FeedScreen(
      channel: channel,
      initialSection: current,
      isSignedIn: true,
      showLiveSectionTabs: false,
      onSectionChanged: liveSection == null
          ? null
          : (value) => liveSection.value = value,
      onChannelChanged: onChannelChanged,
    );
    Widget content = liveSection == null
        ? body(section)
        : ValueListenableBuilder(
            valueListenable: liveSection,
            builder: (context, value, _) => body(value),
          );
    if (active != null) {
      final child = content;
      content = ValueListenableBuilder(
        valueListenable: active,
        builder: (context, value, _) =>
            WorkspaceActivity(active: value, child: child),
      );
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          feedRepositoryProvider.overrideWithValue(repository),
          homeRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(body: content),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester, PopularSection section) async {
    final target = find.byKey(ValueKey('home-section-${section.label}'));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('popular uses compact left-aligned text-only content tabs', (
    tester,
  ) async {
    await mount(tester);
    final strip = find.byKey(const ValueKey('home-section-strip-popular'));
    expect(tester.getSize(strip).height, 44);
    final tabs = find.byWidgetPredicate(
      (widget) => widget is ContentSectionTabs<PopularSection>,
    );
    expect(tabs, findsOneWidget);
    expect(tester.getSize(tabs).width, 1200);
    expect(tester.getRect(tabs).left, 0);
    expect(
      tester.getRect(find.byKey(const ValueKey('home-section-综合热门'))).left,
      12,
    );
    final colors = Theme.of(tester.element(tabs)).colorScheme;
    expect(
      find.descendant(of: tabs, matching: find.byType(Icon)),
      findsNothing,
    );
    for (final section in PopularSection.values) {
      final button = find.byKey(ValueKey('home-section-${section.label}'));
      final style = tester.widget<TextButton>(button).style;
      expect(style?.textStyle?.resolve({})?.fontSize, 13);
      expect(
        style?.foregroundColor?.resolve({}),
        section == PopularSection.all
            ? colors.primary
            : colors.onSurfaceVariant,
      );
      expect(style?.side?.resolve({}), isNull);
      expect(
        style?.backgroundColor?.resolve({WidgetState.hovered}),
        colors.surfaceContainerLow,
      );
      final semantics = tester.widget<Semantics>(
        find.ancestor(of: button, matching: find.byType(Semantics)).first,
      );
      expect(semantics.properties.selected, section == PopularSection.all);
    }
    expect(repository.calls, ['all']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bangumi reuses the same content section presentation', (
    tester,
  ) async {
    await mount(tester, channel: HomeChannel.bangumi);
    final tabs = find.byWidgetPredicate(
      (widget) => widget is ContentSectionTabs<String>,
    );
    expect(tabs, findsOneWidget);
    expect(tester.getSize(tabs).height, 44);
    final first = find.byKey(const ValueKey('home-section-推荐'));
    expect(tester.getRect(first).left, 12);
    expect(
      tester.widget<TextButton>(first).style?.textStyle?.resolve({})?.fontSize,
      13,
    );
    expect(
      find.descendant(of: tabs, matching: find.byType(Icon)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'popular retains grid delegates across activity and tab changes',
    (tester) async {
      final active = ValueNotifier(true);
      addTearDown(active.dispose);
      await mount(tester, active: active);
      final grid = tester.widget<SliverVideoGrid>(find.byType(SliverVideoGrid));
      final position = tester
          .widget<CustomScrollView>(
            find.byKey(const PageStorageKey('popular-all-null')),
          )
          .controller!
          .position;
      position.jumpTo(300);
      await tester.pumpAndSettle();
      var cardBuilds = 0;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        if (builtOnce && element.widget is VideoCard) cardBuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);
      active.value = false;
      await tester.pumpAndSettle();
      active.value = true;
      await tester.pumpAndSettle();
      expect(cardBuilds, 0);
      expect(tester.widget(find.byType(SliverVideoGrid)), same(grid));
      await select(tester, PopularSection.precious);
      await select(tester, PopularSection.all);
      expect(tester.widget(find.byType(SliverVideoGrid)), same(grid));
      expect(position.pixels, 300);
      expect(repository.calls.where((call) => call == 'all'), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'popular footer updates retain rows and appended data replaces them',
    (tester) async {
      repository.popularHasMore = true;
      await mount(tester);
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(FeedScreen)),
      ).read(feedControllerProvider.notifier);
      final grid = tester.widget<SliverVideoGrid>(find.byType(SliverVideoGrid));
      final pending = Completer<PageResult<VideoSummary>>();
      repository.nextPopular = pending;
      final request = controller.loadMore();
      await tester.pump();
      expect(tester.widget(find.byType(SliverVideoGrid)), same(grid));
      pending.completeError(StateError('offline'));
      await request;
      await tester.pumpAndSettle();
      expect(controller.state.pageError, isNotNull);
      expect(tester.widget(find.byType(SliverVideoGrid)), same(grid));
      final append = Completer<PageResult<VideoSummary>>();
      repository.nextPopular = append;
      final retry = controller.loadMore();
      await tester.pump();
      expect(tester.widget(find.byType(SliverVideoGrid)), same(grid));
      append.complete(
        const PageResult(
          items: [
            VideoSummary(
              id: VideoId('BV1234567890'),
              title: 'Appended',
              author: 'Author',
              coverUrl: '',
              duration: Duration.zero,
            ),
          ],
          hasMore: false,
        ),
      );
      await retry;
      await tester.pumpAndSettle();
      final updated = tester.widget<SliverVideoGrid>(
        find.byType(SliverVideoGrid),
      );
      expect(identical(updated, grid), isFalse);
      expect(updated.items, hasLength(61));
      expect(updated.items.last.title, 'Appended');
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(
        tester.widget<SliverVideoGrid>(find.byType(SliverVideoGrid)).items,
        hasLength(60),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('four sections are lazy and retained with the shared video grid', (
    tester,
  ) async {
    await mount(tester);
    expect(repository.calls, ['all']);
    for (final section in PopularSection.values) {
      await select(tester, section);
      expect(
        find.text(
          '${section == PopularSection.weekly ? 'week10' : section.name} video 0',
        ),
        findsOneWidget,
      );
    }
    for (final section in PopularSection.values) {
      await select(tester, section);
    }
    expect(
      repository.calls,
      unorderedEquals([
        'all',
        'directory',
        'week10',
        'precious',
        'regions',
        'ranking0',
      ]),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'weekly periods start at top and a cached period restores its scroll',
    (tester) async {
      await mount(tester, section: '每周必看');
      final old = tester
          .widget<CustomScrollView>(
            find.byKey(const PageStorageKey('popular-weekly-10')),
          )
          .controller!;
      old.jumpTo(400);
      await tester.pumpAndSettle();
      final offset = old.offset;
      tester
          .widget<DropdownButton<int>>(
            find.byKey(const ValueKey('popular-week-selector')),
          )
          .onChanged!(9);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CustomScrollView>(
              find.byKey(const PageStorageKey('popular-weekly-9')),
            )
            .controller!
            .offset,
        0,
      );
      tester
          .widget<DropdownButton<int>>(
            find.byKey(const ValueKey('popular-week-selector')),
          )
          .onChanged!(10);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CustomScrollView>(
              find.byKey(const PageStorageKey('popular-weekly-10')),
            )
            .controller!
            .offset,
        offset,
      );
      expect(repository.calls.where((call) => call == 'week10'), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ranking refresh reloads official regions and falls back from a removed region',
    (tester) async {
      await mount(tester, section: '排行榜');
      await tester.tap(find.byKey(const ValueKey('home-section-1008')));
      await tester.pumpAndSettle();
      expect(repository.calls.last, 'ranking1008');
      repository.regions = const [VideoCategory(id: '1005', name: '动画')];
      final container = ProviderScope.containerOf(
        tester.element(find.byType(FeedScreen)),
      );
      await container.read(feedControllerProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(repository.calls.where((call) => call == 'regions'), hasLength(2));
      expect(repository.calls.last, 'ranking0');
      expect(find.text('动画'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hidden ranking does not react to region removal until active again',
    (tester) async {
      final active = ValueNotifier(true);
      addTearDown(active.dispose);
      await mount(tester, section: '排行榜', active: active);
      await tester.tap(find.byKey(const ValueKey('home-section-1008')));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(FeedScreen)),
      );
      active.value = false;
      await tester.pumpAndSettle();
      final rankingCalls = repository.calls
          .where((call) => call.startsWith('ranking'))
          .length;
      repository.regions = const [];
      container.invalidate(rankingCategoriesProvider);
      await tester.pumpAndSettle();
      expect(
        repository.calls.where((call) => call.startsWith('ranking')),
        hasLength(rankingCalls),
      );
      active.value = true;
      await tester.pumpAndSettle();
      expect(repository.calls.last, 'ranking0');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'legacy ranking uses popular section without a duplicate primary page',
    (tester) async {
      await mount(
        tester,
        channel: HomeChannel.ranking,
        onChannelChanged: (_) {},
      );
      expect(find.byKey(const ValueKey('home-section-排行榜')), findsOneWidget);
      expect(repository.calls, unorderedEquals(['regions', 'ranking0']));
      expect(HomeChannel.primaryValues, isNot(contains(HomeChannel.ranking)));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop live suppresses duplicate tabs and obeys controlled re-entry',
    (tester) async {
      final section = ValueNotifier<String?>('我的关注');
      addTearDown(section.dispose);
      await mount(tester, channel: HomeChannel.live, liveSection: section);
      expect(
        find.byKey(const ValueKey('home-section-strip-live')),
        findsNothing,
      );
      expect(repository.homeSections, contains('我的关注'));
      section.value = null;
      await tester.pumpAndSettle();
      expect(repository.homeSections, contains('推荐'));
      section.value = '观看记录';
      await tester.pumpAndSettle();
      expect(repository.homeSections.last, '观看记录');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('four popular tabs fit narrow windows with large text', (
    tester,
  ) async {
    await mount(tester, scale: 2);
    tester.view.physicalSize = const Size(320, 568);
    await tester.pumpAndSettle();
    for (final section in PopularSection.values) {
      await select(tester, section);
      expect(
        find.byKey(ValueKey('home-section-${section.label}')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });
}

class _Repository
    implements
        FeedRepository,
        PopularFeedRepository,
        RankingFeedRepository,
        HomeRepository {
  final calls = <String>[];
  final homeSections = <String>[];
  bool popularHasMore = false;
  Completer<PageResult<VideoSummary>>? nextPopular;
  List<VideoCategory> regions = const [VideoCategory(id: '1008', name: '游戏')];
  @override
  String get accountScope => 'test';
  PageResult<VideoSummary> page(String name) => PageResult(
    items: [
      for (var index = 0; index < 60; index++)
        VideoSummary(
          id: VideoId('BV${index.toString().padLeft(10, '0')}'),
          title: '$name video $index',
          coverUrl: '',
          author: '作者',
          duration: Duration.zero,
        ),
    ],
    hasMore: false,
  );
  @override
  Future<List<VideoCategory>> loadCategories({
    required RequestCancellation cancellation,
  }) async => const [];
  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) async => this.page('recommended');
  @override
  Future<PageResult<VideoSummary>> loadPopular({
    required int page,
    required RequestCancellation cancellation,
  }) async {
    calls.add('all');
    if (page > 1 && nextPopular != null) return nextPopular!.future;
    return PageResult(items: this.page('all').items, hasMore: popularHasMore);
  }

  @override
  Future<List<PopularWeek>> loadPopularWeeks({
    required RequestCancellation cancellation,
  }) async {
    calls.add('directory');
    return const [
      PopularWeek(number: 10, name: '第10期'),
      PopularWeek(number: 9, name: '第9期'),
    ];
  }

  @override
  Future<PageResult<VideoSummary>> loadPopularWeek({
    required int number,
    required RequestCancellation cancellation,
  }) async {
    calls.add('week$number');
    return page('week$number');
  }

  @override
  Future<PageResult<VideoSummary>> loadPrecious({
    required RequestCancellation cancellation,
  }) async {
    calls.add('precious');
    return page('precious');
  }

  @override
  Future<List<VideoCategory>> loadRankingCategories({
    required RequestCancellation cancellation,
  }) async {
    calls.add('regions');
    return regions;
  }

  @override
  Future<PageResult<VideoSummary>> loadRanking({
    required String categoryId,
    required RequestCancellation cancellation,
  }) async {
    calls.add('ranking$categoryId');
    return page('ranking');
  }

  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    homeSections.add(query.section);
    return const HomePage([], hasMore: false);
  }
}
