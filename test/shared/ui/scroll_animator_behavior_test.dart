import 'package:bilisail/domain/wheel_scroll_animation.dart';
import 'package:bilisail/shared/ui/paged_scroll_viewport.dart';
import 'package:bilisail/shared/ui/retained_tab_view.dart';
import 'package:bilisail/shared/ui/scroll_collapsing_header.dart';
import 'package:bilisail/shared/ui/smooth_scroll_behavior.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_animator/scroll_animator.dart';

void main() {
  testWidgets('Chromium mode uses the scroll_animator curve', (tester) async {
    final controller = ScrollController(initialScrollOffset: 300);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        SmoothScrollScope(
          animation: WheelScrollAnimation.chromium,
          dampingRatio: 1.3,
          child: ListView(
            controller: controller,
            children: const [SizedBox(height: 4000)],
          ),
        ),
      ),
    );
    final animation = const ChromiumEaseInOut().createScrollAnimation(
      Offset.zero,
      const Offset(0, 120),
      .pointer,
    );
    await _wheel(tester, find.byType(ListView), 120);
    await tester.pump();
    for (var frame = 1; frame <= 30; frame++) {
      await tester.pump(const Duration(milliseconds: 8));
      final time = Duration(microseconds: (frame * 8000 / 1.3).round());
      final done = time >= animation.duration;
      expect(
        controller.offset,
        closeTo(300 + (done ? 120 : animation.getValue(time).dy), .000001),
      );
      expect(
        controller.position.activity?.velocity ?? 0,
        closeTo(done ? 0 : animation.getVelocity(time).dy / 1.3, .000001),
      );
    }
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(420, .000001));
    expect(controller.position.isScrollingNotifier.value, isFalse);
  });

  testWidgets('default motion uses the original spring and physical clock', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 300);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        ListView(
          controller: controller,
          children: const [SizedBox(height: 4000)],
        ),
      ),
    );
    final position = controller.position;
    final simulation = ScrollSpringSimulation(
      SpringDescription.withDampingRatio(mass: 1, stiffness: 1600, ratio: 1.3),
      0,
      120,
      0,
      tolerance: Tolerance(
        distance: .5 / position.devicePixelRatio,
        velocity: position.physics.toleranceFor(position).velocity,
      ),
    );
    await _wheel(tester, find.byType(ListView), 120);
    await tester.pump();
    for (var frame = 1; frame <= 30; frame++) {
      await tester.pump(const Duration(milliseconds: 8));
      final time = frame * .008;
      expect(controller.offset, closeTo(300 + simulation.x(time), .000001));
      expect(
        controller.position.activity?.velocity ?? 0,
        closeTo(simulation.isDone(time) ? 0 : simulation.dx(time), .000001),
      );
    }
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(420, .000001));
    expect(controller.position.isScrollingNotifier.value, isFalse);
  });

  for (final initial in WheelScrollAnimation.values) {
    final speed = initial == WheelScrollAnimation.multiplatform ? 2 : 1;
    testWidgets(
      'switching from $initial stops motion and retains the position',
      (tester) async {
        final mode = ValueNotifier(initial);
        final controller = ScrollController(initialScrollOffset: 500);
        addTearDown(mode.dispose);
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _app(
            ValueListenableBuilder(
              valueListenable: mode,
              builder: (_, value, child) => SmoothScrollScope(
                animation: value,
                dampingRatio: .5,
                child: child!,
              ),
              child: ListView(
                controller: controller,
                children: const [SizedBox(height: 4000)],
              ),
            ),
          ),
        );
        final position = controller.position;
        await _wheel(tester, find.byType(ListView), 400);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 48));
        expect(position.isScrollingNotifier.value, isTrue);
        mode.value = initial == WheelScrollAnimation.spring
            ? WheelScrollAnimation.chromium
            : WheelScrollAnimation.spring;
        await tester.pump();
        final saved = controller.offset;
        expect(controller.position, same(position));
        expect(position.isScrollingNotifier.value, isFalse);
        await tester.pump(const Duration(seconds: 1));
        expect(controller.offset, saved);
        await _wheel(tester, find.byType(ListView), 120);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(controller.offset, greaterThan(saved));
        await tester.pumpAndSettle();
        final nextSpeed = mode.value == WheelScrollAnimation.multiplatform
            ? 2
            : 1;
        expect(controller.offset, closeTo(saved + 120 * nextSpeed, .000001));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('$initial keeps nested header and retained tab positions', (
      tester,
    ) async {
      final selection = ValueNotifier(0);
      final controllers = <int, ScrollController>{};
      addTearDown(selection.dispose);
      await tester.pumpWidget(
        _app(
          SmoothScrollScope(
            animation: initial,
            dampingRatio: 1.3,
            child: ScrollHeaderLayout(
              enabled: true,
              header: const SizedBox(height: 80),
              child: ValueListenableBuilder(
                valueListenable: selection,
                builder: (_, value, _) => RetainedTabView<int>(
                  tabs: const [0, 1],
                  value: value,
                  onChanged: (tab) => selection.value = tab,
                  animateSelection: (_, _) => false,
                  pageBuilder: (_, tab, active) => PagedScrollViewport(
                    key: ValueKey(tab),
                    active: active,
                    canLoadMore: false,
                    contentVersion: tab,
                    onLoadMore: () async {},
                    builder: (controller) {
                      controllers[tab] = controller;
                      return ListView.builder(
                        key: ValueKey('list-$tab'),
                        controller: controller,
                        itemExtent: 60,
                        itemCount: 200,
                        itemBuilder: (_, index) => Text('$tab:$index'),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final first = controllers[0]!;
      final firstPosition = first.position;
      final outer = tester
          .state<NestedScrollViewState>(find.byType(NestedScrollView))
          .outerController;
      await _wheel(tester, find.byKey(const ValueKey('list-0')), 600);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(outer.offset, 80);
      expect(first.offset, greaterThan(0));
      expect(firstPosition.isScrollingNotifier.value, isTrue);
      selection.value = 1;
      await tester.pumpAndSettle();
      final saved = first.offset;
      final second = controllers[1]!;
      final secondPosition = second.position;
      expect(second.offset, 0);
      expect(firstPosition.isScrollingNotifier.value, isFalse);
      await _wheel(tester, find.byKey(const ValueKey('list-1')), 240);
      await tester.pumpAndSettle();
      expect(second.offset, closeTo(240 * speed, .000001));
      expect(first.offset, saved);
      selection.value = 0;
      await tester.pumpAndSettle();
      expect(first.position, same(firstPosition));
      expect(first.offset, saved);
      expect(outer.offset, 80);
      await _wheel(tester, find.byKey(const ValueKey('list-0')), -(saved + 80));
      await tester.pumpAndSettle();
      expect(first.offset, closeTo(0, .000001));
      expect(outer.offset, closeTo(0, .000001));
      expect(second.offset, closeTo(240 * speed, .000001));
      expect(second.position, same(secondPosition));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }
}

Widget _app(Widget child) => MaterialApp(
  theme: ThemeData(platform: TargetPlatform.windows),
  scrollBehavior: const SmoothScrollBehavior(),
  home: Scaffold(body: child),
);

Future<void> _wheel(WidgetTester tester, Finder target, double delta) =>
    tester.sendEventToBinding(
      PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: tester.getCenter(target),
        scrollDelta: Offset(0, delta),
      ),
    );
