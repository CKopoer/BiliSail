import 'package:bilisail/domain/wheel_scroll_animation.dart';
import 'package:bilisail/shared/ui/smooth_scroll_behavior.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_animator/scroll_animator.dart';
import 'package:smooth_scroll_multiplatform/smooth_scroll_multiplatform.dart';

void main() {
  for (final curve in ChromiumScrollCurve.values) {
    for (final duration in [.5, 1.0, 2.0]) {
      for (final distance in [.5, 1.75]) {
        testWidgets(
          '$curve distance=$distance duration=$duration follows the dependency',
          (tester) async {
            final controller = ScrollController(initialScrollOffset: 300);
            addTearDown(controller.dispose);
            await tester.pumpWidget(
              _app(
                SmoothScrollScope(
                  animation: WheelScrollAnimation.chromium,
                  dampingRatio: 1.3,
                  chromiumCurve: curve,
                  distanceMultiplier: distance,
                  durationMultiplier: duration,
                  child: _list(controller),
                ),
              ),
            );
            final ScrollAnimationFactory factory =
                curve == ChromiumScrollCurve.easeInOut
                ? const ChromiumEaseInOut()
                : const ChromiumImpulse();
            final animation = factory.createScrollAnimation(
              Offset.zero,
              Offset(0, 120 * distance),
              .pointer,
            );
            await _wheel(tester, 120);
            await tester.pump();
            for (var frame = 1; frame <= 6; frame++) {
              await tester.pump(const Duration(milliseconds: 16));
              final time = Duration(
                microseconds: (frame * 16000 / duration).round(),
              );
              final done = time >= animation.duration;
              expect(
                controller.offset,
                closeTo(
                  300 + (done ? 120 * distance : animation.getValue(time).dy),
                  .000001,
                ),
              );
              expect(
                controller.position.activity?.velocity ?? 0,
                closeTo(
                  done ? 0 : animation.getVelocity(time).dy / duration,
                  .000001,
                ),
              );
            }
            await tester.pumpAndSettle();
            expect(controller.offset, closeTo(300 + 120 * distance, .000001));
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets(
    'multiplatform simulation matches DynMouseScroll on successive wheel inputs',
    (tester) async {
      late ScrollController original;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DynMouseScroll(
              builder: (_, controller, physics) {
                original = controller;
                return ListView(
                  controller: controller,
                  physics: physics,
                  children: const [SizedBox(height: 6000)],
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _wheel(tester, 120);
      await tester.pump();
      await tester.pump();
      var simulation = SmoothScrollSimulation(start: 0, end: 240);
      for (var frame = 1; frame <= 6; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(original.offset, closeTo(simulation.x(frame * .016), .000001));
      }
      simulation = SmoothScrollSimulation(start: original.offset, end: 480);
      await _wheel(tester, 120);
      await tester.pump();
      for (var frame = 1; frame <= 6; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(original.offset, closeTo(simulation.x(frame * .016), .000001));
      }
      await tester.pumpAndSettle();
      expect(original.offset, 480);
      await tester.pumpWidget(const SizedBox.shrink());
      original.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in WheelScrollAnimation.values) {
    for (final reduced in [false, true]) {
      testWidgets(
        '$mode scales wheel distance and honors reduced motion=$reduced',
        (tester) async {
          final controller = ScrollController();
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            _app(
              MediaQuery(
                data: MediaQueryData(disableAnimations: reduced),
                child: SmoothScrollScope(
                  animation: mode,
                  dampingRatio: 1.3,
                  distanceMultiplier: 1.5,
                  durationMultiplier: 2,
                  child: _list(controller),
                ),
              ),
            ),
          );
          final distance = mode == WheelScrollAnimation.multiplatform
              ? 360.0
              : 180.0;
          await _wheel(tester, 120);
          expect(controller.offset, reduced ? distance : 0);
          await tester.pumpAndSettle();
          expect(controller.offset, closeTo(distance, .000001));
          await _wheel(tester, 120, kind: PointerDeviceKind.trackpad);
          expect(controller.offset, closeTo(distance + 120, .000001));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final mode in [
    WheelScrollAnimation.chromium,
    WheelScrollAnimation.multiplatform,
  ]) {
    testWidgets(
      '$mode changing parameters stops old motion and preserves position',
      (tester) async {
        final settings = ValueNotifier((
          distance: 1.0,
          duration: 1.0,
          curve: ChromiumScrollCurve.easeInOut,
        ));
        final controller = ScrollController(initialScrollOffset: 500);
        addTearDown(settings.dispose);
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _app(
            ValueListenableBuilder(
              valueListenable: settings,
              child: _list(controller),
              builder: (_, value, child) => SmoothScrollScope(
                animation: mode,
                dampingRatio: .5,
                distanceMultiplier: value.distance,
                durationMultiplier: value.duration,
                chromiumCurve: value.curve,
                child: child!,
              ),
            ),
          ),
        );
        final position = controller.position;
        for (final value in [
          (distance: 2.0, duration: 1.0, curve: ChromiumScrollCurve.easeInOut),
          (distance: 2.0, duration: 2.0, curve: ChromiumScrollCurve.easeInOut),
          if (mode == WheelScrollAnimation.chromium)
            (distance: 2.0, duration: 2.0, curve: ChromiumScrollCurve.impulse),
        ]) {
          await _wheel(tester, 120);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 48));
          settings.value = value;
          await tester.pump();
          final saved = controller.offset;
          expect(controller.position, same(position));
          expect(position.isScrollingNotifier.value, isFalse);
          await tester.pump(const Duration(seconds: 1));
          expect(controller.offset, saved);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Widget _app(Widget child) => MaterialApp(
  theme: ThemeData(platform: TargetPlatform.windows),
  scrollBehavior: const SmoothScrollBehavior(),
  home: Scaffold(body: child),
);

Widget _list(ScrollController controller) =>
    ListView(controller: controller, children: const [SizedBox(height: 6000)]);

Future<void> _wheel(
  WidgetTester tester,
  double delta, {
  PointerDeviceKind kind = PointerDeviceKind.mouse,
}) => tester.sendEventToBinding(
  PointerScrollEvent(
    kind: kind,
    position: tester.getCenter(find.byType(ListView)),
    scrollDelta: Offset(0, delta),
  ),
);
