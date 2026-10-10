import 'package:bilisail/shared/ui/width_layout_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('height changes relayout the child without rebuilding it', (
    tester,
  ) async {
    final dimensions = ValueNotifier(const Size(390, 700));
    addTearDown(dimensions.dispose);
    var builds = 0;
    var taps = 0;
    final child = WidthLayoutBuilder(
      builder: (_, width) {
        builds++;
        return GestureDetector(
          key: const Key('content'),
          behavior: HitTestBehavior.opaque,
          onTap: () => taps++,
          child: const SizedBox.expand(),
        );
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: ValueListenableBuilder<Size>(
            valueListenable: dimensions,
            child: child,
            builder: (_, size, child) =>
                SizedBox.fromSize(size: size, child: child),
          ),
        ),
      ),
    );
    expect(builds, 1);
    for (final height in [500.0, 300.0, 0.0, 500.0]) {
      dimensions.value = Size(390, height);
      await tester.pump();
      expect(builds, 1);
      expect(tester.getSize(find.byKey(const Key('content'))).height, height);
    }
    dimensions.value = const Size(700, 500);
    await tester.pump();
    expect(builds, 2);
    expect(tester.getSize(find.byKey(const Key('content'))).width, 700);
    await tester.tap(find.byKey(const Key('content')));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inherited typography changes rebuild at the same width', (
    tester,
  ) async {
    final revision = ValueNotifier(0);
    addTearDown(revision.dispose);
    var builds = 0;
    final child = WidthLayoutBuilder(
      builder: (context, width) {
        builds++;
        return Text(
          '${Theme.of(context).brightness.name}/'
          '${DefaultTextStyle.of(context).style.fontSize}/'
          '${Directionality.of(context).name}/'
          '${MediaQuery.textScalerOf(context).scale(10)}',
        );
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<int>(
          valueListenable: revision,
          child: child,
          builder: (_, value, child) => Theme(
            data: ThemeData(
              brightness: value == 0 ? Brightness.light : Brightness.dark,
            ),
            child: DefaultTextStyle(
              style: TextStyle(fontSize: value == 0 ? 12 : 24),
              child: Directionality(
                textDirection: value == 0
                    ? TextDirection.ltr
                    : TextDirection.rtl,
                child: MediaQuery(
                  data: MediaQueryData(
                    textScaler: TextScaler.linear(value == 0 ? 1 : 2),
                  ),
                  child: child ?? const SizedBox(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('light/12.0/ltr/10.0'), findsOneWidget);
    revision.value = 1;
    await tester.pump();
    expect(builds, 2);
    expect(find.text('dark/24.0/rtl/20.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('updated content and explicit inset dependencies remain live', (
    tester,
  ) async {
    var builds = 0;
    Widget app(String label) => MaterialApp(
      home: WidthLayoutBuilder(
        builder: (context, width) {
          builds++;
          return Text('$label/${MediaQuery.viewInsetsOf(context).bottom}');
        },
      ),
    );
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(app('first'));
    expect(find.text('first/0.0'), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    await tester.pump();
    expect(builds, 2);
    expect(find.text('first/200.0'), findsOneWidget);
    await tester.pumpWidget(app('second'));
    expect(builds, 3);
    expect(find.text('second/200.0'), findsOneWidget);
  });

  testWidgets('natural height and text baseline are forwarded after layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: WidthLayoutBuilder(
                  builder: (_, width) =>
                      const Text('baseline', style: TextStyle(fontSize: 24)),
                ),
              ),
              const Text('peer', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(WidthLayoutBuilder)).height,
      greaterThan(0),
    );
    expect(tester.takeException(), isNull);
  });
}
