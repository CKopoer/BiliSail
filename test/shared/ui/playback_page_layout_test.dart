import 'package:bilisail/shared/ui/playback_page_layout.dart';
import 'package:bilisail/shared/ui/scroll_collapsing_header.dart';
import 'package:bilisail/shared/ui/scroll_boundary_handoff.dart';
import 'package:bilisail/shared/ui/smooth_scroll_behavior.dart';
import 'package:bili_player/bili_player.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HeaderScrollController scroll;
  var taps = 0;

  setUp(() {
    scroll = HeaderScrollController();
    taps = 0;
  });
  tearDown(() => scroll.dispose());

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(390, 800),
    VideoDimensions? dimensions = const VideoDimensions(1080, 1920),
    bool listening = false,
    bool showInfo = true,
    Object contentKey = 'one',
    int items = 50,
    ScrollController? nested,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const SmoothScrollBehavior(),
        home: Scaffold(
          body: PlaybackPageLayout(
            wide: size.width >= 1000,
            showInfo: showInfo,
            listening: listening,
            dimensions: dimensions,
            collapsedHeight: listening ? size.height / 2 : size.width * 9 / 16,
            contentKey: contentKey,
            toggleInfo: () {},
            toggleTooltip: '信息',
            player: GestureDetector(
              onTap: () => taps++,
              child: const ColoredBox(
                key: ValueKey('player'),
                color: Colors.black,
              ),
            ),
            info: Builder(
              builder: (context) {
                scroll.configure(context, active: showInfo);
                return Column(
                  key: const ValueKey('info'),
                  children: [
                    const SizedBox(height: 48, child: Text('简介')),
                    Expanded(
                      child: ListView.builder(
                        controller: scroll,
                        itemExtent: 60,
                        itemCount: items,
                        itemBuilder: (_, index) => index == 0 && nested != null
                            ? ScrollBoundaryHandoff(
                                child: ListView.builder(
                                  key: const ValueKey('nested'),
                                  controller: nested,
                                  itemExtent: 30,
                                  itemCount: 10,
                                  itemBuilder: (_, item) => Text('分 P $item'),
                                ),
                              )
                            : Text('内容 $index'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double height(WidgetTester tester) =>
      tester.getSize(find.byKey(const ValueKey('player'))).height;

  for (final (dimensions, expandedHeight) in [
    (const VideoDimensions(1080, 1920), 520.0),
    (const VideoDimensions(1080, 1080), 390.0),
  ]) {
    testWidgets(
      '${dimensions.width}x${dimensions.height} reserves information space and collapses continuously',
      (tester) async {
        await show(tester, dimensions: dimensions);
        expect(height(tester), expandedHeight);
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('info'))).dy,
          expandedHeight,
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('info'))).height,
          800 - expandedHeight,
        );
        await tester.tapAt(Offset(100, expandedHeight / 2));
        await tester.pump();
        expect(taps, 1);

        final gesture = await tester.startGesture(const Offset(150, 680));
        await gesture.moveBy(const Offset(0, -70));
        await tester.pump();
        final first = height(tester);
        expect(first, lessThan(expandedHeight));
        expect(first, greaterThan(390 * 9 / 16));
        expect(scroll.offset, 0);
        await gesture.moveBy(const Offset(0, -60));
        await tester.pump();
        expect(first - height(tester), closeTo(60, .01));
        expect(scroll.offset, 0);
        await gesture.moveBy(const Offset(0, -450));
        await tester.pump();
        expect(height(tester), 390 * 9 / 16);
        expect(scroll.offset, greaterThan(0));
        await gesture.up();
        await tester.pumpAndSettle();
        scroll.jumpTo(0);
        await tester.pumpAndSettle();
        expect(height(tester), expandedHeight);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('short information still permits collapsing and expanding', (
    tester,
  ) async {
    await show(tester, items: 1);
    await tester.drag(find.text('内容 0'), const Offset(0, -360));
    await tester.pumpAndSettle();
    expect(height(tester), 390 * 9 / 16);
    await tester.drag(find.text('内容 0'), const Offset(0, 360));
    await tester.pumpAndSettle();
    expect(height(tester), 520);
  });

  testWidgets(
    'nested part list hands a downward drag back to portrait height',
    (tester) async {
      final nested = ScrollController();
      addTearDown(nested.dispose);
      await show(tester, nested: nested);
      tester
          .state<NestedScrollViewState>(find.byType(NestedScrollView))
          .outerController
          .jumpTo(520 - 390 * 9 / 16);
      nested.jumpTo(30);
      await tester.pumpAndSettle();
      expect(height(tester), 390 * 9 / 16);
      expect(scroll.offset, 0);
      await tester.drag(
        find.byKey(const ValueKey('nested')),
        const Offset(0, 430),
      );
      await tester.pumpAndSettle();
      expect(nested.offset, 0);
      expect(height(tester), 520);
    },
  );

  testWidgets('desktop wheel shares the collapse distance with the list', (
    tester,
  ) async {
    await show(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(100, 650));
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(100, 650),
        scrollDelta: Offset(0, 100),
      ),
    );
    await tester.pumpAndSettle();
    expect(height(tester), closeTo(420, 1));
    expect(scroll.offset, 0);
    await mouse.removePointer();
  });

  for (final dimensions in [
    null,
    const VideoDimensions(1920, 1080),
    const VideoDimensions(1081, 1080),
    const VideoDimensions(0, 1920),
  ]) {
    testWidgets('nonportrait dimensions $dimensions keep landscape height', (
      tester,
    ) async {
      await show(tester, dimensions: dimensions);
      expect(height(tester), 390 * 9 / 16);
      await tester.dragFrom(const Offset(100, 650), const Offset(0, -180));
      await tester.pumpAndSettle();
      expect(height(tester), 390 * 9 / 16);
      expect(scroll.offset, greaterThan(0));
    });
  }

  testWidgets('available height and aspect ratio cap portrait expansion', (
    tester,
  ) async {
    await show(tester, size: const Size(480, 660));
    expect(height(tester), 420);
    await show(tester, dimensions: const VideoDimensions(1000, 1100));
    expect(height(tester), closeTo(429, .01));
    await show(tester, size: const Size(700, 600));
    expect(height(tester), 700 * 9 / 16);
  });

  testWidgets('square expansion respects available space and player modes', (
    tester,
  ) async {
    const square = VideoDimensions(1080, 1080);
    await show(tester, size: const Size(480, 660), dimensions: square);
    expect(height(tester), 420);
    await show(tester, size: const Size(700, 600), dimensions: square);
    expect(height(tester), 700 * 9 / 16);
    await show(tester, dimensions: square, listening: true);
    expect(height(tester), 400);
    await show(tester, dimensions: square, showInfo: false);
    expect(height(tester), 800);
  });

  testWidgets('wide listening and hidden information keep their own heights', (
    tester,
  ) async {
    await show(tester, size: const Size(1200, 800));
    expect(
      tester.getSize(find.byKey(const ValueKey('player'))),
      const Size(820, 800),
    );
    await show(tester, listening: true);
    expect(height(tester), 400);
    await show(tester, showInfo: false);
    expect(height(tester), 800);
    await show(tester);
    expect(height(tester), 520);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new content restores expansion without replacing the player', (
    tester,
  ) async {
    await show(tester);
    final player = tester.element(find.byKey(const ValueKey('player')));
    await tester.drag(find.text('内容 1'), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(height(tester), 390 * 9 / 16);
    await show(tester, contentKey: 'two');
    expect(height(tester), 520);
    expect(tester.element(find.byKey(const ValueKey('player'))), same(player));
  });
}
