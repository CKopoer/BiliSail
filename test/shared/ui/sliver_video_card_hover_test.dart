import 'dart:async';

import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/video/application/video_card_preview_playback.dart';
import 'package:bilisail/features/video/domain/video_card_interactions.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:bilisail/shared/ui/video_card_interaction_scope.dart';
import 'package:bilisail/shared/ui/video_grid.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';

import '../../support/video_card_fake_engine.dart';

void main() {
  for (final pendingOpen in [false, true]) {
    testWidgets(
      'sliver eviction releases ${pendingOpen ? 'pending' : 'playing'} preview once',
      (tester) async {
        _setViewport(tester);
        final interactions = _Interactions(
          opening: pendingOpen ? Completer<void>() : null,
        );
        final scroll = ScrollController();
        _cleanUp(tester, interactions, scroll);
        final grid = _grid();
        await tester.pumpWidget(_app(interactions, scroll, grid));
        final first = _firstCard();
        final firstState = tester.state<State<VideoCard>>(first);
        final mouse = await _hoverFirst(tester, first);
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump();
        expect(interactions.engines, hasLength(1));
        expect(interactions.reads, 1);
        final engine = interactions.engines.single;
        final token = interactions.tokens.single;
        expect(
          find.byKey(const ValueKey('fake-card-video-surface')),
          pendingOpen ? findsNothing : findsOneWidget,
        );

        // Jump far beyond both the viewport and the explicit 100px cache.
        // Keep the pointer stationary until layout evicts the old row.
        scroll.jumpTo(3200);
        await tester.pump();
        // InkWell retains a hovered row until its exit highlight has faded.
        // The stationary pointer exits during layout, then keep-alive ends.
        for (var frame = 0; frame < 2; frame++) {
          await tester.pump(const Duration(milliseconds: 60));
          await tester.pump();
        }
        expect(firstState.mounted, isFalse);
        expect(first, findsNothing);
        expect(token.isCancelled, isTrue);
        await mouse.moveTo(const Offset(700, 500));
        await _flushRelease(tester);
        expect(engine.stops, 1);
        expect(engine.disposals, 1);
        expect(interactions.engines, hasLength(1));

        if (pendingOpen) {
          interactions.opening!.complete();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(firstState.mounted, isFalse);
          expect(engine.disposals, 1);
          expect(interactions.engines, hasLength(1));
          expect(
            find.byKey(const ValueKey('fake-card-video-surface')),
            findsNothing,
          );
        }

        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
        await _flushRelease(tester);
        expect(engine.disposals, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'cached sliver releases hidden preview and restores stationary hover',
    (tester) async {
      _setViewport(tester);
      final interactions = _Interactions();
      final scroll = ScrollController();
      _cleanUp(tester, interactions, scroll);
      final grid = _grid();
      await tester.pumpWidget(_app(interactions, scroll, grid));
      final first = _firstCard();
      final firstState = tester.state<State<VideoCard>>(first);
      final mouse = await _hoverFirst(tester, first);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      final engine = interactions.engines.single;
      final token = interactions.tokens.single;
      expect(
        find.byKey(const ValueKey('fake-card-video-surface')),
        findsOneWidget,
      );

      await tester.pumpWidget(_app(interactions, scroll, grid, active: false));
      await _flushRelease(tester);
      expect(tester.state<State<VideoCard>>(first), same(firstState));
      expect(firstState.mounted, isTrue);
      expect(token.isCancelled, isTrue);
      expect(engine.disposals, 1);
      await tester.pump(const Duration(milliseconds: 500));
      expect(interactions.reads, 1);
      expect(
        find.byKey(const ValueKey('fake-card-video-surface')),
        findsNothing,
      );

      await tester.pumpWidget(_app(interactions, scroll, grid));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(tester.state<State<VideoCard>>(first), same(firstState));
      expect(interactions.reads, 2);
      expect(interactions.engines, hasLength(2));
      expect(
        find.byKey(const ValueKey('fake-card-video-surface')),
        findsOneWidget,
      );
      expect(engine.disposals, 1);

      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      await _flushRelease(tester);
      expect(interactions.engines.last.disposals, 1);
      expect(tester.takeException(), isNull);
    },
  );
}

void _setViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _cleanUp(
  WidgetTester tester,
  _Interactions interactions,
  ScrollController scroll,
) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    final opening = interactions.opening;
    if (opening != null && !opening.isCompleted) opening.complete();
    await _flushRelease(tester);
    unawaited(interactions.previews.close());
    scroll.dispose();
  });
}

Finder _firstCard() => find.byWidgetPredicate(
  (widget) =>
      widget is VideoCard && widget.video.id == const VideoId('BV0000000000'),
);

Future<TestGesture> _hoverFirst(WidgetTester tester, Finder first) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: const Offset(700, 500));
  await mouse.moveTo(tester.getCenter(first));
  await tester.pump();
  return mouse;
}

Future<void> _flushRelease(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}

Widget _grid() => SliverVideoGrid(
  items: [
    for (var index = 0; index < 100; index++)
      VideoSummary(
        id: VideoId('BV${index.toString().padLeft(10, '0')}'),
        title: '视频 $index',
        coverUrl: '',
        author: '作者',
        duration: const Duration(seconds: 20),
        previewCid: '${index + 1}',
      ),
  ],
  onOpen: (_) {},
);

Widget _app(
  _Interactions interactions,
  ScrollController scroll,
  Widget grid, {
  bool active = true,
}) => MaterialApp(
  theme: BiliTheme.light(),
  home: Scaffold(
    body: VideoCardInteractionScope(
      interactions: interactions,
      onNotice: (_, _) {},
      child: WorkspaceActivity(
        active: active,
        child: TickerMode(
          enabled: active,
          child: CustomScrollView(
            controller: scroll,
            scrollCacheExtent: const ScrollCacheExtent.pixels(100),
            slivers: [grid],
          ),
        ),
      ),
    ),
  ),
);

final class _Interactions implements VideoCardOperations {
  _Interactions({this.opening});

  final Completer<void>? opening;
  final engines = <CardFakeEngine>[];
  final tokens = <RequestCancellation>[];
  int reads = 0;
  late final previews = VideoCardPreviewPlayback(
    createEngine: () {
      final engine = CardFakeEngine()..opening = opening;
      engines.add(engine);
      return engine;
    },
  );

  @override
  Future<VideoCardPreviewSession?> preview(
    VideoId id,
    RequestCancellation cancellation, {
    String? cid,
  }) {
    reads++;
    tokens.add(cancellation);
    return previews.start(cardPreviewMedia(), cancellation);
  }

  @override
  Future<WatchLaterResult> addWatchLater(VideoId id) async =>
      WatchLaterResult.added;
  @override
  bool isAdded(VideoId id) => false;
  @override
  bool isUncertain(VideoId id) => false;
}
