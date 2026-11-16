import 'package:bilisail/shared/ui/scroll_aware_hover_region.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('touch lists only observe scroll activity for an actual hover', (
    tester,
  ) async {
    final controller = _CountingScrollController();
    addTearDown(controller.dispose);
    final events = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: controller,
            child: Column(
              children: [
                for (var i = 0; i < 100; i++)
                  ScrollAwareHoverRegion(
                    onHover: events.add,
                    child: const SizedBox(width: 320, height: 40),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(controller.observed.isScrollingNotifier.hoverListeners, 0);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    expect(controller.observed.isScrollingNotifier.hoverListeners, 0);
    expect(events, isEmpty);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(100, 100));
    await tester.pump();
    expect(controller.observed.isScrollingNotifier.hoverListeners, 1);
    expect(events, [true]);
    await mouse.moveTo(const Offset(700, 500));
    await tester.pump();
    expect(controller.observed.isScrollingNotifier.hoverListeners, 0);
    expect(events, [true, false]);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'hidden hover releases listeners and restores a stationary pointer',
    (tester) async {
      final controller = _CountingScrollController();
      addTearDown(controller.dispose);
      final events = <bool>[];
      var active = true;
      late StateSetter update;
      final content = SingleChildScrollView(
        controller: controller,
        child: ScrollAwareHoverRegion(
          onHover: events.add,
          child: const SizedBox(width: 320, height: 1400),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return WorkspaceActivity(active: active, child: content);
            },
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(100, 100));
      await tester.pump();
      expect(events, [true]);
      expect(controller.observed.isScrollingNotifier.hoverListeners, 1);
      update(() => active = false);
      await tester.pump();
      expect(controller.observed.isScrollingNotifier.hoverListeners, 0);
      controller.jumpTo(10);
      await tester.pump();
      expect(events, [true]);
      update(() => active = true);
      await tester.pumpAndSettle();
      expect(controller.observed.isScrollingNotifier.hoverListeners, 1);
      expect(events, [true]);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      expect(controller.observed.isScrollingNotifier.hoverListeners, 0);
    },
  );

  for (final exitDuringScroll in [false, true]) {
    testWidgets('nested scrolling restores only the current pointer '
        '(exit=$exitDuringScroll)', (tester) async {
      final outer = ScrollController();
      final inner = ScrollController();
      final events = <bool>[];
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        outer.dispose();
        inner.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: outer,
              child: SizedBox(
                height: 1400,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 320,
                    height: 300,
                    child: SingleChildScrollView(
                      controller: inner,
                      child: ScrollAwareHoverRegion(
                        onHover: events.add,
                        child: const SizedBox(width: 320, height: 900),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(100, 100));
      addTearDown(mouse.removePointer);
      await tester.pump();
      expect(events, [true]);
      final movingOuter = outer.animateTo(
        20,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );
      final movingInner = inner.animateTo(
        20,
        duration: const Duration(milliseconds: 500),
        curve: Curves.linear,
      );
      await tester.pump();
      expect(events, [true, false]);
      await mouse.moveTo(const Offset(600, 400));
      if (!exitDuringScroll) await mouse.moveTo(const Offset(100, 100));
      await tester.pump(const Duration(milliseconds: 220));
      await movingOuter;
      expect(outer.position.isScrollingNotifier.value, isFalse);
      expect(inner.position.isScrollingNotifier.value, isTrue);
      expect(events, [true, false]);
      await tester.pump(const Duration(milliseconds: 300));
      await movingInner;
      await tester.pump();
      expect(events, exitDuringScroll ? [true, false] : [true, false, true]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('removing a moving region releases scroll listeners', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var notifications = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: controller,
            child: ScrollAwareHoverRegion(
              onHover: (_) => notifications++,
              child: const SizedBox(width: 320, height: 1400),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(100, 100));
    await tester.pump();
    final moving = controller.animateTo(
      200,
      duration: const Duration(seconds: 1),
      curve: Curves.linear,
    );
    await tester.pump();
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
    await moving;
    final before = notifications;
    await tester.pump(const Duration(seconds: 2));
    expect(notifications, before);
    expect(tester.takeException(), isNull);
  });
}

final class _CountingScrollController extends ScrollController {
  late _CountingScrollPosition observed;
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => observed = _CountingScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

final class _CountingScrollPosition extends ScrollPositionWithSingleContext {
  _CountingScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
  });
  final _hoverScrollingNotifier = _HoverCountingNotifier();
  @override
  _HoverCountingNotifier get isScrollingNotifier => _hoverScrollingNotifier;
}

final class _HoverCountingNotifier extends ValueNotifier<bool> {
  _HoverCountingNotifier() : super(false);
  int hoverListeners = 0;
  @override
  void addListener(VoidCallback listener) {
    if (StackTrace.current.toString().contains(
      '_ScrollAwareHoverRegionState',
    )) {
      hoverListeners++;
    }
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (StackTrace.current.toString().contains(
      '_ScrollAwareHoverRegionState',
    )) {
      hoverListeners--;
    }
    super.removeListener(listener);
  }
}
