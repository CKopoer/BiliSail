import 'dart:async';

import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/home_feed_cards.dart';
import 'package:bilisail/features/live/application/live_card_preview_controller.dart';
import 'package:bilisail/features/library/domain/library_repository.dart';
import 'package:bilisail/features/library/presentation/history_content_card.dart';
import 'package:bilisail/features/live/domain/live_room.dart';
import 'package:bilisail/features/playback/application/card_preview_playback.dart';
import 'package:bilisail/features/search/domain/search_result.dart';
import 'package:bilisail/features/search/presentation/search_results.dart';
import 'package:bilisail/shared/ui/live_card_preview_scope.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/live_card_preview_fakes.dart';
import '../../support/video_card_fake_engine.dart';

const _owner = ValueKey('live-card-hover-preview');
const _preview = ValueKey('live-card-preview');
const _scale = ValueKey('live-card-cover-scale');

void main() {
  late LivePreviewFakeRepository repository;
  late CardPreviewPlayback playback;
  late LiveCardPreviewController controller;
  late List<CardFakeEngine> engines;
  late bool waitForOpen;
  var initialized = false;
  setUp(() {
    repository = LivePreviewFakeRepository();
    engines = [];
    waitForOpen = false;
    initialized = false;
  });
  tearDown(() {
    if (!initialized) return;
    controller.dispose();
    unawaited(playback.close());
  });

  Widget app({
    bool enabled = true,
    bool active = true,
    bool ticker = true,
    String room = '12',
    VoidCallback? onTap,
    ScrollController? scroll,
    Widget? card,
  }) {
    if (!initialized) {
      initialized = true;
      playback = CardPreviewPlayback(
        createEngine: () {
          final engine = CardFakeEngine();
          if (waitForOpen) engine.opening = Completer<void>();
          engines.add(engine);
          return engine;
        },
      );
      controller = LiveCardPreviewController(
        repository: repository,
        playback: playback,
      );
    }
    return MaterialApp(
      theme: BiliTheme.light(),
      home: Scaffold(
        body: LiveCardPreviewScope(
          controller: controller,
          enabled: enabled,
          child: WorkspaceActivity(
            active: active,
            child: TickerMode(
              enabled: ticker,
              child: SingleChildScrollView(
                controller: scroll,
                child: SizedBox(
                  height: 1200,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: 320,
                      child:
                          card ??
                          LiveRoomCard(
                            entry: HomeEntry(
                              id: room,
                              kind: HomeEntryKind.live,
                              title: '直播标题',
                              authorName: '主播',
                              areaName: '游戏',
                            ),
                            onTap: onTap ?? () {},
                          ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<TestGesture> hover(WidgetTester tester, {bool title = false}) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 500));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(title ? find.text('直播标题') : find.byKey(_scale)),
    );
    await tester.pump();
    return mouse;
  }

  Future<void> loaded(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  for (final kind in ['search', 'history']) {
    for (final isLive in [true, false]) {
      testWidgets('$kind live card respects known offline state: $isLive', (
        tester,
      ) async {
        final card = kind == 'search'
            ? ProviderScope(
                child: SizedBox(
                  height: 400,
                  child: CustomScrollView(
                    slivers: [
                      SearchResults(
                        items: [
                          SearchLiveEntry(
                            id: const RoomId('12'),
                            title: '直播标题',
                            author: '主播',
                            isLive: isLive,
                          ),
                        ],
                        query: '',
                        category: SearchCategory.live,
                        onCategory: (_) {},
                      ),
                    ],
                  ),
                ),
              )
            : HistoryContentCard(
                entry: WatchHistoryEntry.content(
                  type: HistoryContentType.live,
                  id: '12',
                  title: '直播标题',
                  coverUrl: '',
                  author: '主播',
                  watchedAt: DateTime(2026, 11, 14),
                  isLive: isLive,
                ),
                date: '今天',
                dateTooltip: '今天',
                onOpen: () {},
                onDelete: null,
              );
        await tester.pumpWidget(app(card: card));
        await hover(tester);
        await loaded(tester);
        expect(repository.rooms.length, isLive ? 1 : 0);
        expect(find.byKey(_preview), isLive ? findsOneWidget : findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets(
    'title hover waits, fades first frame, omits live progress, and releases',
    (tester) async {
      var taps = 0;
      waitForOpen = true;
      await tester.pumpWidget(app(onTap: () => taps++));
      expect(find.byKey(_owner), findsNothing);
      final mouse = await hover(tester, title: true);
      expect(tester.widget<AnimatedScale>(find.byKey(_scale)).scale, 1.05);
      await tester.pump(const Duration(milliseconds: 199));
      expect(repository.rooms, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(repository.rooms, hasLength(1));
      expect(find.byKey(_preview), findsNothing);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      engines.single.opening!.complete();
      await tester.pump();
      expect(find.byKey(_preview), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 220));
      await tester.tapAt(tester.getCenter(find.byKey(_scale)));
      await tester.pump();
      expect(taps, 1);
      expect(repository.tokens.single.isCancelled, isTrue);
      expect(find.byKey(_preview), findsNothing);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(engines.single.disposals, 1);
      await mouse.moveTo(const Offset(700, 500));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('moving away before delay performs no read', (tester) async {
    await tester.pumpWidget(app());
    final mouse = await hover(tester);
    await tester.pump(const Duration(milliseconds: 100));
    await mouse.moveTo(const Offset(700, 500));
    await tester.pump();
    await loaded(tester);
    expect(repository.rooms, isEmpty);
    expect(engines, isEmpty);
    expect(find.byKey(_owner), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'setting disables pending and active previews without changing hover style',
    (tester) async {
      await tester.pumpWidget(app(enabled: false));
      await hover(tester);
      await loaded(tester);
      expect(repository.rooms, isEmpty);
      expect(find.byKey(_owner), findsNothing);
      expect(tester.widget<AnimatedScale>(find.byKey(_scale)).scale, 1.05);
      await tester.pumpWidget(app());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(app(enabled: false));
      await loaded(tester);
      expect(repository.rooms, isEmpty);
      await tester.pumpWidget(app());
      await loaded(tester);
      expect(find.byKey(_preview), findsOneWidget);
      await tester.pumpWidget(app(enabled: false));
      expect(find.byKey(_preview), findsNothing);
      expect(repository.tokens.single.isCancelled, isTrue);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(engines.single.disposals, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final kind in ['workspace', 'ticker', 'background']) {
    testWidgets('$kind hides and releases preview, restoring waits again', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await hover(tester);
      await loaded(tester);
      expect(find.byKey(_preview), findsOneWidget);
      if (kind == 'background') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
      } else {
        await tester.pumpWidget(
          app(active: kind != 'workspace', ticker: kind != 'ticker'),
        );
      }
      expect(find.byKey(_preview), findsNothing);
      expect(repository.tokens.first.isCancelled, isTrue);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(engines.first.disposals, 1);
      if (kind == 'background') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
      } else {
        await tester.pumpWidget(app());
      }
      await loaded(tester);
      expect(repository.rooms, hasLength(2));
      expect(find.byKey(_preview), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'ancestor scrolling cancels preview and restarts only when idle',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(app(scroll: scroll));
      await hover(tester);
      await loaded(tester);
      final scrolling = scroll.animateTo(
        8,
        duration: const Duration(milliseconds: 300),
        curve: Curves.linear,
      );
      await tester.pump();
      expect(repository.tokens.first.isCancelled, isTrue);
      expect(find.byKey(_preview), findsNothing);
      await tester.pump(const Duration(milliseconds: 150));
      expect(repository.rooms, hasLength(1));
      await tester.pump(const Duration(milliseconds: 160));
      await scrolling;
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await loaded(tester);
      expect(repository.rooms, hasLength(2));
      expect(find.byKey(_preview), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'room replacement cancels pending read and rejects late response',
    (tester) async {
      repository.pending = Completer();
      await tester.pumpWidget(app());
      await hover(tester);
      await tester.pump(const Duration(milliseconds: 220));
      final pending = repository.pending!;
      await tester.pumpWidget(app(room: '13'));
      expect(repository.tokens.first.isCancelled, isTrue);
      repository.pending = null;
      pending.complete(repository.info);
      await tester.pump();
      expect(engines, isEmpty);
      await loaded(tester);
      expect(repository.rooms.map((id) => id.value), ['12', '13']);
      expect(engines, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('failure retains cover and navigation', (tester) async {
    repository.failure = const AppFailure(AppFailureKind.permission, 'locked');
    var taps = 0;
    await tester.pumpWidget(app(onTap: () => taps++));
    await hover(tester);
    await loaded(tester);
    expect(find.byKey(_preview), findsNothing);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('直播标题'));
    expect(taps, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('touch tap opens room without creating preview', (tester) async {
    var taps = 0;
    await tester.pumpWidget(app(onTap: () => taps++));
    await tester.tap(find.text('直播标题'));
    await loaded(tester);
    expect(taps, 1);
    expect(repository.rooms, isEmpty);
    expect(engines, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
