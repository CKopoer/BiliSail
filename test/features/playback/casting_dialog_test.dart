import 'package:bilisail/app/theme.dart';
import 'package:bilisail/features/playback/presentation/casting_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/casting_fakes.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'device selection and controls adapt to narrow $brightness dialog',
      (tester) async {
        final h = CastingHarness();
        addTearDown(h.dispose);
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await h.controller.search();
        await tester.pumpWidget(
          MaterialApp(
            theme: brightness == Brightness.dark
                ? BiliTheme.dark()
                : BiliTheme.light(),
            home: Scaffold(body: CastingDialog(controller: h.controller)),
          ),
        );
        expect(find.text('客厅电视 a'), findsOneWidget);
        await tester.tap(find.text('客厅电视 a'));
        await tester.pumpAndSettle();
        expect(find.text('正在投屏'), findsOneWidget);
        expect(h.localPauses, 1);
        await tester.tap(find.text('暂停'));
        await tester.pumpAndSettle();
        expect(find.text('投屏已暂停'), findsOneWidget);
        await tester.tap(find.text('继续'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('停止投屏'));
        await tester.pumpAndSettle();
        expect(find.text('正在投屏'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('short large-text dialog scrolls and exposes invalidation', (
    tester,
  ) async {
    final h = CastingHarness();
    addTearDown(h.dispose);
    tester.view.physicalSize = const Size(320, 280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: CastingDialog(controller: h.controller)),
        ),
      ),
    );
    h.current = false;
    h.source.value++;
    await tester.pump();
    expect(find.text('播放内容或账号已变化，请关闭后重新打开投屏'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
