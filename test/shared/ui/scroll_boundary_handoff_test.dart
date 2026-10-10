import 'package:bilisail/shared/ui/scroll_boundary_handoff.dart';
import 'package:bilisail/shared/ui/smooth_scroll_behavior.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('wheel keeps inner scrolling and falls through at its edge', (
    tester,
  ) async {
    final outer = ScrollController();
    final inner = ScrollController();
    addTearDown(outer.dispose);
    addTearDown(inner.dispose);
    await tester.pumpWidget(_app(outer, inner, TargetPlatform.windows));
    await tester.pumpAndSettle();
    outer.jumpTo(120);
    inner.jumpTo(100);
    await tester.pump();
    final viewport = find.byKey(const ValueKey('inner'));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(viewport),
        scrollDelta: const Offset(0, -50),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();
    expect(inner.offset, closeTo(50, .01));
    expect(outer.offset, 120);
    inner.jumpTo(0);
    await tester.pump();
    expect(
      outer.offset,
      120,
      reason: 'a programmatic selection jump must stay local',
    );
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(viewport),
        scrollDelta: const Offset(0, -50),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();
    expect(outer.offset, closeTo(70, .01));
    expect(inner.offset, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new pointer cancels outer inertia and disposal releases it', (
    tester,
  ) async {
    final outer = ScrollController();
    final inner = ScrollController();
    addTearDown(outer.dispose);
    addTearDown(inner.dispose);
    await tester.pumpWidget(_app(outer, inner, TargetPlatform.android));
    await tester.pumpAndSettle();
    outer.jumpTo(150);
    await tester.pump();
    final viewport = find.byKey(const ValueKey('inner'));
    await tester.fling(viewport, const Offset(0, 70), 900);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(outer.position.isScrollingNotifier.value, true);
    final pointer = await tester.startGesture(tester.getCenter(viewport));
    final stopped = outer.offset;
    await tester.pump(const Duration(milliseconds: 100));
    expect(outer.offset, stopped);
    expect(outer.position.isScrollingNotifier.value, false);
    await pointer.cancel();
    await tester.pumpAndSettle();
    outer.jumpTo(150);
    await tester.pump();
    await tester.fling(viewport, const Offset(0, 70), 900);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Widget _app(
  ScrollController outer,
  ScrollController inner,
  TargetPlatform platform,
) => MaterialApp(
  theme: ThemeData(platform: platform),
  scrollBehavior: const SmoothScrollBehavior(),
  home: Scaffold(
    body: SingleChildScrollView(
      controller: outer,
      child: Column(
        children: [
          const SizedBox(height: 180),
          SizedBox(
            height: 160,
            child: ScrollBoundaryHandoff(
              child: ListView.builder(
                key: const ValueKey('inner'),
                controller: inner,
                primary: false,
                itemExtent: 40,
                itemCount: 50,
                itemBuilder: (_, index) => Text('Item $index'),
              ),
            ),
          ),
          const SizedBox(height: 1000),
        ],
      ),
    ),
  ),
);
