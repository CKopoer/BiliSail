import 'package:bilisail/core/presentation/keyboard_shortcuts.dart';
import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('mouse shortcut adapter ignores ordinary clicks, release and touch', () {
    expect(
      mouseShortcutKey(
        const PointerDownEvent(
          kind: PointerDeviceKind.mouse,
          buttons: kBackMouseButton,
        ),
      ),
      'MouseBack',
    );
    expect(
      mouseShortcutKey(
        const PointerDownEvent(
          kind: PointerDeviceKind.mouse,
          buttons: kForwardMouseButton,
        ),
      ),
      'MouseForward',
    );
    for (final buttons in [
      kPrimaryMouseButton,
      kSecondaryMouseButton,
      kMiddleMouseButton,
      kBackMouseButton | kForwardMouseButton,
    ]) {
      expect(
        mouseShortcutKey(
          PointerDownEvent(kind: PointerDeviceKind.mouse, buttons: buttons),
        ),
        isNull,
      );
    }
    expect(
      mouseShortcutKey(const PointerDownEvent(buttons: kBackMouseButton)),
      isNull,
    );
    expect(
      mouseShortcutKey(
        const PointerUpEvent(
          kind: PointerDeviceKind.mouse,
          buttons: kBackMouseButton,
        ),
      ),
      isNull,
    );
  });
  testWidgets('nested mouse listeners consume a side press only once', (
    tester,
  ) async {
    final handled = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MouseShortcutListener(
          onShortcut: (key) {
            handled.add('outer:$key');
            return true;
          },
          child: Center(
            child: MouseShortcutListener(
              onShortcut: (key) {
                handled.add('inner:$key');
                return true;
              },
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      ),
    );
    final pointer = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kBackMouseButton,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await pointer.down(tester.getCenter(find.byType(SizedBox)));
    await pointer.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(handled, ['inner:Shift+MouseBack']);
  });
  test('both quote logical keys match the same stored speed shortcut', () {
    for (final logical in [
      LogicalKeyboardKey.quote,
      LogicalKeyboardKey.quoteSingle,
    ]) {
      final key = shortcutKey(
        KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.quote,
          logicalKey: logical,
          timeStamp: Duration.zero,
        ),
      );
      expect(key, 'Quote');
      expect(
        const ShortcutSettings.defaults().actionFor(key),
        ShortcutAction.faster,
      );
      expect(
        const ShortcutSettings.defaults()
            .withActionEnabled(ShortcutAction.faster, false)
            .actionFor(key),
        isNull,
      );
    }
  });
}
