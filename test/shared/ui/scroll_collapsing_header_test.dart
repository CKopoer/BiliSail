import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/shared/ui/paged_scroll_viewport.dart';
import 'package:bilisail/shared/ui/scroll_collapsing_header.dart';
import 'package:bilisail/shared/ui/smooth_scroll_behavior.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _header = ValueKey('header');
const _list = ValueKey('vertical-list');
const _tabs = ValueKey('tabs');

void main() {
  late ScrollController controller;
  var headerBuilds = 0;
  var bodyBuilds = 0;

  Future<void> mount(
    WidgetTester tester, {
    bool enabled = true,
    bool active = true,
    bool reduceMotion = false,
    int count = 100,
    Future<void> Function()? onRefresh,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        scrollBehavior: const SmoothScrollBehavior(),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(
            body: WorkspaceActivity(
              active: active,
              child: ScrollHeaderLayout(
                enabled: enabled,
                header: Builder(
                  builder: (_) {
                    headerBuilds++;
                    return const SizedBox(
                      key: _header,
                      height: 80,
                      child: TextField(),
                    );
                  },
                ),
                child: Column(
                  children: [
                    SizedBox(
                      key: _tabs,
                      height: 60,
                      child: ListView.builder(
                        key: const ValueKey('horizontal-list'),
                        primary: false,
                        scrollDirection: Axis.horizontal,
                        itemExtent: 100,
                        itemCount: 20,
                        itemBuilder: (_, index) => Text('tab $index'),
                      ),
                    ),
                    Expanded(
                      child: PagedScrollViewport(
                        active: active,
                        canLoadMore: false,
                        contentVersion: count,
                        onLoadMore: () async {},
                        onRefresh: onRefresh,
                        builder: (scrollController) {
                          bodyBuilds++;
                          controller = scrollController;
                          final list = ListView.builder(
                            key: _list,
                            controller: controller,
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemExtent: 60,
                            itemCount: count,
                            itemBuilder: (_, index) => Text('item $index'),
                          );
                          return onRefresh == null
                              ? list
                              : RefreshIndicator(
                                  onRefresh: onRefresh,
                                  child: list,
                                );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'header and first item move by the drag distance without snapping',
    (tester) async {
      await mount(tester);
      final element = tester.element(find.byKey(_list));
      final builds = (headerBuilds, bodyBuilds);
      final tabTop = tester.getTopLeft(find.byKey(_tabs)).dy;
      final itemTop = tester.getTopLeft(find.text('item 0')).dy;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_list)),
      );
      // Establish a drag, then measure additional displacement without touch slop.
      await gesture.moveBy(const Offset(0, -24));
      await tester.pump();
      final previousTabTop = tester.getTopLeft(find.byKey(_tabs)).dy;
      final previousItemTop = tester.getTopLeft(find.text('item 0')).dy;
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(_tabs)).dy,
        closeTo(previousTabTop - 20, .1),
      );
      expect(
        tester.getTopLeft(find.text('item 0')).dy,
        closeTo(previousItemTop - 20, .1),
      );
      expect(
        controller.offset,
        0,
        reason: 'The header consumes the first part of the drag',
      );
      expect(
        tester.getTopLeft(find.byKey(_tabs)).dy,
        inExclusiveRange(0, tabTop),
      );
      final layers = tester.layers.whereType<OpacityLayer>();
      expect(
        layers.any((layer) => layer.alpha! > 0 && layer.alpha! < 255),
        isTrue,
      );
      expect(
        (headerBuilds, bodyBuilds),
        builds,
        reason: 'Scrolling only lays out and paints existing content',
      );
      expect(itemTop, greaterThan(previousItemTop));
      await gesture.moveBy(const Offset(0, -200));
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(_tabs)).dy, 0);
      expect(controller.offset, greaterThan(0));
      expect(find.byType(TextField).hitTestable(), findsNothing);
      expect(tester.element(find.byKey(_list)), same(element));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reverse scroll reaches list top before bringing back the header',
    (tester) async {
      await mount(tester);
      controller.jumpTo(400);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_list)),
      );
      await gesture.moveBy(const Offset(0, 80));
      await tester.pump();
      expect(controller.offset, greaterThan(0));
      expect(tester.getTopLeft(find.byKey(_tabs)).dy, 0);
      await gesture.moveBy(Offset(0, controller.offset + 30));
      await tester.pump();
      expect(controller.offset, 0);
      expect(tester.getTopLeft(find.byKey(_tabs)).dy, closeTo(30, .1));
      await gesture.moveBy(const Offset(0, 50));
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(_tabs)).dy, 80);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(TextField).hitTestable(), findsOneWidget);
    },
  );

  testWidgets(
    'horizontal scrolling keeps vertical layout and to-top restores it',
    (tester) async {
      await mount(tester);
      await tester.drag(
        find.byKey(const ValueKey('horizontal-list')),
        const Offset(-220, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(_tabs)).dy, 80);
      controller.jumpTo(300);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(_tabs)).dy, 0);
      controller.jumpTo(0);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(_tabs)).dy, 80);
    },
  );

  for (final (enabled, active) in [(false, true), (true, false)]) {
    testWidgets('keeps fixed header enabled=$enabled active=$active', (
      tester,
    ) async {
      await mount(tester, enabled: enabled, active: active);
      await tester.drag(
        find.byKey(_list),
        const Offset(0, -180),
        warnIfMissed: active,
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(_tabs)).dy, 80);
    });
  }

  testWidgets('short lists can reveal the header again', (tester) async {
    await mount(tester, count: 1);
    await tester.drag(find.byKey(_list), const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(_list), const Offset(0, 180));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(_tabs)).dy, 80);
  });

  testWidgets(
    'pull-to-refresh still works after returning to the full header',
    (tester) async {
      var refreshes = 0;
      await mount(tester, onRefresh: () async => refreshes++);
      controller.jumpTo(300);
      await tester.pumpAndSettle();
      controller.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(_list), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(refreshes, 1);
      expect(tester.getTopLeft(find.byKey(_tabs)).dy, 80);
    },
  );

  testWidgets('changing width policy preserves the list position', (
    tester,
  ) async {
    await mount(tester, reduceMotion: true);
    controller.jumpTo(300);
    await tester.pumpAndSettle();
    final position = controller.position;
    await mount(tester, enabled: false, reduceMotion: true);
    expect(controller.position, same(position));
    expect(controller.offset, closeTo(300, .1));
    expect(tester.getTopLeft(find.byKey(_tabs)).dy, 80);
    expect(tester.takeException(), isNull);
  });

  for (final reduced in [false, true]) {
    testWidgets(
      'wheel coordinates both views and stops when hidden reduced=$reduced',
      (tester) async {
        await mount(tester, reduceMotion: reduced);
        Future<void> wheel(double delta) => tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(find.byKey(_list)),
            scrollDelta: Offset(0, delta),
          ),
        );
        await wheel(240);
        await tester.pump();
        if (!reduced) {
          await tester.pump(const Duration(milliseconds: 30));
          expect(
            tester.getTopLeft(find.byKey(_tabs)).dy,
            inExclusiveRange(0, 80),
          );
          expect(controller.position.isScrollingNotifier.value, isTrue);
        }
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.byKey(_tabs)).dy, 0);
        expect(controller.offset, closeTo(160, 1));
        await wheel(-60);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.byKey(_tabs)).dy, 0);
        await wheel(-180);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.byKey(_tabs)).dy, 80);
        await wheel(600);
        await tester.pump();
        await mount(tester, active: false, reduceMotion: reduced);
        final saved = controller.offset;
        await tester.pump(const Duration(seconds: 1));
        expect(controller.offset, saved);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }
}
