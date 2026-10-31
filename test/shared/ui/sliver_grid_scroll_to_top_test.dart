import 'package:bilisail/shared/ui/paged_scroll_viewport.dart';
import 'package:bilisail/shared/ui/responsive_card_grid.dart';
import 'package:bilisail/shared/ui/scroll_collapsing_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [430.0, 1800.0]) {
    testWidgets(
      'long return at $width skips unseen rows with identical frames',
      (tester) async {
        tester.view.physicalSize = Size(width, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final reference = await _run(tester, width: width, optimized: false);
        final measured = await _run(tester, width: width, optimized: true);
        _expectFrames(measured, reference);
        expect(measured.builds, lessThan(reference.builds * .7));
        expect(
          measured.maximumMounted,
          lessThanOrEqualTo(reference.maximumMounted),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final change in _Change.values) {
    testWidgets('reverse layout matches Flutter after $change', (tester) async {
      tester.view.physicalSize = const Size(430, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final reference = await _run(
        tester,
        width: 430,
        optimized: false,
        change: change,
      );
      tester.view.physicalSize = const Size(430, 600);
      final measured = await _run(
        tester,
        width: 430,
        optimized: true,
        change: change,
      );
      _expectFrames(measured, reference);
      expect(tester.takeException(), isNull);
    });
  }
}

enum _Change {
  data,
  width,
  textScale,
  offscreenTextScale,
  descendant,
  fonts,
  evicted,
  interrupted,
}

void _expectFrames(_Result measured, _Result reference) {
  expect(measured.frames.length, reference.frames.length);
  for (var i = 0; i < measured.frames.length; i++) {
    final actual = measured.frames[i];
    final expected = reference.frames[i];
    expect(actual.pixels, closeTo(expected.pixels, .000001));
    expect(actual.visible.keys, unorderedEquals(expected.visible.keys));
    for (final entry in actual.visible.entries) {
      final rect = expected.visible[entry.key];
      expect(rect, isNotNull);
      expect(entry.value.left, closeTo(rect!.left, .000001));
      expect(entry.value.top, closeTo(rect.top, .000001));
      expect(entry.value.size, rect.size);
    }
  }
}

typedef _Frame = ({double pixels, Map<int, Rect> visible});
typedef _Result = ({int builds, int maximumMounted, List<_Frame> frames});

Future<_Result> _run(
  WidgetTester tester, {
  required double width,
  required bool optimized,
  _Change? change,
}) async {
  await tester.pumpWidget(const SizedBox());
  var builds = 0;
  var version = 0;
  var textScale = 1.0;
  final extraHeight = ValueNotifier(0.0);
  late ScrollController controller;
  late StateSetter update;
  Widget card(BuildContext context, int index) {
    builds++;
    return _Card(
      index: index,
      extraHeight: extraHeight,
      version: version,
      offscreenScaleOnly: change == _Change.offscreenTextScale,
    );
  }

  Widget grid(double extent) {
    final columns = extent == 430 ? 2 : 6;
    final spacing = extent < 600 ? 6.0 : 20.0;
    final runSpacing = extent < 600 ? 16.0 : 24.0;
    final cardWidth = (extent - spacing * (columns - 1)) / columns;
    return optimized
        ? SliverResponsiveCardGrid(
            itemCount: 2000,
            itemBuilder: (context, index) => card(context, index),
          )
        : SliverList.builder(
            itemCount: (2000 / columns).ceil(),
            itemBuilder: (context, row) => Padding(
              padding: EdgeInsets.only(bottom: runSpacing),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: spacing,
                children: [
                  for (var column = 0; column < columns; column++)
                    if (row * columns + column < 2000)
                      SizedBox(
                        width: cardWidth,
                        child: RepaintBoundary(
                          child: card(context, row * columns + column),
                        ),
                      ),
                ],
              ),
            ),
          );
  }

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            final list = PagedScrollViewport(
              active: true,
              canLoadMore: false,
              contentVersion: 1,
              onLoadMore: () async {},
              onRefresh: () async {},
              builder: (value) {
                controller = value;
                return CustomScrollView(
                  controller: value,
                  slivers: [grid(width)],
                );
              },
            );
            return MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: change == _Change.interrupted
                  ? ScrollHeaderLayout(
                      enabled: true,
                      header: const SizedBox(height: 120),
                      child: list,
                    )
                  : list,
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Visiting the rows first mirrors browsing a long list, without retaining
  // any of their Elements. A forward jump also measures every intervening row.
  controller.jumpTo(change == _Change.evicted ? 200000 : 24000);
  await tester.pumpAndSettle();
  switch (change) {
    case _Change.data:
      update(() => version++);
    case _Change.width:
      width = 1800;
      tester.view.physicalSize = const Size(1800, 600);
      update(() {});
    case _Change.textScale || _Change.offscreenTextScale:
      update(() => textScale = 1.1);
    case _Change.descendant:
      extraHeight.value = 50;
    case _Change.fonts:
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/system',
        const JSONMessageCodec().encodeMessage({'type': 'fontsChange'}),
        (_) {},
      );
    case _Change.evicted || _Change.interrupted || null:
      break;
  }
  await tester.pumpAndSettle();
  final originalElements = tester.elementList(find.byType(_Card)).toList();
  builds = 0;
  await tester.tap(find.byTooltip('回到顶部'));
  await tester.pump();
  final frames = <_Frame>[];
  var maximumMounted = 0;
  for (var i = 0; i < 17; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (change == _Change.interrupted && i == 3) {
      await tester.dragFrom(const Offset(100, 300), const Offset(0, -80));
    }
    final visible = <int, Rect>{};
    final cards = find.byType(_Card);
    final elements = tester.elementList(cards).toList();
    if (elements.length > maximumMounted) maximumMounted = elements.length;
    for (final element in elements) {
      final rect = tester.getRect(find.byWidget(element.widget));
      if (rect.bottom > 0 && rect.top < 600) {
        visible[(element.widget as _Card).index] = rect;
      }
    }
    frames.add((pixels: controller.offset, visible: visible));
  }
  if (change == _Change.interrupted) {
    final stopped = controller.offset;
    await tester.pumpAndSettle();
    expect(controller.offset, stopped);
    expect(stopped, greaterThan(0));
  } else if (change == null ||
      change == _Change.fonts ||
      change == _Change.evicted) {
    expect(controller.offset, 0);
  }
  expect(originalElements.every((element) => !element.mounted), isTrue);
  await tester.pumpWidget(const SizedBox());
  extraHeight.dispose();
  return (builds: builds, maximumMounted: maximumMounted, frames: frames);
}

class _Card extends StatelessWidget {
  const _Card({
    required this.index,
    required this.extraHeight,
    required this.version,
    required this.offscreenScaleOnly,
  });
  final int index;
  final ValueNotifier<double> extraHeight;
  final int version;
  final bool offscreenScaleOnly;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.primaries[index % Colors.primaries.length],
    child: ValueListenableBuilder(
      valueListenable: extraHeight,
      builder: (context, extra, _) => SizedBox(
        height:
            (offscreenScaleOnly && index > 50
                    ? TextScaler.noScaling
                    : MediaQuery.textScalerOf(context))
                .scale(100 + (index % 7) * 17.0 + version * 11 + extra),
        child: Text('Card $index'),
      ),
    ),
  );
}
