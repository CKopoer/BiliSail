import 'package:bilisail/shared/ui/content_section_tabs.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _entries = [(0, '综合热门'), (1, '每周必看'), (2, '入站必刷'), (3, '排行榜')];

void main() {
  testWidgets('wrapped choices remain selectable and visible after collapse', (
    tester,
  ) async {
    late StateSetter rebuild;
    var wrap = false;
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 220,
                  child: ContentSectionTabs<int>(
                    entries: _entries,
                    value: selected,
                    wrap: wrap,
                    onSelected: (value) => setState(() => selected = value),
                    itemKey: (id) => ValueKey('section-$id'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final first = find.byKey(const ValueKey('section-0'));
    final last = find.byKey(const ValueKey('section-3'));
    expect(last.hitTestable(), findsNothing);

    rebuild(() => wrap = true);
    await tester.pumpAndSettle();
    expect(tester.getRect(last).top, greaterThan(tester.getRect(first).top));
    for (final (id, _) in _entries) {
      expect(find.byKey(ValueKey('section-$id')).hitTestable(), findsOneWidget);
    }
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(selected, 3);

    rebuild(() => wrap = false);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(ContentSectionTabs<int>)).height, 44);
    expect(last.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wheel position survives ordinary rebuilds with equal entries', (
    tester,
  ) async {
    late StateSetter rebuild;
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 220,
                  child: ContentSectionTabs<int>(
                    entries: [..._entries],
                    value: selected,
                    onSelected: (value) => setState(() => selected = value),
                    itemKey: (id) => ValueKey('section-$id'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final strip = find.byType(SingleChildScrollView);
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: strip, matching: find.byType(Scrollable)),
        )
        .position;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: tester.getCenter(strip),
        scrollDelta: const Offset(0, 800),
      ),
    );
    await tester.pumpAndSettle();
    final wheelOffset = position.pixels;
    expect(wheelOffset, greaterThan(0));
    expect(
      find.byKey(const ValueKey('section-3')).hitTestable(),
      findsOneWidget,
    );
    rebuild(() {});
    await tester.pumpAndSettle();
    expect(position.pixels, wheelOffset);
    await tester.tap(find.byKey(const ValueKey('section-3')));
    await tester.pumpAndSettle();
    expect(selected, 3);
    expect(position.pixels, wheelOffset);
    final semantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('section-3')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(semantics.properties.selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local constraint changes minimally reveal selection', (
    tester,
  ) async {
    final width = ValueNotifier(600.0);
    addTearDown(width.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ValueListenableBuilder(
              valueListenable: width,
              builder: (context, value, _) => SizedBox(
                width: value,
                child: ContentSectionTabs<int>(
                  entries: _entries,
                  value: 3,
                  onSelected: (_) {},
                  itemKey: (id) => ValueKey('section-$id'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final viewportWidth = MediaQuery.sizeOf(
      tester.element(find.byType(ContentSectionTabs<int>)),
    ).width;
    final strip = find.byType(ContentSectionTabs<int>);
    final selected = find.byKey(const ValueKey('section-3'));
    expect(tester.getRect(find.byKey(const ValueKey('section-0'))).left, 12);
    width.value = 180;
    await tester.pumpAndSettle();
    expect(MediaQuery.sizeOf(tester.element(strip)).width, viewportWidth);
    expect(
      tester.getRect(selected).right,
      closeTo(tester.getRect(strip).right - 16, .1),
    );
    expect(selected.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text keeps the compact row and rounded hover feedback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              child: ContentSectionTabs<int>(
                entries: _entries,
                value: 0,
                onSelected: (_) {},
                itemKey: (id) => ValueKey('section-$id'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final strip = find.byType(ContentSectionTabs<int>);
    expect(tester.getSize(strip).height, 44);
    final style = tester
        .widget<TextButton>(find.byKey(const ValueKey('section-0')))
        .style!;
    final colors = Theme.of(tester.element(strip)).colorScheme;
    expect(style.backgroundColor?.resolve({}), Colors.transparent);
    expect(
      style.backgroundColor?.resolve({WidgetState.hovered}),
      colors.surfaceContainerLow,
    );
    expect(
      style.overlayColor?.resolve({WidgetState.hovered}),
      Colors.transparent,
    );
    expect(
      (style.shape?.resolve({}) as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(10),
    );
    expect(tester.takeException(), isNull);
  });
}
