import 'dart:ui' show ViewFocusDirection, ViewFocusEvent, ViewFocusState;

import 'package:bilisail/core/presentation/history_back_region.dart';
import 'package:bilisail/core/presentation/window_input_focus.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/input_test_app.dart';

const _origin = Offset(400, 300);
final _indicator = find.byKey(const ValueKey('trackpad-back-indicator'));

void main() {
  testWidgets('arrow follows distance and returns only once on release', (
    tester,
  ) async {
    var backs = 0;
    await tester.pumpWidget(_app(onBack: () => backs++));
    final drag = await _start(tester);
    await drag.moveBy(const Offset(60, 0));
    await tester.pump();
    final halfway = tester.getCenter(_indicator).dx;
    expect(_opacity(tester), closeTo(.5, .01));
    expect(backs, 0);
    await drag.moveBy(const Offset(80, 0));
    await tester.pump();
    expect(tester.getCenter(_indicator).dx, greaterThan(halfway));
    expect(_opacity(tester), 1);
    expect(backs, 0);
    await drag.panZoomEnd();
    expect(backs, 1);
    await tester.pumpAndSettle();
    expect(_opacity(tester), 0);
    expect(backs, 1);
  });

  for (final offsets in [
    [const Offset(70, 0)],
    [const Offset(150, 0), const Offset(-100, 0)],
    [const Offset(-40, 0), const Offset(240, 0)],
    [const Offset(10, 50), const Offset(180, 0)],
    [const Offset(30, 30), const Offset(180, 0)],
  ]) {
    testWidgets('short, reversed or non-horizontal gesture cancels: $offsets', (
      tester,
    ) async {
      var backs = 0;
      await tester.pumpWidget(_app(onBack: () => backs++));
      final drag = await _start(tester);
      for (final offset in offsets) {
        await drag.moveBy(offset);
        await tester.pump(const Duration(milliseconds: 1));
      }
      await drag.panZoomEnd();
      await tester.pumpAndSettle();
      expect(backs, 0);
      expect(_opacity(tester), 0);
    });
  }

  for (final afterDrag in [false, true]) {
    testWidgets('pinch cancels history navigation, after drag=$afterDrag', (
      tester,
    ) async {
      var backs = 0;
      await tester.pumpWidget(_app(onBack: () => backs++));
      final drag = await _start(tester);
      if (afterDrag) await drag.moveBy(const Offset(140, 0));
      await drag.panZoomUpdate(_origin, pan: const Offset(160, 0), scale: 1.2);
      await drag.panZoomEnd();
      await tester.pumpAndSettle();
      expect(backs, 0);
      expect(_opacity(tester), 0);
    });
  }

  for (final atBoundary in [false, true]) {
    testWidgets('horizontal list owns its gesture, at boundary=$atBoundary', (
      tester,
    ) async {
      var backs = 0;
      final scroll = ScrollController(
        initialScrollOffset: atBoundary ? 0 : 300,
      );
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        _app(
          onBack: () => backs++,
          child: ListView(
            controller: scroll,
            scrollDirection: Axis.horizontal,
            children: const [SizedBox(width: 2000)],
          ),
        ),
      );
      final drag = await _start(tester);
      await drag.moveBy(const Offset(50, 0));
      await drag.moveBy(const Offset(150, 0));
      await tester.pump();
      expect(_opacity(tester), 0);
      if (!atBoundary) expect(scroll.offset, lessThan(300));
      await drag.panZoomEnd();
      await tester.pumpAndSettle();
      expect(backs, 0);
    });
  }

  testWidgets('slider and vertical list keep their drag behavior', (
    tester,
  ) async {
    var backs = 0;
    var value = .5;
    await tester.pumpWidget(
      _app(
        onBack: () => backs++,
        child: StatefulBuilder(
          builder: (context, setState) => Center(
            child: TrackpadBackBlocker(
              child: Slider(
                value: value,
                onChanged: (next) => setState(() => value = next),
              ),
            ),
          ),
        ),
      ),
    );
    final sliderDrag = await _start(tester);
    await sliderDrag.moveBy(const Offset(60, 0));
    await sliderDrag.moveBy(const Offset(130, 0));
    await sliderDrag.panZoomEnd();
    await tester.pumpAndSettle();
    expect(value, .5);
    expect(backs, 0);
    final mouseDrag = await tester.startGesture(
      tester.getCenter(find.byType(Slider)),
      kind: PointerDeviceKind.mouse,
    );
    await mouseDrag.moveBy(const Offset(160, 0));
    await mouseDrag.up();
    await tester.pumpAndSettle();
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
    final listDrag = await _start(tester);
    await listDrag.moveBy(const Offset(5, 50));
    await listDrag.moveBy(const Offset(5, 150));
    await listDrag.panZoomEnd();
    await tester.pumpAndSettle();
    expect(scroll.offset, lessThan(300));
    expect(backs, 0);
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets('trackpad back is disabled on $platform', (tester) async {
      var backs = 0;
      await tester.pumpWidget(_app(onBack: () => backs++, platform: platform));
      final drag = await _start(tester);
      await drag.moveBy(const Offset(200, 0));
      await drag.panZoomEnd();
      await tester.pumpAndSettle();
      expect(backs, 0);
      expect(_indicator, findsNothing);
    });
  }

  testWidgets('mouse wheel, mouse drag and touch never navigate', (
    tester,
  ) async {
    var backs = 0;
    await tester.pumpWidget(_app(onBack: () => backs++));
    for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
      final drag = await tester.startGesture(_origin, kind: kind);
      await drag.moveBy(const Offset(200, 0));
      await drag.up();
    }
    await tester.sendEventToBinding(
      const PointerScrollEvent(position: _origin, scrollDelta: Offset(-240, 0)),
    );
    await tester.pumpAndSettle();
    expect(backs, 0);
  });

  for (final change in ['identity', 'disabled', 'hidden', 'resize', 'blur']) {
    testWidgets('$change invalidates an ongoing swipe', (tester) async {
      var backs = 0;
      void onBack() => backs++;
      await tester.pumpWidget(_app(onBack: onBack));
      final drag = await _start(tester);
      await drag.moveBy(const Offset(150, 0));
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
        case 'blur':
          tester.binding.handleViewFocusChanged(
            ViewFocusEvent(
              viewId: tester.view.viewId,
              state: ViewFocusState.unfocused,
              direction: ViewFocusDirection.undefined,
            ),
          );
      }
      await drag.panZoomEnd();
      await tester.pumpAndSettle();
      expect(backs, 0);
      expect(_opacity(tester), 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('modal opened during drag cancels the pending back', (
    tester,
  ) async {
    var backs = 0;
    late BuildContext pageContext;
    await tester.pumpWidget(
      _app(
        onBack: () => backs++,
        child: Builder(
          builder: (context) {
            pageContext = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    final drag = await _start(tester);
    await drag.moveBy(const Offset(150, 0));
    showDialog<void>(
      context: pageContext,
      builder: (_) => const AlertDialog(content: Text('dialog')),
    );
    await tester.pumpAndSettle();
    await drag.panZoomEnd();
    await tester.pumpAndSettle();
    expect(backs, 0);
    expect(find.text('dialog'), findsOneWidget);
    expect(_opacity(tester), 0);
  });

  testWidgets('native focus recovery enables a fresh gesture after blur', (
    tester,
  ) async {
    var backs = 0;
    await tester.pumpWidget(_app(onBack: () => backs++));
    final oldDrag = await _start(tester);
    await oldDrag.moveBy(const Offset(150, 0));
    tester.binding.handleViewFocusChanged(
      ViewFocusEvent(
        viewId: tester.view.viewId,
        state: ViewFocusState.unfocused,
        direction: ViewFocusDirection.undefined,
      ),
    );
    const channel = MethodChannel('bilisail/application_window');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'revision': 1,
        'viewId': tester.view.viewId,
        'active': true,
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await WindowInputFocus.instance.synchronizeNativeFocus();
    await oldDrag.panZoomEnd();
    expect(backs, 0);
    final newDrag = await _start(tester);
    await newDrag.moveBy(const Offset(150, 0));
    await newDrag.panZoomEnd();
    await tester.pumpAndSettle();
    expect(backs, 1);
  });

  testWidgets('reduced motion clears feedback on release', (tester) async {
    var backs = 0;
    await tester.pumpWidget(_app(onBack: () => backs++, reduceMotion: true));
    final drag = await _start(tester);
    await drag.moveBy(const Offset(150, 0));
    await tester.pump();
    expect(_opacity(tester), 1);
    await drag.panZoomEnd();
    await tester.pump();
    expect(backs, 1);
    expect(_opacity(tester), 0);
    expect(tester.hasRunningAnimations, isFalse);
  });
}

double _opacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find.ancestor(of: _indicator, matching: find.byType(Opacity)),
    )
    .opacity;

Future<TestGesture> _start(WidgetTester tester) async {
  final drag = await tester.createGesture(kind: PointerDeviceKind.trackpad);
  await drag.panZoomStart(_origin);
  return drag;
}

Widget _app({
  required VoidCallback onBack,
  Widget child = const SizedBox.expand(),
  bool enabled = true,
  bool active = true,
  Object identity = 'page',
  TargetPlatform platform = TargetPlatform.macOS,
  bool reduceMotion = false,
}) => InputTestApp(
  theme: ThemeData(platform: platform),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
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
);
