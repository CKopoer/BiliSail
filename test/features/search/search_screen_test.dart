import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/platform/external_links.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/live/domain/live_room.dart';
import 'package:bilisail/features/pgc/domain/pgc_repository.dart';
import 'package:bilisail/features/search/application/search_controller.dart';
import 'package:bilisail/features/search/domain/search_repository.dart';
import 'package:bilisail/features/search/domain/search_result.dart';
import 'package:bilisail/features/search/presentation/search_screen.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:bilisail/shared/ui/bili_badges.dart';
import 'package:flutter/material.dart';
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
      await tester.tap(find.text('60分钟以上'));
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
      await tester.tap(find.byKey(const ValueKey('search-category-user')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('粉丝数由低到高'));
      await tester.pumpAndSettle();
      expect(repository.calls.last.order, SearchOrder.fansAscending);
      await tester.tap(find.byKey(const ValueKey('search-more-filters')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('UP主'));
      await tester.pumpAndSettle();
      expect(repository.calls.last.userType, SearchUserType.uploader);
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
      expect(urls.single, Uri.parse('https://www.bilibili.com/read/cv789'));
    },
  );

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
      },
    );
  }

  testWidgets('search uses full width and shared five-column video cards', (
    tester,
  ) async {
    await _mount(tester, _Repository(), size: const Size(1895, 927));
    await tester.tap(find.byKey(const ValueKey('search-category-video')));
    await tester.pumpAndSettle();
    final cards = find.byType(VideoCard);
    expect(cards, findsNWidgets(10));
    final first = tester.getRect(cards.first);
    final fifth = tester.getRect(cards.at(4));
    final sixth = tester.getRect(cards.at(5));
    expect(first.width, greaterThan(350));
    expect(first.left, 28);
    expect(fifth.right, 1895 - 28);
    expect(fifth.top, first.top);
    expect(sixth.top, greaterThan(first.bottom));
    expect(find.byType(BiliUpBadge), findsNWidgets(10));
    await _snapshot(tester, '1895-video-grid');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sort change starts at the top even with a retained page storage key',
    (tester) async {
      await _mount(tester, _Repository());
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      ScrollController? scroll() =>
          tester.widget<ListView>(find.byType(ListView)).controller;
      expect(scroll()?.offset, greaterThan(0));
      await tester.tap(find.text('最新发布'));
      await tester.pumpAndSettle();
      expect(scroll()?.offset, 0);
    },
  );
}

Future<GoRouter> _mount(
  WidgetTester tester,
  _Repository repository, {
  Size size = const Size(1400, 900),
  double scale = 1,
  List<Uri>? urls,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final router = GoRouter(
    initialLocation: '/search',
    routes: [
      GoRoute(
        path: '/search',
        builder: (_, _) => const Scaffold(
          body: SearchScreen(
            key: PageStorageKey('fixture-search'),
            query: '测试',
          ),
        ),
      ),
      for (final path in [
        '/user/:id',
        '/video/:id',
        '/pgc/season/:id',
        '/live/:id',
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
  );
  final SearchCategory category;
  final SearchOrder order;
  final SearchDuration duration;
  final SearchUserType userType;
  final int page;
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
    required RequestCancellation cancellation,
  }) async {
    calls.add(_Call(category, order, duration, userType, page));
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
