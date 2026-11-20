import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/app/router.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/core/platform/external_links.dart';
import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/live/domain/live_room.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/pgc/domain/pgc_repository.dart';
import 'package:bilisail/features/search/application/search_controller.dart';
import 'package:bilisail/features/search/data/api_search_repository.dart';
import 'package:bilisail/features/search/domain/search_repository.dart';
import 'package:bilisail/features/search/domain/search_result.dart';
import 'package:bilisail/features/search/presentation/search_screen.dart';
import 'package:bilisail/features/search/presentation/search_category_bar.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:bilisail/shared/ui/bili_badges.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('HarmonyOS Sans')
      ..addFont(
        rootBundle.load(
          'assets/fonts/harmonyos_sans/HarmonyOS_Sans_SC_Regular.ttf',
        ),
      );
    await loader.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader(
      'BiliIcons',
    )..addFont(rootBundle.load('assets/fonts/biliicon.ttf'))).load();
  });

  testWidgets(
    'seven category tabs, counts, sorts and duration filter request page one',
    (tester) async {
      final repository = _Repository();
      await _mount(tester, repository);
      for (final category in SearchCategory.values) {
        expect(
          find.byKey(ValueKey('search-category-${category.name}')),
          findsOneWidget,
        );
      }
      expect(find.text('99+'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      await tester.tap(find.text('最多收藏'));
      await tester.pumpAndSettle();
      expect(repository.calls.last.order, SearchOrder.favorites);
      await tester.tap(find.byKey(const ValueKey('search-more-filters')));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      await tester.tap(find.text('60分钟以上'));
      await tester.tap(find.text('应用筛选'));
      await tester.pumpAndSettle();
      expect(repository.calls.last.duration, SearchDuration.overSixty);
      expect(repository.calls.last.page, 1);
      await tester.tap(find.byKey(const ValueKey('search-category-article')));
      await tester.pumpAndSettle();
      expect(find.text('最多阅读'), findsOneWidget);
      expect(find.text('最多弹幕'), findsNothing);
      await tester.tap(find.text('最多评论'));
      await tester.pumpAndSettle();
      expect(repository.calls.last.order, SearchOrder.comments);
      await tester.tap(find.byKey(const ValueKey('search-more-filters')));
      await tester.pumpAndSettle();
      final articleZone = SearchArticleZone.values.last;
      final articleZoneChoice = find.text(articleZone.label);
      await tester.ensureVisible(articleZoneChoice);
      await tester.tap(articleZoneChoice);
      await tester.tap(find.text('应用筛选'));
      await tester.pumpAndSettle();
      expect(repository.calls.last.articleZone, articleZone);
      await tester.tap(find.byTooltip('移除筛选：${articleZone.label}'));
      await tester.pumpAndSettle();
      expect(repository.calls.last.articleZone, SearchArticleZone.any);
      expect(repository.calls.last.order, SearchOrder.comments);
      await tester.tap(find.byKey(const ValueKey('search-category-user')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('粉丝数由低到高'));
      await tester.pumpAndSettle();
      expect(repository.calls.last.order, SearchOrder.fansAscending);
      await tester.tap(find.byKey(const ValueKey('search-more-filters')));
      await tester.pumpAndSettle();
      final type = SearchUserType.values.last;
      await tester.tap(find.text(type.label));
      await tester.tap(find.text('应用筛选'));
      await tester.pumpAndSettle();
      expect(repository.calls.last.userType, type);
      await tester.tap(find.byTooltip('移除筛选：${type.label}'));
      await tester.pumpAndSettle();
      expect(repository.calls.last.userType, SearchUserType.any);
      expect(repository.calls.last.order, SearchOrder.fansAscending);
      await tester.tap(find.byKey(const ValueKey('search-category-film')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-more-filters')), findsNothing);
    },
  );

  testWidgets(
    'mixed results render highlighted text and each content opens its own destination',
    (tester) async {
      final repository = _Repository();
      final urls = <Uri>[];
      final router = await _mount(tester, repository, urls: urls);
      expect(find.text('测试用户', findRichText: true), findsOneWidget);
      expect(find.text('查看TA的所有稿件 ›'), findsOneWidget);
      await tester.tap(find.text('进入主页 ›'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/user/42');
      for (final (category, title, path) in [
        (SearchCategory.video, '测试视频0', '/video/BV1000000000'),
        (SearchCategory.bangumi, '测试番剧', '/pgc/season/123'),
        (SearchCategory.film, '测试影视', '/pgc/season/456'),
        (SearchCategory.live, '测试直播', '/live/321'),
      ]) {
        router.go('/search');
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey('search-category-${category.name}')),
        );
        await tester.pumpAndSettle();
        final target = find.text(title, findRichText: true);
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, path);
      }
      router.go('/search');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('search-category-article')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('测试专栏', findRichText: true));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/article/789');
      expect(urls, isEmpty);
    },
  );

  for (final (size, scale) in [
    (const Size(420, 800), 1.0),
    (const Size(320, 700), 2.0),
  ]) {
    for (final mouseDrag in [false, true]) {
      testWidgets(
        'search categories reach later tabs with ${mouseDrag ? 'mouse drag' : 'wheel'} at $size scale $scale',
        (tester) async {
          final repository = _Repository();
          await _mount(tester, repository, size: size, scale: scale);
          ScrollPosition position(Finder strip) => tester
              .state<ScrollableState>(
                find.descendant(of: strip, matching: find.byType(Scrollable)),
              )
              .position;
          Future<void> move(Finder strip, {bool forward = true}) async {
            final direction = forward ? 1.0 : -1.0;
            if (mouseDrag) {
              await tester.dragFrom(
                tester.getCenter(strip),
                Offset(-2000 * direction, 0),
                kind: PointerDeviceKind.mouse,
              );
            } else {
              await tester.sendEventToBinding(
                PointerScrollEvent(
                  kind: PointerDeviceKind.mouse,
                  position: tester.getCenter(strip),
                  scrollDelta: Offset(0, 2000 * direction),
                ),
              );
            }
            await tester.pumpAndSettle();
          }

          final categories = find.byKey(
            const ValueKey('search-category-strip'),
          );
          final list = tester
              .widget<CustomScrollView>(find.byType(CustomScrollView))
              .controller!;
          expect(
            find.byKey(const ValueKey('search-order-strip')),
            findsNothing,
          );
          expect(position(categories).maxScrollExtent, greaterThan(0));
          await move(categories);
          expect(
            position(categories).pixels,
            position(categories).maxScrollExtent,
          );
          expect(list.offset, 0);
          await tester.tap(find.byKey(const ValueKey('search-category-user')));
          await tester.pumpAndSettle();
          expect(repository.calls.last.category, SearchCategory.user);
          await move(categories, forward: false);
          expect(position(categories).pixels, 0);
          await tester.tap(find.byKey(const ValueKey('search-category-all')));
          await tester.pumpAndSettle();
          expect(repository.calls.last.category, SearchCategory.all);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );
    }
  }

  testWidgets('resizing a search keeps the sort and result viewport', (
    tester,
  ) async {
    final repository = _Repository();
    await _mount(tester, repository, size: const Size(760, 800), scale: 2);
    final user = find.byKey(const ValueKey('search-category-user'));
    await tester.ensureVisible(user);
    await tester.tap(user);
    await tester.pumpAndSettle();
    final strip = find.byKey(const ValueKey('search-order-strip'));
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: strip, matching: find.byType(Scrollable)),
        )
        .position;
    expect(position.maxScrollExtent, greaterThan(0));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: tester.getCenter(strip),
        scrollDelta: const Offset(0, 2000),
      ),
    );
    await tester.pumpAndSettle();
    expect(position.pixels, position.maxScrollExtent);
    await tester.tap(find.text(SearchOrder.levelAscending.label));
    await tester.pumpAndSettle();
    expect(repository.calls.last.order, SearchOrder.levelAscending);
    final requests = repository.calls.length;
    ScrollController? resultScroll() => tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller;
    final controller = resultScroll();

    tester.view.physicalSize = const Size(760 - 1, 800);
    await tester.pumpAndSettle();
    expect(strip, findsNothing);
    expect(find.text(SearchOrder.levelAscending.label), findsOneWidget);
    expect(resultScroll(), same(controller));

    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(strip, findsOneWidget);
    expect(repository.calls.length, requests);
    expect(resultScroll(), same(controller));
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('compact filter sheet applies a draft once and supports reset', (
    tester,
  ) async {
    final repository = _Repository();
    await _mount(tester, repository, size: const Size(320, 568), scale: 2);
    final open = find.byKey(const ValueKey('search-more-filters'));
    final options = find.byKey(const ValueKey('search-filter-options'));
    final apply = find.text('应用筛选');
    final lastZone = SearchVideoZone.values.last;
    Future<void> choose(String label) async {
      final option = find.descendant(of: options, matching: find.text(label));
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pumpAndSettle();
    }

    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(apply.hitTestable(), findsOneWidget);
    expect(
      tester
          .state<ScrollableState>(
            find.descendant(of: options, matching: find.byType(Scrollable)),
          )
          .position
          .maxScrollExtent,
      greaterThan(0),
    );
    final callsBefore = repository.calls.length;
    await choose(SearchOrder.comments.label);
    await choose(SearchDuration.overSixty.label);
    await choose(SearchPublicationPeriod.week.label);
    await choose(lastZone.label);
    expect(repository.calls.length, callsBefore);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(repository.calls.length, callsBefore + 1);
    final applied = repository.calls.last;
    expect(applied.category, SearchCategory.all);
    expect(applied.order, SearchOrder.comments);
    expect(applied.duration, SearchDuration.overSixty);
    expect(applied.videoZone, lastZone);
    expect(applied.publicationRange, isNotNull);
    expect(applied.page, 1);
    final count = find.descendant(of: open, matching: find.text('4'));
    expect(count, findsOneWidget);

    await tester.tap(open);
    await tester.pumpAndSettle();
    await tester.tap(find.text('重置'));
    await tester.tap(find.byTooltip('关闭筛选'));
    await tester.pumpAndSettle();
    expect(repository.calls.length, callsBefore + 1);
    expect(count, findsOneWidget);

    final quickOrder = find.byKey(const ValueKey('search-quick-order'));
    await tester.tap(quickOrder);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭排序'));
    await tester.pumpAndSettle();
    expect(repository.calls.length, callsBefore + 1);
    await tester.tap(quickOrder);
    await tester.pumpAndSettle();
    final latest = find.widgetWithText(ListTile, SearchOrder.latest.label);
    await tester.ensureVisible(latest);
    await tester.tap(latest);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(repository.calls.length, callsBefore + 2);
    expect(repository.calls.last.order, SearchOrder.latest);
    expect(repository.calls.last.duration, applied.duration);
    expect(repository.calls.last.videoZone, applied.videoZone);
    expect(repository.calls.last.publicationRange, applied.publicationRange);

    await tester.tap(find.byTooltip('移除筛选：${applied.duration.label}'));
    await tester.tap(find.byTooltip('移除筛选：${lastZone.label}'));
    await tester.pumpAndSettle();
    expect(repository.calls.length, callsBefore + 4);
    expect(repository.calls.last.order, SearchOrder.latest);
    expect(repository.calls.last.duration, SearchDuration.any);
    expect(repository.calls.last.videoZone, SearchVideoZone.any);
    expect(repository.calls.last.publicationRange, applied.publicationRange);
    expect(repository.calls.last.page, 1);

    await tester.tap(open);
    await tester.pumpAndSettle();
    await tester.tap(find.text('重置'));
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(repository.calls.length, callsBefore + 5);
    expect(repository.calls.last.order, SearchOrder.relevance);
    expect(repository.calls.last.duration, SearchDuration.any);
    expect(repository.calls.last.videoZone, SearchVideoZone.any);
    expect(repository.calls.last.publicationRange, isNull);
    expect(find.text('筛选'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom publication range is confirmed with the filter draft', (
    tester,
  ) async {
    final repository = _Repository();
    await _mount(tester, repository, size: const Size(360, 640));
    final open = find.byKey(const ValueKey('search-more-filters'));
    await tester.tap(open);
    await tester.pumpAndSettle();
    final dateChoice = find.text(SearchPublicationPeriod.customRange.label);
    await tester.ensureVisible(dateChoice);
    await tester.tap(dateChoice);
    await tester.pumpAndSettle();
    final picker = find.byType(DateRangePickerDialog);
    await tester.tap(
      find.byTooltip(
        MaterialLocalizations.of(tester.element(picker))
            .inputDateModeButtonLabel,
      ),
    );
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: picker,
      matching: find.byType(TextField),
    );
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.first, '1/10/2025');
    await tester.enterText(fields.last, '2/15/2025');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(repository.calls.last.publicationRange, isNull);
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    final range = repository.calls.last.publicationRange;
    expect(range?.start, DateTime(2025, 1, 10));
    expect(range?.end, DateTime(2025, 2, 15));
    expect(find.descendant(of: open, matching: find.text('1')), findsOneWidget);
    final dateTag = find.byTooltip(RegExp('移除筛选'));
    await tester.tap(dateTag);
    await tester.pumpAndSettle();
    expect(repository.calls.last.publicationRange, isNull);
    expect(dateTag, findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final (count, label) in [(14010, '1.4万'), (0, '0'), (null, '—')]) {
    testWidgets(
      'featured UP preview maps dm=$count through to the video card',
      (tester) async {
        final requests = ApiRequests();
        final api = BiliApiClient(
          transport: _PreviewTransport(count),
          sessionProvider: requests,
        );
        addTearDown(api.close);
        await _mount(
          tester,
          ApiSearchRepository(api, requests),
          size: const Size(420, 800),
        );
        final card = find.byType(VideoCard);
        expect(card, findsOneWidget);
        expect(tester.widget<VideoCard>(card).video.danmakuCount, count);
        expect(find.byType(BiliUpBadge), findsNothing);
        expect(
          find.descendant(of: card, matching: find.text(label)),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final (size, scale) in [
    (const Size(1895, 927), 1.0),
    (const Size(1440, 900), 1.0),
    (const Size(360, 640), 1.0),
    (const Size(320, 568), 2.0),
  ]) {
    testWidgets(
      'search layout fits $size at text scale $scale including filters',
      (tester) async {
        await _mount(tester, _Repository(), size: size, scale: scale);
        expect(tester.takeException(), isNull);
        await _snapshot(tester, '${size.width.toInt()}-${scale.toInt()}');
        await tester.tap(find.byKey(const ValueKey('search-more-filters')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('全部时长'), findsOneWidget);
        await _snapshot(
          tester,
          '${size.width.toInt()}-${scale.toInt()}-filters',
        );
      },
    );
  }

  for (final (size, scale) in [
    (const Size(1440, 900), 1.0),
    (const Size(1000, 800), 1.0),
    (const Size(360, 640), 1.0),
    (const Size(320, 568), 2.0),
  ]) {
    testWidgets('workspace search header fits $size at scale $scale', (
      tester,
    ) async {
      final repository = _Repository();
      await _mount(
        tester,
        repository,
        size: size,
        scale: scale,
        workspace: true,
      );
      final strip = find.byKey(const ValueKey('search-category-strip'));
      final search = find.byKey(const ValueKey('workspace-search'));
      expect(find.byKey(const ValueKey('home-channel-strip')), findsNothing);
      expect(
        find.descendant(
          of: find.byType(SearchScreen),
          matching: find.byType(SearchCategoryBar),
        ),
        findsNothing,
      );
      expect(strip, findsOneWidget);
      expect(search, findsOneWidget);
      if (size.width >= 760) {
        expect(tester.getCenter(strip).dy, tester.getCenter(search).dy);
      } else {
        expect(
          tester.getTopLeft(strip).dy,
          greaterThan(tester.getBottomLeft(search).dy),
        );
      }
      await _snapshot(
        tester,
        'workspace-${size.width.toInt()}-${scale.toInt()}',
      );
      if (size.width < 760) {
        final scrollable = tester.state<ScrollableState>(
          find.descendant(of: strip, matching: find.byType(Scrollable)),
        );
        expect(scrollable.position.maxScrollExtent, greaterThan(0));
        await tester.sendEventToBinding(
          PointerScrollEvent(
            kind: PointerDeviceKind.mouse,
            position: tester.getCenter(strip),
            scrollDelta: const Offset(0, 2000),
          ),
        );
        await tester.pumpAndSettle();
        expect(scrollable.position.pixels, scrollable.position.maxScrollExtent);
        await tester.tap(find.byKey(const ValueKey('search-category-user')));
        await tester.pumpAndSettle();
        expect(repository.calls.last.category, SearchCategory.user);
      }
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }

  for (final width in [320.0, 390.0, 1895.0]) {
    testWidgets('search video cards fill the available width at $width', (
      tester,
    ) async {
      await _mount(tester, _Repository(), size: Size(width, 927));
      await tester.tap(find.byKey(const ValueKey('search-category-video')));
      await tester.pumpAndSettle();
      final cards = find.byType(VideoCard);
      final compact = width < 600;
      final columns = compact ? 2 : 6;
      final inset = compact ? 4.0 : 28.0;
      final gap = compact ? 6.0 : 20.0;
      final first = tester.getRect(cards.first);
      final last = tester.getRect(cards.at(columns - 1));
      final next = tester.getRect(cards.at(columns));
      expect(
        first.width,
        closeTo((width - inset * 2 - (columns - 1) * gap) / columns, .01),
      );
      expect(first.left, inset);
      expect(last.right, closeTo(width - inset, .01));
      expect(last.top, first.top);
      expect(next.top - first.bottom, closeTo(compact ? 16 : 24, .01));
      expect(find.byType(BiliUpBadge), findsNothing);
      await _snapshot(tester, '${width.toInt()}-video-grid');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'sort change starts at the top even with a retained page storage key',
    (tester) async {
      await _mount(tester, _Repository());
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
      await tester.pumpAndSettle();
      ScrollController? scroll() => tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller;
      expect(scroll()?.offset, greaterThan(0));
      await tester.tap(find.text('最新发布'));
      await tester.pumpAndSettle();
      expect(scroll()?.offset, 0);
    },
  );
}

Future<GoRouter> _mount(
  WidgetTester tester,
  SearchRepository repository, {
  Size size = const Size(1400, 900),
  double scale = 1,
  List<Uri>? urls,
  bool workspace = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final router = workspace
      ? createBiliRouter(
          initialLocation: '/search?q=测试',
          playerBuilder: (_, _, _) => const SizedBox.shrink(),
        )
      : GoRouter(
          initialLocation: '/search',
          routes: [
            GoRoute(
              path: '/search',
              builder: (_, _) => const Scaffold(
                body: Column(
                  children: [
                    SearchCategoryBar(),
                    Expanded(
                      child: SearchScreen(
                        key: PageStorageKey('fixture-search'),
                        query: '测试',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            for (final path in [
              '/user/:id',
              '/video/:id',
              '/pgc/season/:id',
              '/live/:id',
              '/article/:id',
            ])
              GoRoute(
                path: path,
                builder: (_, state) => Scaffold(body: Text(state.uri.path)),
              ),
          ],
        );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (workspace) ...[
          feedRepositoryProvider.overrideWithValue(_FeedRepository()),
          homeRepositoryProvider.overrideWithValue(_HomeRepository()),
        ],
        searchRepositoryProvider.overrideWithValue(repository),
        externalLinkOpenerProvider.overrideWithValue((uri) async {
          urls?.add(uri);
          return true;
        }),
      ],
      child: MaterialApp.router(
        theme: BiliTheme.light(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(
            key: const ValueKey('search-preview'),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

final class _PreviewTransport implements ApiTransport {
  const _PreviewTransport(this.danmakuCount);
  final int? danmakuCount;

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    final Object data;
    if (uri.path.endsWith('/nav')) {
      data = {
        'wbi_img': {
          'img_url': 'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
          'sub_url': 'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
        },
      };
    } else if (uri.path.endsWith('/all/v2')) {
      data = {
        'result': [
          {
            'result_type': 'bili_user',
            'data': [
              {
                'mid': 42,
                'uname': '测试用户',
                'res': [
                  {
                    'bvid': 'BV1sS4y1t7ce',
                    'title': '测试预览视频',
                    'play': '5506056',
                    'duration': '05:30',
                    if (danmakuCount != null) 'dm': danmakuCount,
                  },
                ],
              },
            ],
          },
        ],
      };
    } else {
      data = {'numResults': 0, 'numPages': 0, 'result': []};
    }
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
      const {},
    );
  }
}

final class _FeedRepository implements FeedRepository {
  @override
  Future<List<VideoCategory>> loadCategories({
    required RequestCancellation cancellation,
  }) async => const [];

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

final class _HomeRepository implements HomeRepository {
  @override
  String get accountScope => 'guest';

  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async => const HomePage([], hasMore: false);
}

Future<void> _snapshot(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('SEARCH_PREVIEW')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('search-preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('Preview encoding failed');
    await Directory('build/search-preview').create(recursive: true);
    await File('build/search-preview/$name.png')
        .writeAsBytes(bytes.buffer.asUint8List());
    image.dispose();
  });
}

final class _Call {
  const _Call(
    this.category,
    this.order,
    this.duration,
    this.userType,
    this.page,
    this.videoZone,
    this.articleZone,
    this.publicationRange,
  );
  final SearchCategory category;
  final SearchOrder order;
  final SearchDuration duration;
  final SearchUserType userType;
  final int page;
  final SearchVideoZone videoZone;
  final SearchArticleZone articleZone;
  final SearchPublicationRange? publicationRange;
}

final class _Repository implements SearchRepository {
  final calls = <_Call>[];
  @override
  Future<SearchPage> search({
    required String query,
    required int page,
    required SearchCategory category,
    required SearchOrder order,
    required SearchDuration duration,
    required SearchUserType userType,
    SearchVideoZone videoZone = SearchVideoZone.any,
    SearchArticleZone articleZone = SearchArticleZone.any,
    SearchPublicationRange? publicationRange,
    required RequestCancellation cancellation,
  }) async {
    calls.add(
      _Call(
        category,
        order,
        duration,
        userType,
        page,
        videoZone,
        articleZone,
        publicationRange,
      ),
    );
    return SearchPage(
      items: _items
          .where(
            (item) =>
                category == SearchCategory.all || item.category == category,
          )
          .toList(),
      hasMore: false,
      counts: const {
        SearchCategory.video: 123,
        SearchCategory.user: 3,
        SearchCategory.bangumi: 0,
        SearchCategory.film: 1,
        SearchCategory.live: 3,
        SearchCategory.article: 2,
      },
    );
  }
}

final _items = <SearchEntry>[
  SearchUserEntry(
    id: const UserId('42'),
    name: '测试用户',
    signature: '分享知识与有趣的故事',
    fans: 10912000,
    videoCount: 264,
    level: 6,
    videos: List.generate(3, _video),
  ),
  const SearchMediaEntry(
    id: PgcSeasonId('123'),
    title: '测试番剧',
    category: SearchCategory.bangumi,
    description: '这里是番剧的简介。',
    areas: '日本',
    styles: '推理 · 日常',
    updateText: '更新至12话',
    score: 9.5,
  ),
  const SearchMediaEntry(
    id: PgcSeasonId('456'),
    title: '测试影视',
    category: SearchCategory.film,
    description: '这里是影视的简介。',
  ),
  const SearchLiveEntry(
    id: RoomId('321'),
    title: '测试直播',
    author: '主播',
    area: '游戏',
    online: 12000,
    isLive: true,
  ),
  const SearchArticleEntry(
    id: ArticleId('789'),
    title: '测试专栏',
    author: '作者',
    views: 23000,
    likes: 123,
    replies: 22,
    description: '分享技术、生活和创作中的点滴。',
  ),
  for (var i = 0; i < 10; i++) SearchVideoEntry(_video(i)),
];
VideoSummary _video(int i) => VideoSummary(
  id: VideoId('BV1${i.toString().padLeft(9, '0')}'),
  title: '测试视频$i',
  coverUrl: '',
  author: '测试UP主',
  authorId: const UserId('42'),
  duration: const Duration(minutes: 37, seconds: 35),
  playCount: 3616000,
  danmakuCount: 23000,
  publishedAt: DateTime(2026, 9, 25),
);
