import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

String? shortcutKey(KeyEvent event) {
  final key = event.logicalKey;
  final special = <LogicalKeyboardKey, String>{
    LogicalKeyboardKey.space: 'Space',
    LogicalKeyboardKey.enter: 'Enter',
    LogicalKeyboardKey.escape: 'Escape',
    LogicalKeyboardKey.arrowLeft: 'ArrowLeft',
    LogicalKeyboardKey.arrowRight: 'ArrowRight',
    LogicalKeyboardKey.arrowUp: 'ArrowUp',
    LogicalKeyboardKey.arrowDown: 'ArrowDown',
    LogicalKeyboardKey.semicolon: 'Semicolon',
    LogicalKeyboardKey.quote: 'Quote',
    LogicalKeyboardKey.quoteSingle: 'Quote',
    LogicalKeyboardKey.comma: 'Comma',
    LogicalKeyboardKey.period: 'Period',
  };
  final name = special[key] ?? key.keyLabel;
  return _withModifiers(name);
}

String _withModifiers(String name) {
  final keyboard = HardwareKeyboard.instance;
  return [
    if (keyboard.isControlPressed) 'Ctrl',
    if (keyboard.isAltPressed) 'Alt',
    if (keyboard.isShiftPressed) 'Shift',
    if (keyboard.isMetaPressed) 'Meta',
    name,
  ].join('+');
}

String? mouseShortcutKey(PointerEvent event) {
  if (event is! PointerDownEvent || event.kind != PointerDeviceKind.mouse) {
    return null;
  }
  final name = switch (event.buttons) {
    kBackMouseButton => 'MouseBack',
    kForwardMouseButton => 'MouseForward',
    _ => null,
  };
  return name == null ? null : _withModifiers(name);
}

String shortcutLabel(String key) => key
    .replaceAll('MouseBack', '鼠标侧键（后退）')
    .replaceAll('MouseForward', '鼠标侧键（前进）');

final _handledMouseShortcuts = Expando<bool>();

/// Share consumption across hit-test listeners and a player's global route.
/// Transformed copies refer to the same original event; one press runs once.
void dispatchMouseShortcut(PointerEvent event, bool Function(String) handle) {
  final original = event.original ?? event;
  if (_handledMouseShortcuts[original] == true) return;
  final key = mouseShortcutKey(event);
  if (key != null && handle(key)) _handledMouseShortcuts[original] = true;
}

class MouseShortcutListener extends StatelessWidget {
  const MouseShortcutListener({
    super.key,
    required this.onShortcut,
    required this.child,
  });
  final bool Function(String) onShortcut;
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) => dispatchMouseShortcut(event, onShortcut),
    child: child,
  );
}

bool shortcutsBlocked(BuildContext context) {
  final focused = FocusManager.instance.primaryFocus?.context;
  return ModalRoute.of(context)?.isCurrent == false ||
      focused?.widget is EditableText ||
      focused?.findAncestorWidgetOfExactType<EditableText>() != null;
}
