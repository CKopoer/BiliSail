import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/shared/ui/scroll_collapsing_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _header = ValueKey('header');
const _list = ValueKey('vertical-list');

void main() {
  late ScrollController controller;

  setUp(() => controller = ScrollController());
  tearDown(() => controller.dispose());

  Future<void> mount(
    WidgetTester tester, {
    bool enabled = true,
    bool active = true,
    bool reduceMotion = false,
    int count = 100,
    Future<void> Function()? onRefresh,
  }) async {
    final list = ListView.builder(
      key: _list,
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      itemExtent: 60,
      itemCount: count,
      itemBuilder: (_, index) => Text('item $index'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(
            body: ScrollHeaderRegion(
              enabled: enabled,
              child: Column(
                children: [
                  const ScrollCollapsingHeader(
                    key: _header,
                    child: SizedBox(height: 80, child: TextField()),
                  ),
                  SizedBox(
                    height: 60,
                    child: ListView.builder(
                      key: const ValueKey('horizontal-list'),
                      scrollDirection: Axis.horizontal,
                      itemExtent: 100,
                      itemCount: 20,
                      itemBuilder: (_, index) => Text('tab $index'),
                    ),
                  ),
                  Expanded(
                    child: WorkspaceActivity(
                      active: active,
                      child: onRefresh == null
                          ? list
                          : RefreshIndicator(onRefresh: onRefresh, child: list),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('slides up, frees space, and reappears before reaching the top', (
    tester,
  ) async {
    await mount(tester);
    final element = tester.element(find.byKey(_list));
    final initialTop = tester.getTopLeft(find.byKey(_list)).dy;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_list)),
    );
    await gesture.moveBy(const Offset(0, -180));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(find.byKey(_header)).height, inExclusiveRange(0, 80));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(_header)).height, 0);
    expect(find.byType(TextField).hitTestable(), findsNothing);
    expect(tester.getTopLeft(find.byKey(_list)).dy, initialTop - 80);
    expect(tester.element(find.byKey(_list)), same(element));
    await tester.drag(find.byKey(_list), const Offset(0, 65));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    expect(tester.getSize(find.byKey(_header)).height, 80);
    expect(find.byType(TextField).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('horizontal paging and programmatic movement keep the header', (
    tester,
  ) async {
    await mount(tester);
    await tester.drag(
      find.byKey(const ValueKey('horizontal-list')),
      const Offset(-220, 0),
    );
    await tester.pumpAndSettle();
    controller.jumpTo(300);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(_header)).height, 80);
    await tester.drag(find.byKey(_list), const Offset(0, -100));
    await tester.pumpAndSettle();
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(_header)).height, 0);
  });

  for (final (enabled, active, count) in [
    (false, true, 100),
    (true, false, 100),
    (true, true, 1),
  ]) {
    testWidgets('ignores scroll enabled=$enabled active=$active count=$count', (
      tester,
    ) async {
      await mount(tester, enabled: enabled, active: active, count: count);
      await tester.drag(find.byKey(_list), const Offset(0, -180));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(_header)).height, 80);
    });
  }

  testWidgets('pull to refresh restores the header without consuming scroll', (
    tester,
  ) async {
    var refreshes = 0;
    await mount(tester, onRefresh: () async => refreshes++);
    await tester.drag(find.byKey(_list), const Offset(0, -200));
    await tester.pumpAndSettle();
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(_header)).height, 0);
    await tester.drag(find.byKey(_list), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(refreshes, 1);
    expect(tester.getSize(find.byKey(_header)).height, 80);
  });

  testWidgets('reduced motion and disabling collapse restore full controls', (
    tester,
  ) async {
    await mount(tester, reduceMotion: true);
    await tester.drag(find.byKey(_list), const Offset(0, -180));
    await tester.pump();
    expect(tester.getSize(find.byKey(_header)).height, 0);
    await mount(tester, enabled: false, reduceMotion: true);
    expect(tester.getSize(find.byKey(_header)).height, 80);
    expect(controller.offset, greaterThan(0));
  });
}
