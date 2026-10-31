import 'package:bilisail/shared/ui/danmaku_send_style_button.dart';
import 'package:bilisail/shared/ui/danmaku_send_style_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reference palette and legacy choices apply together once', (
    tester,
  ) async {
    final state = await _pump(tester);
    await _open(tester);
    for (final name in [
      '白色',
      '红色',
      '橙色',
      '琥珀色',
      '金黄色',
      '黄色',
      '黄绿色',
      '绿色',
      '青色',
      '靛蓝色',
      '浅蓝色',
      '玫红色',
      '深灰色',
      '灰色',
      '粉色',
      '金色',
      '蓝色',
    ]) {
      expect(find.byTooltip(name), findsOneWidget);
      expect(tester.getSize(find.byTooltip(name)), const Size(44, 44));
    }
    await tester.tap(find.text('底部'));
    await tester.tap(find.byTooltip('红色'));
    expect(state.style.value, (mode: 1, color: 0xffffff));
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(state.style.value, (mode: 4, color: 0xfe0302));
    expect(state.changes, 1);
  });

  for (final dismiss in ['取消', 'Escape', '遮罩']) {
    testWidgets('$dismiss discards edits and reopening keeps the saved color', (
      tester,
    ) async {
      final state = await _pump(tester);
      await _open(tester);
      await tester.tap(find.byTooltip('绿色'));
      if (dismiss == '取消') {
        await tester.tap(find.text('取消'));
      } else if (dismiss == 'Escape') {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      } else {
        await tester.tapAt(const Offset(1, 1));
      }
      await tester.pumpAndSettle();
      expect(state.changes, 0);
      await _open(tester);
      expect(find.text('预览 · 滚动 · #FFFFFF'), findsOneWidget);
    });
  }

  testWidgets(
    'hex input validates, accepts pasted RGB and survives reopening',
    (tester) async {
      final state = await _pump(tester);
      await _open(tester);
      await tester.tap(find.text('自定义颜色'));
      await tester.pumpAndSettle();
      final hex = find.byKey(const ValueKey('danmaku-send-hex'));
      await tester.enterText(hex, '12');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '完成'))
            .onPressed,
        isNull,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.byType(Dialog), findsOneWidget);
      await tester.enterText(hex, '#0012aB');
      await tester.pump();
      expect(find.text('预览 · 滚动 · #0012AB'), findsOneWidget);
      await tester.ensureVisible(find.text('完成'));
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(state.style.value.color, 0x0012ab);
      await _open(tester);
      expect(tester.widget<TextField>(hex).controller!.text, '0012AB');
      final red = tester.widget<Slider>(
        find.byKey(const ValueKey('danmaku-send-R')),
      );
      red.onChanged!(255);
      await tester.pump();
      expect(tester.widget<TextField>(hex).controller!.text, 'FF12AB');
    },
  );

  testWidgets('rapid taps open one modal and disabled button cannot reopen', (
    tester,
  ) async {
    await _pump(tester);
    final trigger = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == '发送弹幕样式',
    );
    final button = tester.widget<IconButton>(trigger);
    button.onPressed!();
    button.onPressed!();
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await _pump(tester, enabled: false);
    expect(tester.widget<IconButton>(trigger).onPressed, isNull);
  });

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  ]) {
    for (final size in [
      const Size(320, 640),
      const Size(640, 280),
      const Size(1280, 800),
    ]) {
      testWidgets('$platform fits $size with large text and keyboard', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = await _pump(tester, platform: platform, textScale: 2);
        await _open(tester);
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(DanmakuSendStylePanel)).width,
          lessThanOrEqualTo(440),
        );
        await tester.ensureVisible(find.text('自定义颜色'));
        await tester.tap(find.text('自定义颜色'));
        await tester.pumpAndSettle();
        if (size.height > 400) {
          tester.view.viewInsets = FakeViewPadding(bottom: 200);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
        }
        final hex = find.byKey(const ValueKey('danmaku-send-hex'));
        await tester.ensureVisible(hex);
        await tester.enterText(hex, '123456');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('完成'));
        await tester.tap(find.text('完成'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(state.style.value.color, 0x123456);
      });
    }
  }
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byTooltip('发送弹幕样式'));
  await tester.pumpAndSettle();
}

final class _State {
  final style = ValueNotifier<({int mode, int color})>((
    mode: 1,
    color: 0xffffff,
  ));
  int changes = 0;
}

Future<_State> _pump(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.windows,
  double textScale = 1,
  bool enabled = true,
}) async {
  final state = _State();
  addTearDown(state.style.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: DanmakuSendStyleButton(
            style: state.style,
            enabled: enabled,
            onChanged: (value) {
              state.changes++;
              state.style.value = value;
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}
