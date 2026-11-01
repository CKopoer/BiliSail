import 'package:bilisail/app/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_dock_navi/liquid_dock_navi.dart';

void main() {
  testWidgets('dock history and downloads entries stay on the glass bar', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var location = '/';
    late StateSetter setOuterState;
    Widget buildShell() => MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) {
          setOuterState = setState;
          return BiliAppShell(
            location: location,
            child: const SizedBox.expand(),
          );
        },
      ),
    );
    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();
    LiquidDockNavi widget() =>
        tester.widget<LiquidDockNavi>(find.byType(LiquidDockNavi));
    int indexFor(String label) {
      final w = widget();
      return w.items.indexWhere((item) => item.label == label);
    }

    // Home starts selected.
    expect(find.byType(LiquidDockNavi), findsOneWidget);
    expect(indexFor('首页'), 0);

    // Switching to history keeps the glass dock and highlights history.
    setOuterState(() => location = '/history');
    await tester.pumpAndSettle();
    expect(find.byType(LiquidDockNavi), findsOneWidget);
    expect(find.text('历史'), findsOneWidget);
    expect(widget().currentIndex, indexFor('历史'));

    // Switching to downloads keeps the glass dock and highlights downloads.
    setOuterState(() => location = '/downloads');
    await tester.pumpAndSettle();
    expect(find.byType(LiquidDockNavi), findsOneWidget);
    expect(find.text('下载'), findsOneWidget);
    expect(widget().currentIndex, indexFor('下载'));

    // Back to home.
    setOuterState(() => location = '/');
    await tester.pumpAndSettle();
    expect(widget().currentIndex, indexFor('首页'));
  });
}
