import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:bilisail/features/settings/presentation/shortcut_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('close-tab editor records a modified side key and saves it', (
    tester,
  ) async {
    ShortcutSettings saved = const ShortcutSettings.defaults();
    await tester.pumpWidget(
      MaterialApp(
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
        MaterialApp(
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
