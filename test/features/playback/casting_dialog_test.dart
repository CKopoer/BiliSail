import 'package:bilisail/app/theme.dart';
import 'package:bilisail/features/playback/presentation/casting_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/casting_fakes.dart';

void main() {
  testWidgets(
    'experimental mode reconnect remains reachable in a short large-text dialog',
    (tester) async {
      final h = CastingHarness();
      addTearDown(h.dispose);
      h.devices.found = [castDevice('tv', bilibili: true)];
      await h.controller.search();
      await h.controller.connect(h.devices.found.single);
      h.controller.setTelevisionDanmaku(true);
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
      final reconnect = find.text('按当前设置重新投屏');
      await tester.ensureVisible(reconnect);
      await tester.tap(reconnect);
      await tester.pumpAndSettle();
      expect(h.media.receiversResolve, [false, true]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'TV danmaku is opt-in and switching back requires an explicit reconnect',
    (tester) async {
      final h = CastingHarness();
      addTearDown(h.dispose);
      h.devices.found = [castDevice('tv', bilibili: true)];
      await h.controller.search();
      await tester.pumpWidget(
        MaterialApp(
          theme: BiliTheme.light(),
          home: Scaffold(body: CastingDialog(controller: h.controller)),
        ),
      );
      final toggle = find.widgetWithText(SwitchListTile, '电视弹幕（实验）');
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      await tester.ensureVisible(find.text('客厅电视 tv'));
      await tester.tap(find.text('客厅电视 tv'));
      await tester.pumpAndSettle();
      expect(h.media.receiversResolve, [false]);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(h.devices.calls, ['set:tv', 'play:tv']);
      await tester.tap(find.text('按当前设置重新投屏'));
      await tester.pumpAndSettle();
      expect(h.media.receiversResolve, [false, true]);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(h.media.receiversResolve, [false, true]);
      await tester.tap(find.text('按当前设置重新投屏'));
      await tester.pumpAndSettle();
      expect(h.media.receiversResolve, [false, true, false]);
      expect(tester.takeException(), isNull);
    },
  );

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
