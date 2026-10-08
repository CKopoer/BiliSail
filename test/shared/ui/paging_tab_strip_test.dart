import 'dart:ui' as ui;

import 'package:bilisail/shared/ui/paging_tab_strip.dart';
import 'package:bilisail/shared/ui/retained_tab_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _primary = Color(0xff0077dd);
const _boundary = ValueKey('strip-pixels');
const _surface = ValueKey('test-pager');

void main() {
  testWidgets(
    'reduced motion moves the tab and underline directly to the target',
    (tester) async {
      await _mount(tester, disableAnimations: true);
      final last = tester.getRect(find.byKey(const ValueKey('tab-2')));
      await tester.tap(find.byKey(const ValueKey('tab-2')));
      await tester.pump();
      await tester.pump();
      expect(
        (await _line(tester, false)).center.dx,
        closeTo(last.center.dx, 1),
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final fullWidth in [false, true]) {
    for (final rtl in [false, true]) {
      testWidgets(
        'indicator follows drag and rebound: full=$fullWidth rtl=$rtl',
        (tester) async {
          await _mount(tester, fullWidth: fullWidth, rtl: rtl);
          final first = tester.getRect(find.byKey(const ValueKey('tab-0')));
          final second = tester.getRect(find.byKey(const ValueKey('tab-1')));
          final initial = await _line(tester, fullWidth);
          expect(initial.center.dx, closeTo(first.center.dx, 1));
          final gesture = await tester.startGesture(
            tester.getCenter(find.byKey(_surface)),
          );
          await gesture.moveBy(Offset(rtl ? 80 : -80, 0));
          await tester.pump();
          await tester.pump();
          final dragged = await _line(tester, fullWidth);
          expect(
            dragged.center.dx,
            closeTo(
              first.center.dx + (second.center.dx - first.center.dx) * 80 / 375,
              1,
            ),
          );
          expect(dragged.width, greaterThanOrEqualTo(19));
          await gesture.up();
          final centers = <double>[];
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            centers.add((await _line(tester, fullWidth)).center.dx);
          }
          expect(centers.toSet().length, greaterThan(3));
          await tester.pumpAndSettle();
          expect(
            (await _line(tester, fullWidth)).center.dx,
            closeTo(first.center.dx, 1),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'tap indicator traverses continuously and rapid taps stop at target',
    (tester) async {
      await _mount(tester);
      final first = tester.getRect(find.byKey(const ValueKey('tab-0')));
      final last = tester.getRect(find.byKey(const ValueKey('tab-2')));
      await tester.tap(find.byKey(const ValueKey('tab-2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final middle = await _line(tester, false);
      expect(
        middle.center.dx,
        inExclusiveRange(first.center.dx, last.center.dx),
      );
      await tester.tap(find.byKey(const ValueKey('tab-0')));
      await tester.pumpAndSettle();
      expect(
        (await _line(tester, false)).center.dx,
        closeTo(first.center.dx, 1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow enlarged strip reveals only obscured selection smoothly',
    (tester) async {
      final selected = await _mount(tester, width: 180, scale: 2);
      final horizontal = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byKey(_boundary),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      final before = horizontal.pixels;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_surface)),
      );
      await gesture.moveBy(const Offset(-130, 0));
      await gesture.up();
      for (var frame = 0; selected.value != 1 && frame < 60; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(selected.value, 1);
      await tester.pump();
      expect(horizontal.pixels, closeTo(before, .1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(horizontal.pixels, greaterThan(before));
      expect(horizontal.pixels, lessThan(horizontal.maxScrollExtent));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tab-1')).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<ValueNotifier<int>> _mount(
  WidgetTester tester, {
  bool fullWidth = false,
  bool rtl = false,
  double width = 375,
  double scale = 1,
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final selected = ValueNotifier(0);
  final progress = TabPagingProgress(0);
  addTearDown(selected.dispose);
  addTearDown(progress.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _primary)
            .copyWith(primary: _primary),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: disableAnimations,
        ),
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: child ?? const SizedBox(),
        ),
      ),
      home: Scaffold(
        body: ValueListenableBuilder(
          valueListenable: selected,
          builder: (context, value, _) => Column(
            children: [
              RepaintBoundary(
                key: _boundary,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: PagingTabStrip<int>(
                    tabs: const [0, 1, 2],
                    value: value,
                    onSelected: (value) => selected.value = value,
                    progress: progress,
                    fullWidthIndicator: fullWidth,
                    indicatorHeight: fullWidth ? 3 : 2,
                    buttonStyle: TextButton.styleFrom(
                      minimumSize: const Size(48, 44),
                    ),
                    itemKey: (tab) => ValueKey('tab-$tab'),
                    labelBuilder: (_, tab) => Text(['一', '更长分类', '三'][tab]),
                  ),
                ),
              ),
              Expanded(
                child: RetainedTabView<int>(
                  tabs: const [0, 1, 2],
                  value: value,
                  onChanged: (value) => selected.value = value,
                  progress: progress,
                  viewKey: _surface,
                  pageBuilder: (_, tab, active) =>
                      ColoredBox(color: Colors.grey.shade100),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return selected;
}

/// Scan the painted underline row, independent of the painter's geometry code.
Future<Rect> _line(WidgetTester tester, bool fullWidth) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundary),
  );
  final result = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError('Missing strip pixels');
      final y = image.height - (fullWidth ? 2 : 9);
      final xs = <int>[];
      for (var x = 0; x < image.width; x++) {
        final offset = (y * image.width + x) * 4;
        if (data.getUint8(offset) == 0 &&
            data.getUint8(offset + 1) == 0x77 &&
            data.getUint8(offset + 2) == 0xdd &&
            data.getUint8(offset + 3) == 255) {
          xs.add(x);
        }
      }
      if (xs.isEmpty) throw StateError('Underline disappeared');
      return Rect.fromLTRB(
        xs.first.toDouble(),
        y.toDouble(),
        xs.last + 1.0,
        y + 1.0,
      );
    } finally {
      image.dispose();
    }
  });
  if (result == null) throw StateError('Missing strip capture');
  return result.shift(tester.getTopLeft(find.byKey(_boundary)));
}
