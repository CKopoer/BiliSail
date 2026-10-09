import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/shared/ui/paging_tab_strip.dart';
import 'package:bilisail/shared/ui/playback_info_tabs.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pager = find.byKey(const ValueKey('playback-test-pager'));
  late StateSetter update;
  var value = 0;
  var active = true;
  var changes = 0;

  Future<void> mount(
    WidgetTester tester, {
    bool disableAnimations = false,
  }) async {
    value = 0;
    active = true;
    changes = 0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return WorkspaceActivity(
                  active: active,
                  child: PlaybackInfoTabs(
                    labels: const [Text('简介'), Text('评论')],
                    value: value,
                    onChanged: (tab) => setState(() {
                      value = tab;
                      changes++;
                    }),
                    viewKey: const ValueKey('playback-test-pager'),
                    pageBuilder: (_, tab, _) => ListView.builder(
                      key: ValueKey('playback-test-list-$tab'),
                      itemCount: 40,
                      itemBuilder: (_, index) =>
                          SizedBox(height: 60, child: Text('$tab/$index')),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('short, cancelled and mouse drags keep playback info selection', (
    tester,
  ) async {
    await mount(tester);
    final short = await tester.startGesture(tester.getCenter(pager));
    await short.moveBy(const Offset(-60, 0));
    await tester.pump(const Duration(milliseconds: 400));
    await short.up();
    await tester.pumpAndSettle();
    expect(value, 0);
    final cancelled = await tester.startGesture(tester.getCenter(pager));
    await cancelled.moveBy(const Offset(-260, 0));
    await tester.pump();
    await cancelled.cancel();
    await tester.pumpAndSettle();
    expect(value, 0);
    await tester.drag(
      pager,
      const Offset(-260, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(value, 0);
    expect(changes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hiding info during a drag cancels its pending selection', (
    tester,
  ) async {
    await mount(tester);
    final drag = await tester.startGesture(tester.getCenter(pager));
    await drag.moveBy(const Offset(-260, 0));
    await tester.pump();
    update(() => active = false);
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(value, 0);
    expect(changes, 0);
    update(() => active = true);
    await tester.pumpAndSettle();
    await tester.drag(pager, const Offset(-260, 0));
    await tester.pumpAndSettle();
    expect(value, 1);
    expect(changes, 1);
    expect(tester.takeException(), isNull);
  });

  for (final reduced in [false, true]) {
    testWidgets('playback tab taps honor reduced motion: $reduced', (
      tester,
    ) async {
      await mount(tester, disableAnimations: reduced);
      await tester.tap(find.text('评论'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      final strip = tester.widget<PagingTabStrip<int>>(
        find.byType(PagingTabStrip<int>),
      );
      expect(value, 1);
      expect(strip.progress?.value, reduced ? 1 : inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(find.text('1/0').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
