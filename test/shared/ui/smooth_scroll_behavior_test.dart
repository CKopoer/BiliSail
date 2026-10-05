import 'package:bili_lite/core/presentation/workspace_activity.dart';
import 'package:bili_lite/shared/ui/paged_scroll_viewport.dart';
import 'package:bili_lite/shared/ui/smooth_scroll_behavior.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('wheel moves through intermediate positions without a jump', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(_list(controller)));
    await _wheel(tester, find.byType(ListView), 120);
    expect(controller.offset, 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(controller.offset, greaterThan(0));
    expect(controller.offset, lessThan(120));
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(120, .01));
  });

  testWidgets(
    'repeated wheel inputs accumulate and reversal starts at pixels',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(_list(controller)));
      for (var i = 0; i < 3; i++) {
        await _wheel(tester, find.byType(ListView), 120);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 25));
      }
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(360, .01));
      await _wheel(tester, find.byType(ListView), 240);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 45));
      final beforeReverse = controller.offset;
      await _wheel(tester, find.byType(ListView), -120);
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(beforeReverse - 120, .01));
    },
  );

  testWidgets('inner lists claim the wheel and pass it outward at their edge', (
    tester,
  ) async {
    final outer = ScrollController();
    final inner = ScrollController();
    addTearDown(outer.dispose);
    addTearDown(inner.dispose);
    const innerKey = Key('inner');
    await tester.pumpWidget(
      _app(
        ListView(
          controller: outer,
          children: [
            SizedBox(height: 200, child: _list(inner, key: innerKey)),
            const SizedBox(height: 2000),
          ],
        ),
      ),
    );
    await _wheel(tester, find.byKey(innerKey), 120);
    await tester.pumpAndSettle();
    expect(inner.offset, closeTo(120, .01));
    expect(outer.offset, 0);
    inner.jumpTo(inner.position.maxScrollExtent);
    await tester.pump();
    await _wheel(tester, find.byKey(innerKey), 120);
    await tester.pumpAndSettle();
    expect(inner.offset, inner.position.maxScrollExtent);
    expect(outer.offset, closeTo(120, .01));
  });

  testWidgets('descendant pointer handlers retain ownership', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var handled = 0;
    const control = Key('custom-control');
    await tester.pumpWidget(
      _app(
        ListView(
          controller: controller,
          children: [
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerSignal: (event) => GestureBinding
                  .instance
                  .pointerSignalResolver
                  .register(event, (_) => handled++),
              child: const SizedBox(key: control, height: 200),
            ),
            const SizedBox(height: 2000),
          ],
        ),
      ),
    );
    await _wheel(tester, find.byKey(control), 120);
    await tester.pumpAndSettle();
    expect(handled, 1);
    expect(controller.offset, 0);
  });

  testWidgets('trackpad signals and reduced motion keep immediate scrolling', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(_list(controller)));
    await _wheel(
      tester,
      find.byType(ListView),
      120,
      kind: PointerDeviceKind.trackpad,
    );
    expect(controller.offset, 120);
    await tester.pumpWidget(_app(_list(controller), disableAnimations: true));
    await _wheel(tester, find.byType(ListView), 120);
    expect(controller.offset, 240);
    await tester.pumpAndSettle();
    expect(controller.offset, 240);
  });

  testWidgets('dialogs and implicit controllers inherit the global behavior', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const Dialog(
                child: SizedBox(
                  height: 200,
                  child: SingleChildScrollView(child: SizedBox(height: 2000)),
                ),
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    await _wheel(tester, find.byType(SingleChildScrollView), 120);
    expect(position.pixels, 0);
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(120, .01));
  });

  testWidgets('non-scrollable physics and mobile wheel handling stay native', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        ListView(
          controller: controller,
          physics: const NeverScrollableScrollPhysics(),
          children: const [SizedBox(height: 2400)],
        ),
      ),
    );
    await _wheel(tester, find.byType(ListView), 120);
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        scrollBehavior: const SmoothScrollBehavior(),
        home: Scaffold(body: _list(controller)),
      ),
    );
    await tester.pumpAndSettle();
    await _wheel(tester, find.byType(ListView), 120);
    expect(controller.offset, 120);
  });

  testWidgets('touch dragging and scrollbar dragging still work', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(_list(controller)));
    await tester.drag(find.byType(ListView), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(100));
    final previous = controller.offset;
    final rect = tester.getRect(find.byType(ListView));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.down(Offset(rect.right - 3, rect.top + 40));
    await mouse.moveBy(const Offset(0, 100));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(previous));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Shift routes vertical wheel to horizontal lists', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        ListView(
          controller: controller,
          scrollDirection: Axis.horizontal,
          children: const [SizedBox(width: 2400)],
        ),
      ),
    );
    await _wheel(tester, find.byType(ListView), 120);
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await _wheel(tester, find.byType(ListView), 120);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(120, .01));
  });

  testWidgets('reversed lists and extent boundaries retain their semantics', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 300);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        ListView(
          controller: controller,
          reverse: true,
          children: const [SizedBox(height: 2400)],
        ),
      ),
    );
    await _wheel(tester, find.byType(ListView), 120);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(180, .01));
    await _wheel(tester, find.byType(ListView), 1000);
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
  });

  testWidgets('programmatic navigation cancels pending wheel targets', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(_list(controller)));
    await _wheel(tester, find.byType(ListView), 400);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    controller.jumpTo(800);
    await _wheel(tester, find.byType(ListView), 120);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(920, .01));
    await _wheel(tester, find.byType(ListView), 120);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden workspaces stop a transition and do not resume it', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var active = true;
    late StateSetter update;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return WorkspaceActivity(active: active, child: _list(controller));
          },
        ),
      ),
    );
    await _wheel(tester, find.byType(ListView), 400);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    update(() => active = false);
    await tester.pump();
    final stopped = controller.offset;
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.offset, stopped);
    update(() => active = true);
    await tester.pump();
    await _wheel(tester, find.byType(ListView), 120);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(stopped + 120, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('animated scrolling continues to trigger bounded pagination', (
    tester,
  ) async {
    var requests = 0;
    await tester.pumpWidget(
      _app(
        PagedScrollViewport(
          active: true,
          canLoadMore: true,
          contentVersion: 1,
          onLoadMore: () async => requests++,
          builder: (controller) => ListView(
            controller: controller,
            children: const [SizedBox(height: 2400)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests, 0);
    await _wheel(tester, find.byType(ListView), 1500);
    await tester.pumpAndSettle();
    expect(requests, greaterThan(0));
    final settledRequests = requests;
    await tester.pump(const Duration(seconds: 1));
    expect(requests, settledRequests);
    expect(tester.takeException(), isNull);
  });
}

Widget _app(Widget child, {bool disableAnimations = false}) => MaterialApp(
  theme: ThemeData(platform: TargetPlatform.windows),
  scrollBehavior: const SmoothScrollBehavior(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
    child: child ?? const SizedBox(),
  ),
  home: Scaffold(body: child),
);

Widget _list(ScrollController controller, {Key? key}) => ListView(
  key: key,
  controller: controller,
  children: const [SizedBox(height: 2400)],
);

Future<void> _wheel(
  WidgetTester tester,
  Finder target,
  double delta, {
  PointerDeviceKind kind = PointerDeviceKind.mouse,
}) => tester.sendEventToBinding(
  PointerScrollEvent(
    kind: kind,
    position: tester.getCenter(target),
    scrollDelta: Offset(0, delta),
  ),
);
