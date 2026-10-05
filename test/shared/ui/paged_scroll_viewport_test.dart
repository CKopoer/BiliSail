import 'package:bili_lite/shared/ui/paged_scroll_viewport.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'checks once after layout and only downward scrolls check again',
    (tester) async {
      var pageCalls = 0;
      await tester.pumpWidget(
        _app(
          canLoadMore: true,
          contentHeight: 1200,
          onLoadMore: () async => pageCalls++,
        ),
      );
      await tester.pumpAndSettle();
      expect(pageCalls, 1);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(pageCalls, 1);
      await _wheel(tester, 100);
      await tester.pumpAndSettle();
      expect(pageCalls, 2);
      await _wheel(tester, -50);
      await tester.pumpAndSettle();
      expect(pageCalls, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('square actions support keyboard activation in a narrow view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var refreshCalls = 0;
    await tester.pumpWidget(
      _app(contentHeight: 1400, onRefresh: () async => refreshCalls++),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(refreshCalls, 1);
    await _wheel(tester, 200);
    await tester.pumpAndSettle();
    expect(find.byTooltip('回到顶部'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byTooltip('回到顶部'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _app({
  bool canLoadMore = false,
  required double contentHeight,
  Future<void> Function()? onLoadMore,
  Future<void> Function()? onRefresh,
}) => MaterialApp(
  home: Scaffold(
    body: PagedScrollViewport(
      active: true,
      canLoadMore: canLoadMore,
      contentVersion: 1,
      onLoadMore: onLoadMore ?? () async {},
      onRefresh: onRefresh,
      builder: (controller) => ListView(
        controller: controller,
        children: [SizedBox(height: contentHeight)],
      ),
    ),
  ),
);

Future<void> _wheel(WidgetTester tester, double delta) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: tester.getCenter(find.byType(ListView)),
      scrollDelta: Offset(0, delta),
    ),
  );
  await tester.pump();
}
