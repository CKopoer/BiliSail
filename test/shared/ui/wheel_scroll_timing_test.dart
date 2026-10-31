import 'package:bilisail/shared/ui/paged_scroll_viewport.dart';
import 'package:bilisail/shared/ui/scroll_collapsing_header.dart';
import 'package:bilisail/shared/ui/smooth_scroll_behavior.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final coordinated in [false, true]) {
    for (final dilation in [1.0, 2.0]) {
      testWidgets('timestamped wheel stream is independent of frame grouping '
          '(header=$coordinated, timeDilation=$dilation)', (tester) async {
        timeDilation = dilation;
        addTearDown(() => timeDilation = 1);
        try {
          final samples = <({double pixels, double velocity})>[];
          for (final frameMs in [8, 16, 32, 96]) {
            final controller = await _mount(tester, coordinated: coordinated);
            final origin = tester.binding.currentSystemFrameTimeStamp;
            final events = [1, 14, 17, 30, 35, 48, 63];
            var event = 0;
            for (var time = frameMs; time <= 96; time += frameMs) {
              while (event < events.length && events[event] <= time) {
                await _wheel(
                  tester,
                  origin + Duration(milliseconds: events[event]),
                );
                event++;
              }
              await tester.pump(Duration(milliseconds: frameMs));
            }
            samples.add((
              pixels: controller.offset,
              velocity: controller.position.activity!.velocity,
            ));
            await tester.pumpAndSettle();
            expect(
              controller.offset,
              closeTo(500 + events.length * 120, .000001),
            );
            await tester.pumpWidget(const SizedBox());
            if (!coordinated) controller.dispose();
          }
          for (final sample in samples.skip(1)) {
            expect(sample.pixels, closeTo(samples.first.pixels, .000001));
            expect(sample.velocity, closeTo(samples.first.velocity, .000001));
          }
          expect(tester.takeException(), isNull);
        } finally {
          timeDilation = 1;
        }
      });
    }
  }

  testWidgets('timestamped first wheel moves on its first frame', (
    tester,
  ) async {
    final controller = await _mount(tester);
    final origin = tester.binding.currentSystemFrameTimeStamp;
    await _wheel(tester, origin + const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 8));
    expect(controller.offset, inExclusiveRange(500, 620));
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(620, .000001));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('missing and queued timestamps never rewind a retarget; '
      'reversal discards unpainted old momentum', (tester) async {
    final controller = await _mount(tester);
    final origin = tester.binding.currentSystemFrameTimeStamp;
    await _wheel(tester, origin + const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 8));
    final activity = controller.position.activity;
    final before = controller.offset;
    await _wheel(tester, origin + const Duration(milliseconds: 10));
    await _wheel(tester, Duration.zero);
    await _wheel(tester, origin + const Duration(milliseconds: 6));
    expect(controller.offset, before);
    expect(controller.position.activity, same(activity));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.offset, greaterThan(before));
    final beforeReverse = controller.offset;
    await _wheel(
      tester,
      origin + const Duration(milliseconds: 23),
      delta: -120,
    );
    await tester.pump(const Duration(milliseconds: 8));
    expect(controller.offset, lessThan(beforeReverse));
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(beforeReverse - 120, .000001));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('late wheel input only contributes after its timestamp', (
    tester,
  ) async {
    final offsets = <double>[];
    for (final secondInputMs in [17, 31]) {
      final controller = await _mount(tester);
      final origin = tester.binding.currentSystemFrameTimeStamp;
      await _wheel(tester, origin + const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 16));
      final before = controller.offset;
      await _wheel(tester, origin + Duration(milliseconds: secondInputMs));
      expect(controller.offset, before);
      await tester.pump(const Duration(milliseconds: 16));
      offsets.add(controller.offset);
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(740, .000001));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }
    expect(offsets.first - offsets.last, greaterThan(5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('input newer than vsync waits for the following frame', (
    tester,
  ) async {
    final samples = <double>[];
    for (final withPendingInput in [false, true]) {
      final controller = await _mount(tester);
      final origin = tester.binding.currentSystemFrameTimeStamp;
      await _wheel(tester, origin + const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 16));
      if (withPendingInput) {
        await _wheel(tester, origin + const Duration(milliseconds: 38));
      }
      await tester.pump(const Duration(milliseconds: 16));
      samples.add(controller.offset);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(withPendingInput ? 740 : 620, .000001));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }
    expect(samples.last, closeTo(samples.first, .000001));
    expect(tester.takeException(), isNull);
  });

  for (final reverse in [false, true]) {
    testWidgets(
      'dense queued input is bounded and retains the latest direction '
      '(reverse=$reverse)',
      (tester) async {
        final controller = await _mount(tester);
        final origin = tester.binding.currentSystemFrameTimeStamp;
        for (var i = 0; i < 200; i++) {
          await _wheel(tester, origin + Duration(microseconds: 1000 + i));
        }
        if (reverse) {
          await _wheel(
            tester,
            origin + const Duration(microseconds: 1201),
            delta: -120,
          );
        }
        await tester.pumpAndSettle();
        expect(controller.offset, closeTo(reverse ? 380 : 2000, .000001));
        expect(controller.position.isScrollingNotifier.value, isFalse);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }
  testWidgets('reaching the edge discards old travel while later input waits', (
    tester,
  ) async {
    final count = ValueNotifier(20);
    final controller = ScrollController();
    addTearDown(count.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        scrollBehavior: const SmoothScrollBehavior(),
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: count,
            builder: (_, value, _) => ListView.builder(
              key: const ValueKey('wheel-timing-list'),
              controller: controller,
              itemExtent: 100,
              itemCount: value,
              itemBuilder: (_, i) => Text('row $i'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final edge = controller.position.maxScrollExtent;
    controller.jumpTo(edge - 10);
    await tester.pump();
    final origin = tester.binding.currentSystemFrameTimeStamp;
    await _wheel(tester, origin + const Duration(milliseconds: 1));
    await _wheel(tester, origin + const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 64));
    expect(controller.offset, edge);
    count.value = 30;
    await tester.pump();
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(edge + 120, .000001));
    expect(controller.position.isScrollingNotifier.value, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final damping in [.5, 2.0]) {
    testWidgets('timestamped input preserves damping $damping and takes over '
        'an elastic rebound', (tester) async {
      final controller = await _mount(tester, damping: damping);
      final origin = tester.binding.currentSystemFrameTimeStamp;
      await _wheel(tester, origin + const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 110));
      final before = controller.offset;
      if (damping < 1) {
        expect(before, greaterThan(620));
        expect(controller.position.activity!.velocity, lessThan(0));
      }
      await _wheel(tester, origin + const Duration(milliseconds: 111));
      await tester.pump(const Duration(milliseconds: 8));
      expect(controller.offset, greaterThan(before));
      await tester.pumpAndSettle();
      expect(
        controller.offset,
        closeTo(damping < 1 ? before + 120 : 740, .000001),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }
}

Future<ScrollController> _mount(
  WidgetTester tester, {
  bool coordinated = false,
  double damping = 1.3,
}) async {
  late ScrollController controller;
  Widget list(ScrollController scroll) => ListView.builder(
    key: const ValueKey('wheel-timing-list'),
    controller: scroll,
    itemExtent: 100,
    itemCount: 300,
    itemBuilder: (_, i) => Text('row $i'),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      scrollBehavior: const SmoothScrollBehavior(),
      home: SmoothScrollScope(
        dampingRatio: damping,
        child: Scaffold(
          body: coordinated
              ? ScrollHeaderLayout(
                  enabled: false,
                  header: const SizedBox.shrink(),
                  child: PagedScrollViewport(
                    active: true,
                    canLoadMore: false,
                    contentVersion: 1,
                    onLoadMore: () async {},
                    builder: (scroll) {
                      controller = scroll;
                      return list(scroll);
                    },
                  ),
                )
              : list(controller = ScrollController()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  controller.jumpTo(500);
  await tester.pump();
  return controller;
}

Future<void> _wheel(
  WidgetTester tester,
  Duration stamp, {
  double delta = 120,
}) => tester.sendEventToBinding(
  PointerScrollEvent(
    timeStamp: stamp,
    kind: PointerDeviceKind.mouse,
    position: tester.getCenter(find.byKey(const ValueKey('wheel-timing-list'))),
    scrollDelta: Offset(0, delta),
  ),
);
