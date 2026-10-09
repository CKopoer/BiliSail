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
  testWidgets('page and tab strip complete a 200ms tap transition together', (
    tester,
  ) async {
    await _mount(tester);
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final position = _pagePosition(tester);
    expect(position.pixels, inExclusiveRange(0, position.viewportDimension));
    await _expectPagingSync(
      tester,
      position.pixels / position.viewportDimension,
    );
    await tester.pump(const Duration(milliseconds: 120));
    // The driven scroll ends on the first frame after its duration expires.
    await tester.pump(const Duration(milliseconds: 16));
    expect(position.isScrollingNotifier.value, isFalse);
    expect(position.pixels, closeTo(position.viewportDimension, .1));
    await _expectPagingSync(tester, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('standalone tab strip completes a selection within 200ms', (
    tester,
  ) async {
    final selected = await _mount(tester, connectProgress: false);
    selected.value = 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    await _expectPagingSync(tester, 1);
    expect(tester.takeException(), isNull);
  });

  for (final rtl in [false, true]) {
    for (final pixelRatio in [1.0, 3.0]) {
      for (final complete in [false, true]) {
        testWidgets(
          'page and tab strip settle together within 320ms: rtl=$rtl dpr=$pixelRatio complete=$complete',
          (tester) async {
            final selected = await _mount(
              tester,
              rtl: rtl,
              pixelRatio: pixelRatio,
            );
            final position = _pagePosition(tester);
            final gesture = await tester.startGesture(
              tester.getCenter(find.byKey(_surface)),
            );
            await gesture.moveBy(
              Offset((rtl ? 1 : -1) * (complete ? 220 : 80), 0),
            );
            await tester.pump();
            await gesture.up();
            await tester.pump();
            for (var frame = 0; frame < 20; frame++) {
              await tester.pump(const Duration(milliseconds: 16));
              final progress = position.pixels / position.viewportDimension;
              expect(progress, inInclusiveRange(0, 1));
              await _expectPagingSync(tester, progress);
            }
            expect(position.isScrollingNotifier.value, isFalse);
            expect(selected.value, complete ? 1 : 0);
            expect(
              position.pixels,
              closeTo(complete ? position.viewportDimension : 0, .1),
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

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
    'narrow enlarged strip scrolls during paging before selection settles',
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
      await tester.pump();
      await tester.pump();
      expect(selected.value, 0);
      expect(horizontal.pixels, greaterThan(before));
      expect(horizontal.pixels, lessThan(horizontal.maxScrollExtent));
      await gesture.up();
      for (var frame = 0; selected.value != 1 && frame < 60; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(selected.value, 1);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tab-1')).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final rtl in [false, true]) {
    for (final fullWidth in [false, true]) {
      testWidgets(
        'strip follows both swipe directions continuously: rtl=$rtl full=$fullWidth',
        (tester) async {
          final selected = await _mount(
            tester,
            width: 300,
            scale: 1.5,
            tabCount: 8,
            initialIndex: 3,
            rtl: rtl,
            fullWidth: fullWidth,
          );
          final horizontal = _horizontalPosition(tester);
          final viewport = tester.getRect(find.byKey(_boundary));
          expect(
            tester.getCenter(find.byKey(const ValueKey('tab-3'))).dx,
            closeTo(viewport.center.dx, 1),
          );
          for (final forward in [true, false]) {
            final source = forward ? 3 : 4;
            final target = forward ? 4 : 3;
            final sign = (rtl ? 1.0 : -1.0) * (forward ? 1 : -1);
            final gesture = await tester.startGesture(
              tester.getCenter(find.byKey(_surface)),
            );
            var previous = horizontal.pixels;
            for (var step = 1; step <= 3; step++) {
              await gesture.moveBy(Offset(sign * 60, 0));
              await tester.pump();
              await tester.pump();
              expect(selected.value, source);
              expect(
                horizontal.pixels,
                forward ? greaterThan(previous) : lessThan(previous),
              );
              previous = horizontal.pixels;
              // The moving indicator stays centered while labels slide past it.
              expect(
                (await _line(tester, fullWidth)).center.dx,
                closeTo(viewport.center.dx, 1),
              );
            }
            await gesture.up();
            await tester.pumpAndSettle();
            expect(selected.value, target);
            expect(
              tester.getCenter(find.byKey(ValueKey('tab-$target'))).dx,
              closeTo(viewport.center.dx, 1),
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('consecutive swipes center tabs and clamp ends: rtl=$rtl', (
      tester,
    ) async {
      final selected = await _mount(
        tester,
        width: 300,
        scale: 1.5,
        tabCount: 8,
        rtl: rtl,
      );
      final horizontal = _horizontalPosition(tester);
      for (final index in [
        ...List.generate(7, (i) => i + 1),
        6,
        5,
        4,
        3,
        2,
        1,
        0,
      ]) {
        final forward = index > selected.value;
        await tester.drag(
          find.byKey(_surface),
          Offset((rtl ? 1 : -1) * (forward ? 220.0 : -220.0), 0),
        );
        await tester.pumpAndSettle();
        expect(selected.value, index);
        final tab = tester.getRect(find.byKey(ValueKey('tab-$index')));
        final viewport = tester.getRect(find.byKey(_boundary));
        expect(tab.left, greaterThanOrEqualTo(viewport.left - 1));
        expect(tab.right, lessThanOrEqualTo(viewport.right + 1));
        if (index >= 2 && index <= 5) {
          expect(tab.center.dx, closeTo(viewport.center.dx, 1));
        }
        if (index == 7) {
          expect(horizontal.pixels, closeTo(horizontal.maxScrollExtent, .1));
        } else if (index == 0) {
          expect(horizontal.pixels, closeTo(horizontal.minScrollExtent, .1));
        }
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('strip returns with a short or cancelled page drag', (
    tester,
  ) async {
    final selected = await _mount(
      tester,
      width: 300,
      scale: 1.5,
      tabCount: 8,
      initialIndex: 3,
    );
    final horizontal = _horizontalPosition(tester);
    final initial = horizontal.pixels;
    for (final cancel in [false, true]) {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_surface)),
      );
      await gesture.moveBy(const Offset(-80, 0));
      await tester.pump();
      await tester.pump();
      expect(horizontal.pixels, greaterThan(initial));
      if (cancel) {
        await gesture.cancel();
      } else {
        await gesture.up();
      }
      await tester.pumpAndSettle();
      expect(selected.value, 3);
      expect(horizontal.pixels, closeTo(initial, .1));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'idle strip drag stays independent and paging resumes centering',
    (tester) async {
      final selected = await _mount(
        tester,
        width: 300,
        scale: 1.5,
        tabCount: 8,
        initialIndex: 3,
      );
      final horizontal = _horizontalPosition(tester);
      final initial = horizontal.pixels;
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(-130, 0),
      );
      await tester.pumpAndSettle();
      expect(selected.value, 3);
      expect(horizontal.pixels, greaterThan(initial + 100));
      await tester.drag(find.byKey(_surface), const Offset(-220, 0));
      await tester.pumpAndSettle();
      expect(selected.value, 4);
      expect(
        tester.getCenter(find.byKey(const ValueKey('tab-4'))).dx,
        closeTo(tester.getRect(find.byKey(_boundary)).center.dx, 1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reduced motion external selection centers and clamps immediately',
    (tester) async {
      final selected = await _mount(
        tester,
        width: 300,
        scale: 1.5,
        tabCount: 8,
        disableAnimations: true,
      );
      final horizontal = _horizontalPosition(tester);
      for (final index in [3, 7, 0]) {
        selected.value = index;
        await tester.pump();
        await tester.pump();
        if (index == 3) {
          expect(
            tester.getCenter(find.byKey(const ValueKey('tab-3'))).dx,
            closeTo(tester.getRect(find.byKey(_boundary)).center.dx, 1),
          );
        } else {
          expect(
            horizontal.pixels,
            closeTo(
              index == 0
                  ? horizontal.minScrollExtent
                  : horizontal.maxScrollExtent,
              .1,
            ),
          );
        }
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('fallback selection animation scrolls and can be retargeted', (
    tester,
  ) async {
    final selected = await _mount(
      tester,
      width: 300,
      scale: 1.5,
      tabCount: 8,
      initialIndex: 3,
      connectProgress: false,
    );
    final horizontal = _horizontalPosition(tester);
    final initial = horizontal.pixels;
    selected.value = 4;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(horizontal.pixels, greaterThan(initial));
    expect(horizontal.pixels, lessThan(horizontal.maxScrollExtent));
    selected.value = 0;
    await tester.pumpAndSettle();
    expect(horizontal.pixels, closeTo(horizontal.minScrollExtent, .1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('resizing the viewport keeps the active tab centered', (
    tester,
  ) async {
    await _mount(tester, width: 300, scale: 1.5, tabCount: 8, initialIndex: 3);
    tester.view.physicalSize = const Size(420, 800);
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.byKey(const ValueKey('tab-3'))).dx,
      closeTo(tester.getRect(find.byKey(_boundary)).center.dx, 1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a fully visible strip stays still during page swipes', (
    tester,
  ) async {
    final selected = await _mount(tester, width: 1000, scale: 1.5, tabCount: 8);
    final horizontal = _horizontalPosition(tester);
    final original = [
      for (var tab = 0; tab < 8; tab++)
        tester.getRect(find.byKey(ValueKey('tab-$tab'))),
    ];
    expect(horizontal.maxScrollExtent, 0);
    for (final forward in [true, false]) {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_surface)),
      );
      await gesture.moveBy(Offset(forward ? -700 : 700, 0));
      await tester.pump();
      await tester.pump();
      expect(horizontal.pixels, 0);
      for (var tab = 0; tab < 8; tab++) {
        expect(tester.getRect(find.byKey(ValueKey('tab-$tab'))), original[tab]);
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(selected.value, forward ? 1 : 0);
      expect(horizontal.pixels, 0);
    }
    expect(tester.takeException(), isNull);
  });
}

ScrollPosition _pagePosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(PageView),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

Future<void> _expectPagingSync(WidgetTester tester, double progress) async {
  final first = tester.getRect(find.byKey(const ValueKey('tab-0')));
  final second = tester.getRect(find.byKey(const ValueKey('tab-1')));
  expect(
    (await _line(tester, false)).center.dx,
    closeTo(
      first.center.dx + (second.center.dx - first.center.dx) * progress,
      1,
    ),
  );
  final button = tester.widget<TextButton>(find.byKey(const ValueKey('tab-1')));
  final colors = Theme.of(tester.element(find.byKey(_surface))).colorScheme;
  expect(
    button.style?.foregroundColor?.resolve({})?.toARGB32(),
    Color.lerp(colors.onSurface, _primary, progress)?.toARGB32(),
  );
}

ScrollPosition _horizontalPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byKey(_boundary),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

Future<ValueNotifier<int>> _mount(
  WidgetTester tester, {
  bool fullWidth = false,
  bool rtl = false,
  double width = 375,
  double scale = 1,
  double pixelRatio = 1,
  bool disableAnimations = false,
  int tabCount = 3,
  int initialIndex = 0,
  bool connectProgress = true,
}) async {
  tester.view.physicalSize = Size(width * pixelRatio, 800 * pixelRatio);
  tester.view.devicePixelRatio = pixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final tabs = List.generate(tabCount, (index) => index);
  final selected = ValueNotifier(initialIndex);
  final progress = TabPagingProgress(initialIndex.toDouble());
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
                    tabs: tabs,
                    value: value,
                    onSelected: (value) => selected.value = value,
                    progress: connectProgress ? progress : null,
                    fullWidthIndicator: fullWidth,
                    indicatorHeight: fullWidth ? 3 : 2,
                    buttonStyle: TextButton.styleFrom(
                      minimumSize: const Size(48, 44),
                    ),
                    itemKey: (tab) => ValueKey('tab-$tab'),
                    labelBuilder: (_, tab) => Text(
                      ['一', '更长分类', '三', '第四项', '第五项', '六', '第七项', '八'][tab],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: RetainedTabView<int>(
                  tabs: tabs,
                  value: value,
                  onChanged: (value) => selected.value = value,
                  progress: connectProgress ? progress : null,
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
