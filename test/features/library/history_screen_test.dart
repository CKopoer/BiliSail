import 'dart:async';

import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/library/application/library_controller.dart';
import 'package:bilisail/features/library/domain/library_repository.dart';
import 'package:bilisail/features/library/presentation/history_screen.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';
import 'package:go_router/go_router.dart';

void main() {
  for (final config in [
    (width: 320.0, scale: 2.0, platform: TargetPlatform.android),
    (width: 390.0, scale: 1.0, platform: TargetPlatform.iOS),
    (width: 1280.0, scale: 1.0, platform: TargetPlatform.windows),
  ]) {
    testWidgets(
      'history search submits, clears and fits ${config.platform} / ${config.width}',
      (tester) async {
        tester.view.physicalSize = Size(config.width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = _HistoryRepository(_entries());
        await _pump(
          tester,
          repository,
          platform: config.platform,
          scale: config.scale,
          showHeading: false,
        );
        final field = find.byKey(const ValueKey('history-search'));
        final clear = find.byKey(const ValueKey('history-clear'));
        final available = config.width - (config.width < 600 ? 8 : 40);
        expect(
          tester.getSize(field).width,
          closeTo(config.width >= 840 * config.scale ? 320 : available, 1),
        );
        if (config.width < 840 * config.scale) {
          expect(
            tester.getRect(field).top,
            greaterThanOrEqualTo(tester.getRect(clear).bottom),
          );
        } else {
          expect(
            (tester.getCenter(field).dy - tester.getCenter(clear).dy).abs(),
            lessThan(1),
          );
        }
        await tester.enterText(field, '  Flutter  ');
        await tester.pump();
        expect(repository.keywords, ['']);
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(repository.keywords, ['', 'Flutter']);
        expect(find.byType(VideoCard), findsOneWidget);
        expect(tester.widget<TextField>(field).controller!.text, 'Flutter');
        final container = ProviderScope.containerOf(tester.element(field));
        await container.read(historyProvider.notifier).refresh();
        await tester.pumpAndSettle();
        expect(repository.keywords.last, 'Flutter');
        expect(tester.widget<TextField>(field).controller!.text, 'Flutter');
        await tester.tap(find.byTooltip('清除搜索'));
        await tester.pumpAndSettle();
        expect(repository.keywords.last, '');
        expect(find.byType(VideoCard), findsNWidgets(2));
        expect(tester.widget<TextField>(field).controller!.text, '');
        await tester.enterText(field, '不存在');
        await tester.pump();
        await tester.tap(find.byTooltip('搜索观看历史'));
        await tester.pumpAndSettle();
        expect(repository.keywords.last, '不存在');
        expect(find.text('未找到相关观看记录，试试其他关键词'), findsOneWidget);
        expect(find.byType(VideoCard), findsNothing);
        await tester.tap(clear);
        await tester.pumpAndSettle();
        expect(find.textContaining('全部云端观看历史'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(repository.clears, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final config in [
    (width: 320.0, platform: TargetPlatform.android, scale: 2.0),
    (width: 390.0, platform: TargetPlatform.iOS, scale: 1.0),
    (width: 360.0, platform: TargetPlatform.windows, scale: 2.0),
    (width: 600.0, platform: TargetPlatform.windows, scale: 1.0),
    (width: 1280.0, platform: TargetPlatform.macOS, scale: 1.0),
    (width: 960.0, platform: TargetPlatform.linux, scale: 1.0),
  ]) {
    testWidgets(
      'history actions fit ${config.platform} at ${config.width} / ${config.scale}',
      (tester) async {
        tester.view.physicalSize = Size(config.width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = _HistoryRepository(_entries());
        await _pump(
          tester,
          repository,
          platform: config.platform,
          scale: config.scale,
          showHeading: config.width < 600,
        );
        final clear = find.byKey(const ValueKey('history-clear'));
        final inset = config.width < 600 ? 4 : 20;
        final showClearLabel = config.width - 2 * inset >= 280 * config.scale;
        expect(
          tester.widget(clear),
          showClearLabel ? isA<TextButton>() : isA<IconButton>(),
        );
        expect(tester.getSize(clear).height, greaterThanOrEqualTo(48));
        final menus = find.byKey(const ValueKey('video-card-title-menu'));
        if (config.platform != TargetPlatform.android &&
            config.platform != TargetPlatform.iOS) {
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          addTearDown(mouse.removePointer);
          await mouse.addPointer(location: Offset.zero);
          await mouse.moveTo(tester.getCenter(find.byType(VideoCard).at(1)));
          await tester.pumpAndSettle();
        }
        await tester.tap(menus.at(1));
        await tester.pumpAndSettle();
        expect(find.text('删除记录'), findsOneWidget);
        await tester.tap(find.text('删除记录'));
        await tester.pumpAndSettle();
        expect(repository.deleted, ['pgc_102']);
        expect(find.byType(VideoCard), findsOneWidget);
        expect(
          tester.widget<VideoCard>(find.byType(VideoCard)).publishTooltip,
          '观看于 2026-10-05 00:00',
        );
        await tester.tap(clear);
        await tester.pumpAndSettle();
        expect(find.text('清空观看历史？'), findsOneWidget);
        expect(repository.clears, 0);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(repository.clears, 0);
        await tester.tap(clear);
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认清空'));
        await tester.pumpAndSettle();
        expect(repository.clears, 1);
        expect(find.text('还没有云端观看记录'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final config in [
    (width: 320.0, scale: 1.0),
    (width: 402.0, scale: 1.0),
    (width: 600.0, scale: 1.0),
    (width: 960.0, scale: 1.0),
    (width: 320.0, scale: 2.0),
    (width: 402.0, scale: 2.0),
  ]) {
    testWidgets(
      'embedded history toolbar aligns at ${config.width} / ${config.scale}',
      (tester) async {
        tester.view.physicalSize = Size(config.width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await _pump(
          tester,
          _HistoryRepository(_entries()),
          platform: TargetPlatform.windows,
          scale: config.scale,
          showHeading: false,
        );
        final caption = find.text(
          config.width - (config.width < 600 ? 8 : 40) < 600
              ? '云端观看记录'
              : '当前账号的云端观看记录',
        );
        final clear = find.byKey(const ValueKey('history-clear'));
        expect(
          (tester.getCenter(caption).dy - tester.getCenter(clear).dy).abs(),
          lessThan(1),
        );
        expect(
          tester.getRect(find.byType(VideoCard).first).top -
              tester
                  .getRect(find.byKey(const ValueKey('history-search')))
                  .bottom,
          closeTo(8, 1),
        );
        if (config.scale == 1) expect(find.text('清空历史'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final clear in [false, true]) {
    testWidgets(
      '${clear ? 'clear' : 'delete'} failure retains cards and reports the error',
      (tester) async {
        final repository = _HistoryRepository(_entries())
          ..failure = const AppFailure(AppFailureKind.permission, '操作被拒绝');
        await _pump(tester, repository);
        if (clear) {
          await tester.tap(find.byKey(const ValueKey('history-clear')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('确认清空'));
        } else {
          await tester.tap(
            find.byKey(const ValueKey('video-card-title-menu')).first,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('删除记录'));
        }
        await tester.pumpAndSettle();
        expect(find.byType(VideoCard), findsNWidgets(2));
        expect(find.text('操作被拒绝'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('pending clear disables card menus and the clear button', (
    tester,
  ) async {
    final repository = _HistoryRepository(_entries())
      ..pending = Completer<void>();
    await _pump(tester, repository);
    await tester.tap(find.byKey(const ValueKey('history-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认清空'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('history-clear')))
          .onPressed,
      isNull,
    );
    for (final menu in tester.widgetList<PopupMenuButton<VideoCardMenuAction>>(
      find.byType(PopupMenuButton<VideoCardMenuAction>),
    )) {
      expect(menu.enabled, false);
    }
    repository.pending?.complete();
    await tester.pumpAndSettle();
    expect(find.text('还没有云端观看记录'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final change in ['scope', 'epoch', 'hidden']) {
    testWidgets('clear confirmation cannot affect another $change', (
      tester,
    ) async {
      final repository = _HistoryRepository(_entries());
      var epoch = 0;
      var active = true;
      late StateSetter update;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            libraryRepositoryProvider.overrideWithValue(repository),
            sessionEpochProvider.overrideWithValue(() => epoch),
          ],
          child: MaterialApp(
            builder: AppNoticeHost.builder,
            home: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return WorkspaceActivity(
                  active: active,
                  child: const Scaffold(body: HistoryScreen()),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('history-clear')));
      await tester.pumpAndSettle();
      if (change == 'scope') repository.accountScope = 'user:2';
      if (change == 'epoch') epoch++;
      if (change == 'hidden') update(() => active = false);
      await tester.pump();
      await tester.tap(find.text('确认清空'));
      await tester.pumpAndSettle();
      expect(repository.clears, 0);
      expect(find.byType(VideoCard), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final pgc in [false, true]) {
    testWidgets('history preserves each ${pgc ? 'episode' : 'part'} identity', (
      tester,
    ) async {
      const video = VideoSummary(
        id: VideoId('BV1234567890'),
        title: '同一视频的两条历史',
        coverUrl: '',
        author: '作者',
        duration: Duration(seconds: 100),
        playCount: 12345,
        danmakuCount: 0,
      );
      final entries = [
        for (var index = 1; index <= 2; index++)
          WatchHistoryEntry(
            video: video,
            part: VideoPart(
              cid: '$index',
              page: index,
              title: '第 $index 集',
              duration: const Duration(seconds: 100),
            ),
            episodeId: pgc ? '${100 + index}' : null,
            position: Duration(seconds: index * 20),
            watchedAt: DateTime(2026, 10, 5),
          ),
      ];
      final router = GoRouter(
        initialLocation: '/history',
        routes: [
          GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
          for (final path in ['/video/:id', '/pgc/episode/:id'])
            GoRoute(path: path, builder: (_, _) => const Text('播放目的地')),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            libraryRepositoryProvider.overrideWithValue(
              _HistoryRepository(entries),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      final cards = find.byType(VideoCard);
      expect(tester.widget<VideoCard>(cards.at(0)).progress, 0.2);
      expect(tester.widget<VideoCard>(cards.at(1)).progress, 0.4);
      expect(find.text('当前账号的云端观看记录'), findsOneWidget);
      expect(
        tester.widget<VideoCard>(cards.at(0)).publishTooltip,
        '观看于 2026-10-05 00:00',
      );
      expect(
        tester.widget<VideoCard>(cards.at(0)).publishText,
        DateTime.now().year == 2026 ? '10-05' : '2026-10-05',
      );
      expect(find.text('1.2万'), findsNWidgets(2));
      expect(find.text('0'), findsNWidgets(2));
      await tester.tap(cards.at(1));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri, entries[1].location);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

Future<void> _pump(
  WidgetTester tester,
  _HistoryRepository repository, {
  TargetPlatform platform = TargetPlatform.android,
  double scale = 1,
  bool showHeading = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [libraryRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: ThemeData(platform: platform),
        builder: (context, child) => AppNoticeHost(
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child ?? const SizedBox(),
          ),
        ),
        home: Scaffold(body: HistoryScreen(showHeading: showHeading)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<WatchHistoryEntry> _entries() => [
  for (var i = 1; i <= 2; i++)
    WatchHistoryEntry(
      video: const VideoSummary(
        id: VideoId('BV1234567890'),
        title: '历史记录菜单测试',
        coverUrl: '',
        author: '作者',
        duration: Duration(seconds: 100),
      ),
      part: VideoPart(
        cid: '$i',
        page: i,
        title: '第 $i 集',
        duration: const Duration(seconds: 100),
      ),
      episodeId: i == 2 ? '102' : null,
      deletionKey: i == 2 ? 'pgc_102' : 'archive_101',
      position: const Duration(seconds: 20),
      watchedAt: DateTime(2026, 10, 5),
    ),
];

final class _HistoryRepository
    implements LibraryRepository, WatchHistoryMutations {
  _HistoryRepository(this.entries);
  final List<WatchHistoryEntry> entries;
  @override
  String accountScope = 'user:1';
  final deleted = <String>[];
  final keywords = <String>[];
  int clears = 0;
  AppFailure? failure;
  Completer<void>? pending;
  Future<void> _result() async {
    if (failure case final error?) throw error;
    await pending?.future;
  }

  @override
  Future<void> deleteHistory(
    String deletionKey, {
    required RequestCancellation cancellation,
  }) async {
    deleted.add(deletionKey);
    await _result();
  }

  @override
  Future<void> clearHistory({required RequestCancellation cancellation}) async {
    clears++;
    await _result();
  }

  @override
  Future<WatchHistoryPage> loadHistory({
    String keyword = '',
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    keywords.add(keyword);
    return WatchHistoryPage(
      keyword.isEmpty
          ? entries
          : keyword == 'Flutter'
          ? entries.take(1).toList()
          : const [],
      hasMore: false,
    );
  }
}
