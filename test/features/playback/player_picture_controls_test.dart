import 'package:bilisail/features/playback/presentation/player_picture_controls.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pinch anchors details, pans, clamps and never rebuilds output', (
    tester,
  ) async {
    final controller = PlayerPictureController();
    addTearDown(controller.dispose);
    var builds = 0;
    await tester.pumpWidget(
      _app(
        controller,
        child: Builder(
          builder: (_) {
            builds++;
            return const ColoredBox(color: Colors.blue);
          },
        ),
      ),
    );
    final initialBuilds = builds;
    final a = await tester.startGesture(const Offset(150, 100), pointer: 1);
    final b = await tester.startGesture(const Offset(250, 100), pointer: 2);
    await a.moveTo(const Offset(100, 100));
    await b.moveTo(const Offset(300, 100));
    await tester.pump();
    expect(controller.value.scale, 2);
    expect(controller.value.offset, const Offset(-.5, -.5));
    // Translation is normalized to the viewport, retaining the pinch anchor.
    await a.moveBy(const Offset(20, 10));
    await b.moveBy(const Offset(20, 10));
    await tester.pump();
    expect(controller.value.scale, 2);
    expect(controller.value.offset.dx, closeTo(-.45, .001));
    expect(controller.value.offset.dy, closeTo(-.45, .001));
    expect(builds, initialBuilds);
    await a.up();
    final value = controller.value;
    await b.moveBy(const Offset(60, 0));
    expect(controller.value, value);
    await b.up();
    controller.reset();
    expect(controller.value, PlayerPictureController.identity);
    await tester.pumpWidget(const SizedBox());
  });

  for (final allowShrink in [false, true]) {
    testWidgets('shrink lower bound follows preference $allowShrink', (
      tester,
    ) async {
      final controller = PlayerPictureController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller, allowShrink: allowShrink));
      final a = await tester.startGesture(const Offset(100, 100), pointer: 1);
      final b = await tester.startGesture(const Offset(300, 100), pointer: 2);
      await a.moveTo(const Offset(190, 100));
      await b.moveTo(const Offset(210, 100));
      expect(controller.value.scale, allowShrink ? .75 : 1);
      await a.up();
      await b.up();
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final cancel in [
    'source',
    'hidden',
    'background',
    'modal',
    'pointer',
    'layout',
  ]) {
    testWidgets('$cancel cancels old picture contacts', (tester) async {
      final controller = PlayerPictureController();
      addTearDown(controller.dispose);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(_app(controller, navigator: navigator));
      final a = await tester.startGesture(const Offset(150, 100), pointer: 1);
      final b = await tester.startGesture(const Offset(250, 100), pointer: 2);
      await a.moveBy(const Offset(-20, 0));
      await tester.pump();
      final before = controller.value;
      switch (cancel) {
        case 'source':
          await tester.pumpWidget(
            _app(controller, generation: 2, navigator: navigator),
          );
        case 'hidden':
          await tester.pumpWidget(
            _app(controller, enabled: false, navigator: navigator),
          );
        case 'background':
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
        case 'modal':
          showDialog<void>(
            context: navigator.currentContext!,
            builder: (_) => const AlertDialog(content: Text('modal')),
          );
          await tester.pump();
        case 'pointer':
          await a.cancel();
        case 'layout':
          await tester.pumpWidget(
            _app(controller, width: 390, navigator: navigator),
          );
      }
      await b.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(controller.value, before);
      if (cancel != 'pointer') await a.up();
      await b.up();
      if (cancel == 'background') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('single touch and wheel retain existing meanings', (
    tester,
  ) async {
    final controller = PlayerPictureController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await tester.dragFrom(const Offset(100, 100), const Offset(100, 0));
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(100, 100),
        scrollDelta: Offset(0, -100),
      ),
    );
    expect(controller.value, PlayerPictureController.identity);
    await tester.pumpWidget(const SizedBox());
  });
}

Widget _app(
  PlayerPictureController controller, {
  int generation = 1,
  bool enabled = true,
  bool allowShrink = true,
  double width = 400,
  GlobalKey<NavigatorState>? navigator,
  Widget child = const ColoredBox(color: Colors.blue),
}) => MaterialApp(
  navigatorKey: navigator,
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: width,
      height: 200,
      child: PlayerPictureControls(
        controller: controller,
        enabled: enabled,
        sourceGeneration: generation,
        isCurrent: () => true,
        allowShrink: allowShrink,
        onTouchSequence: () {},
        onMultipleTouches: () {},
        child: PlayerPicture(controller: controller, child: child),
      ),
    ),
  ),
);
