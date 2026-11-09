import 'package:bilisail/core/presentation/history_back_region.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/input_test_app.dart';

void main() {
  testWidgets('iOS edge swipe shows progress and commits once on release', (
    tester,
  ) async {
    var backs = 0;
    await tester.pumpWidget(_app(onBack: () => backs++));
    final drag = await tester.startGesture(const Offset(5, 300));
    await drag.moveBy(const Offset(200, 0));
    await tester.pump();
    expect(_opacity(tester), closeTo(.5, .01));
    expect(backs, 0);
    await drag.moveBy(const Offset(250, 0));
    await tester.pump();
    expect(_opacity(tester), 1);
    expect(backs, 0);
    await drag.up();
    await tester.pumpAndSettle();
    expect(backs, 1);
    expect(_opacity(tester), 0);
  });

  for (final offsets in [
    [const Offset(70, 0)],
    [const Offset(450, 0), const Offset(-400, 0)],
    [const Offset(-100, 0)],
    [const Offset(0, 450)],
  ]) {
    testWidgets('short, reversed or vertical edge swipe cancels: $offsets', (
      tester,
    ) async {
      var backs = 0;
      await tester.pumpWidget(_app(onBack: () => backs++));
      final drag = await tester.startGesture(const Offset(5, 300));
      for (final offset in offsets) {
        await drag.moveBy(offset);
        await tester.pump(const Duration(milliseconds: 200));
      }
      await drag.up();
      await tester.pumpAndSettle();
      expect(backs, 0);
      expect(_opacity(tester), 0);
    });
  }

  testWidgets('fast forward edge flick commits below the distance threshold', (
    tester,
  ) async {
    var backs = 0;
    await tester.pumpWidget(_app(onBack: () => backs++));
    await tester.flingFrom(const Offset(5, 300), const Offset(150, 0), 1500);
    await tester.pumpAndSettle();
    expect(backs, 1);
  });

  testWidgets('pointer cancellation does not consume Back', (tester) async {
    var backs = 0;
    await tester.pumpWidget(_app(onBack: () => backs++));
    final drag = await tester.startGesture(const Offset(5, 300));
    await drag.moveBy(const Offset(450, 0));
    await drag.cancel();
    await tester.pumpAndSettle();
    expect(backs, 0);
    expect(_opacity(tester), 0);
  });

  for (final change in [
    'identity',
    'disabled',
    'hidden',
    'resize',
    'background',
  ]) {
    testWidgets('$change invalidates an ongoing iOS edge swipe', (
      tester,
    ) async {
      var backs = 0;
      void onBack() => backs++;
      await tester.pumpWidget(_app(onBack: onBack));
      final drag = await tester.startGesture(const Offset(5, 300));
      await drag.moveBy(const Offset(450, 0));
      await tester.pump();
      expect(_opacity(tester), 1);
      switch (change) {
        case 'identity':
          await tester.pumpWidget(_app(onBack: onBack, identity: 'another'));
        case 'disabled':
          await tester.pumpWidget(_app(onBack: onBack, enabled: false));
        case 'hidden':
          await tester.pumpWidget(_app(onBack: onBack, active: false));
        case 'resize':
          tester.view.physicalSize = const Size(900, 600);
          addTearDown(tester.view.resetPhysicalSize);
          await tester.pump();
        case 'background':
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
      }
      await drag.up();
      await tester.pumpAndSettle();
      expect(backs, 0);
      expect(_opacity(tester), 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('inner paging keeps touch drags away from the edge', (
    tester,
  ) async {
    var backs = 0;
    final controller = PageController(initialPage: 1);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        onBack: () => backs++,
        child: PageView(
          controller: controller,
          children: const [Text('first'), Text('second')],
        ),
      ),
    );
    await tester.dragFrom(const Offset(200, 300), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(controller.page, 0);
    expect(backs, 0);
    // The edge remains available even when a child handles horizontal drags.
    await tester.dragFrom(const Offset(5, 300), const Offset(450, 0));
    await tester.pumpAndSettle();
    expect(backs, 1);
  });

  testWidgets('sliders and vertical lists keep their touch behavior', (
    tester,
  ) async {
    var backs = 0;
    var value = .5;
    await tester.pumpWidget(
      _app(
        onBack: () => backs++,
        child: StatefulBuilder(
          builder: (_, setState) => Center(
            child: Slider(
              value: value,
              onChanged: (next) => setState(() => value = next),
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.byType(Slider), const Offset(150, 0));
    expect(value, greaterThan(.5));
    expect(backs, 0);
    final scroll = ScrollController(initialScrollOffset: 300);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _app(
        onBack: () => backs++,
        child: ListView(
          controller: scroll,
          children: const [SizedBox(height: 2000)],
        ),
      ),
    );
    await tester.dragFrom(const Offset(200, 300), const Offset(0, 150));
    await tester.pumpAndSettle();
    expect(scroll.offset, lessThan(300));
    expect(backs, 0);
  });

  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.stylus]) {
    testWidgets('iOS edge ignores $kind drags', (tester) async {
      var backs = 0;
      await tester.pumpWidget(_app(onBack: () => backs++));
      final drag = await tester.startGesture(const Offset(5, 300), kind: kind);
      await drag.moveBy(const Offset(450, 0));
      await drag.up();
      await tester.pumpAndSettle();
      expect(backs, 0);
    });
  }

  testWidgets('iOS leading edge includes safe padding and follows RTL', (
    tester,
  ) async {
    var backs = 0;
    await tester.pumpWidget(
      _app(onBack: () => backs++, padding: const EdgeInsets.only(left: 44)),
    );
    await tester.dragFrom(const Offset(35, 300), const Offset(450, 0));
    await tester.pumpAndSettle();
    expect(backs, 1);
    await tester.pumpWidget(_app(onBack: () => backs++, rtl: true));
    await tester.dragFrom(const Offset(5, 300), const Offset(450, 0));
    await tester.pumpAndSettle();
    expect(backs, 1);
    await tester.dragFrom(const Offset(795, 300), const Offset(-450, 0));
    await tester.pumpAndSettle();
    expect(backs, 2);
  });
}

double _opacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find.ancestor(
        of: find.byKey(const ValueKey('ios-back-indicator')),
        matching: find.byType(Opacity),
      ),
    )
    .opacity;

Widget _app({
  required VoidCallback onBack,
  Widget child = const SizedBox.expand(),
  Object identity = 'page',
  bool enabled = true,
  bool active = true,
  bool rtl = false,
  EdgeInsets padding = EdgeInsets.zero,
}) => InputTestApp(
  theme: ThemeData(platform: TargetPlatform.iOS),
  home: Scaffold(
    body: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(padding: padding),
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: WorkspaceActivity(
            active: active,
            child: HistoryBackRegion(
              enabled: enabled,
              identity: identity,
              onBack: onBack,
              child: child,
            ),
          ),
        ),
      ),
    ),
  ),
);
