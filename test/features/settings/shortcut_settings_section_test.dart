import '../../support/input_test_app.dart';

import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:bilisail/features/settings/presentation/shortcut_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final key in [
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.keyW,
    LogicalKeyboardKey.tab,
  ]) {
    testWidgets('recording ${key.keyLabel} owns the press until release', (
      tester,
    ) async {
      await tester.pumpWidget(
        InputTestApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ShortcutSettingsSection(
                settings: const ShortcutSettings.defaults(),
                save: (_) async {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.widgetWithText(ListTile, '关闭当前标签页'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('录制组合键'));
      await tester.pumpAndSettle();
      if (key != LogicalKeyboardKey.escape) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      }
      await tester.sendKeyDownEvent(key);
      await tester.pump();
      expect(find.textContaining('释放按键后完成录制'), findsOneWidget);
      await tester.sendKeyRepeatEvent(key);
      await tester.pump();
      expect(find.textContaining('释放按键后完成录制'), findsOneWidget);
      await tester.sendKeyUpEvent(key);
      if (key != LogicalKeyboardKey.escape) {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      }
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        key == LogicalKeyboardKey.escape
            ? 'Escape'
            : key == LogicalKeyboardKey.tab
            ? 'Ctrl+Tab'
            : 'Ctrl+W',
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('failed shortcut save preserves the editing draft', (
    tester,
  ) async {
    await tester.pumpWidget(
      InputTestApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ShortcutSettingsSection(
              settings: const ShortcutSettings.defaults(),
              save: (_) async {
                throw StateError('disk');
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.widgetWithText(ListTile, '关闭当前标签页'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'MouseBack');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'MouseBack',
    );
    expect(find.textContaining('设置保存失败'), findsOneWidget);
  });

  testWidgets('close-tab editor records a modified side key and saves it', (
    tester,
  ) async {
    ShortcutSettings saved = const ShortcutSettings.defaults();
    await tester.pumpWidget(
      InputTestApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ShortcutSettingsSection(
              settings: saved,
              save: (value) async {
                saved = value;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.widgetWithText(ListTile, '关闭当前标签页'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Ctrl+W',
    );
    await tester.tap(find.text('录制组合键'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    final pointer = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kForwardMouseButton,
    );
    await pointer.down(tester.getCenter(find.textContaining('按下键盘按键')));
    await pointer.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Ctrl+MouseForward',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved.actionFor('Ctrl+MouseForward'), ShortcutAction.closeTab);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'shortcut editor detects conflicts and records a custom key without stealing text shortcuts',
    (tester) async {
      ShortcutSettings saved = const ShortcutSettings.defaults();
      await tester.pumpWidget(
        InputTestApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ShortcutSettingsSection(
                settings: saved,
                save: (value) async {
                  saved = value;
                },
              ),
            ),
          ),
        ),
      );
      final action = find.widgetWithText(ListTile, '播放 / 暂停');
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'F');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.textContaining('已用于'), findsOneWidget);
      await tester.tap(find.text('录制组合键'));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'Ctrl+K',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(saved.actionFor('Ctrl+K'), ShortcutAction.playPause);
      expect(tester.takeException(), isNull);
    },
  );
}
