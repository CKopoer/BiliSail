import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../input/input_stroke.dart';
import '../input/shortcut_dispatcher.dart';
import 'input_scope.dart';

final class InputNormalizer {
  InputNormalizer({TargetPlatform? platform})
    : _trackModifiers =
          (platform ?? defaultTargetPlatform) == TargetPlatform.windows;

  final _clock = Stopwatch()..start();
  int _sequence = 0;
  final _buttons = <(int, int), int>{};
  // TODO(flutter/flutter#177822, flutter/flutter#99330): Remove the Windows
  // modifier bookkeeping once the pinned SDK synchronizes modifiers on focus
  // changes, including mouse refocus after Alt+Tab. Do not seed from its stale
  // HardwareKeyboard cache after blur.
  final bool _trackModifiers;
  final _modifierKeys =
      <PhysicalKeyboardKey, ({LogicalKeyboardKey key, int mask})>{};
  int get modifiers {
    if (_trackModifiers) {
      return _modifierKeys.values.fold(
        0,
        (mask, modifier) => mask | modifier.mask,
      );
    }
    final keyboard = HardwareKeyboard.instance;
    return (keyboard.isControlPressed ? ShortcutChord.control : 0) |
        (keyboard.isAltPressed ? ShortcutChord.alt : 0) |
        (keyboard.isShiftPressed ? ShortcutChord.shift : 0) |
        (keyboard.isMetaPressed ? ShortcutChord.meta : 0);
  }

  bool isKeyPressed(LogicalKeyboardKey key) {
    if (_trackModifiers && _modifierMask(key) != 0) {
      return _modifierKeys.values.any((modifier) => modifier.key == key);
    }
    return HardwareKeyboard.instance.isLogicalKeyPressed(key);
  }

  static int _modifierMask(LogicalKeyboardKey key) => switch (key) {
    LogicalKeyboardKey.controlLeft ||
    LogicalKeyboardKey.controlRight => ShortcutChord.control,
    LogicalKeyboardKey.altLeft ||
    LogicalKeyboardKey.altRight => ShortcutChord.alt,
    LogicalKeyboardKey.shiftLeft ||
    LogicalKeyboardKey.shiftRight => ShortcutChord.shift,
    LogicalKeyboardKey.metaLeft ||
    LogicalKeyboardKey.metaRight => ShortcutChord.meta,
    _ => 0,
  };

  static final _keys = <LogicalKeyboardKey, String>{
    LogicalKeyboardKey.space: 'Space',
    LogicalKeyboardKey.enter: 'Enter',
    LogicalKeyboardKey.escape: 'Escape',
    LogicalKeyboardKey.tab: 'Tab',
    LogicalKeyboardKey.arrowLeft: 'ArrowLeft',
    LogicalKeyboardKey.arrowRight: 'ArrowRight',
    LogicalKeyboardKey.arrowUp: 'ArrowUp',
    LogicalKeyboardKey.arrowDown: 'ArrowDown',
    LogicalKeyboardKey.semicolon: 'Semicolon',
    LogicalKeyboardKey.quote: 'Quote',
    LogicalKeyboardKey.quoteSingle: 'Quote',
    LogicalKeyboardKey.comma: 'Comma',
    LogicalKeyboardKey.period: 'Period',
    LogicalKeyboardKey.pageUp: 'PageUp',
    LogicalKeyboardKey.pageDown: 'PageDown',
    LogicalKeyboardKey.equal: 'Equal',
    LogicalKeyboardKey.minus: 'Minus',
    LogicalKeyboardKey.numpadAdd: 'NumpadAdd',
    LogicalKeyboardKey.numpadSubtract: 'NumpadSubtract',
    for (var i = 0; i < 26; i++)
      LogicalKeyboardKey(0x61 + i): String.fromCharCode(65 + i),
    for (var i = 0; i < 10; i++) LogicalKeyboardKey(0x30 + i): '$i',
    LogicalKeyboardKey.f1: 'F1',
    LogicalKeyboardKey.f2: 'F2',
    LogicalKeyboardKey.f3: 'F3',
    LogicalKeyboardKey.f4: 'F4',
    LogicalKeyboardKey.f5: 'F5',
    LogicalKeyboardKey.f6: 'F6',
    LogicalKeyboardKey.f7: 'F7',
    LogicalKeyboardKey.f8: 'F8',
    LogicalKeyboardKey.f9: 'F9',
    LogicalKeyboardKey.f10: 'F10',
    LogicalKeyboardKey.f11: 'F11',
    LogicalKeyboardKey.f12: 'F12',
  };
  InputStroke key(KeyEvent event, {int? viewId}) {
    if (_trackModifiers) {
      if (event is KeyUpEvent) {
        _modifierKeys.remove(event.physicalKey);
      } else {
        final modifier = _modifierMask(event.logicalKey);
        // Synthesized modifier events reconcile state without executing actions.
        if (modifier != 0) {
          _modifierKeys[event.physicalKey] = (
            key: event.logicalKey,
            mask: modifier,
          );
        }
      }
    }
    var name = _keys[event.logicalKey];
    var fallback = false;
    // Only unknown/non-layout logical identities may use US punctuation positions.
    if (name == null && event.logicalKey.keyId > 0x10ffff) {
      name = switch (event.physicalKey) {
        PhysicalKeyboardKey.semicolon => 'Semicolon',
        PhysicalKeyboardKey.quote => 'Quote',
        _ => null,
      };
      fallback = name != null;
    }
    return InputStroke(
      identity: 'key:${event.physicalKey.usbHidUsage}',
      device: InputDevice.keyboard,
      sequence: ++_sequence,
      elapsedMicros: _clock.elapsedMicroseconds,
      logicalKeyId: event.logicalKey.keyId,
      physicalKeyId: event.physicalKey.usbHidUsage,
      viewId: viewId,
      phase: event is KeyUpEvent
          ? InputPhase.up
          : event is KeyRepeatEvent
          ? InputPhase.repeat
          : InputPhase.down,
      chord: name == null ? null : ShortcutChord(name, modifiers: modifiers),
      synthesized: event.synthesized,
      physicalFallback: fallback,
    );
  }

  void resetKeyboard() => _modifierKeys.clear();
  void resetMouse() => _buttons.clear();
  List<InputStroke> pointer(PointerEvent event) {
    if (event.kind != PointerDeviceKind.mouse || event is PointerSignalEvent) {
      return [];
    }
    final device = (event.viewId, event.device);
    final previous = _buttons[device];
    final cancelled =
        event is PointerCancelEvent || event is PointerRemovedEvent;
    final current = cancelled ? 0 : event.buttons;
    if (_buttons.length >= 32 && !_buttons.containsKey(device)) return [];
    _buttons[device] = current;
    if (previous == null && event is! PointerDownEvent) return [];
    final pressed = current & ~(previous ?? 0);
    final released = (previous ?? 0) & ~current;
    final ambiguous =
        pressed & (kBackMouseButton | kForwardMouseButton) ==
        (kBackMouseButton | kForwardMouseButton);
    final strokes = <InputStroke>[];
    for (final (mask, name) in [
      (kBackMouseButton, 'MouseBack'),
      (kForwardMouseButton, 'MouseForward'),
    ]) {
      if (released & mask != 0 || (!ambiguous && pressed & mask != 0)) {
        strokes.add(
          InputStroke(
            identity: 'mouse:${device.$1}:${device.$2}:$mask',
            device: InputDevice.mouse,
            sequence: ++_sequence,
            elapsedMicros: _clock.elapsedMicroseconds,
            viewId: event.viewId,
            buttons: event.buttons,
            phase: released & mask != 0
                ? (cancelled ? InputPhase.cancel : InputPhase.up)
                : InputPhase.down,
            chord: ShortcutChord(name, modifiers: modifiers),
          ),
        );
      }
    }
    if (event is PointerRemovedEvent) _buttons.remove(device);
    return strokes;
  }
}

/// Root and nested Navigators share this route ledger, including focusless popups.
final class _InputRoutes {
  final routes = <Route<Object?>>[];
  final presentationRoutes = <Route<Object?>>{};
  VoidCallback? onChanged;
}

class InputRouteObserver extends NavigatorObserver {
  InputRouteObserver() : _ledger = _InputRoutes();
  InputRouteObserver._(this._ledger);
  final _InputRoutes _ledger;
  InputRouteObserver child() => InputRouteObserver._(_ledger);
  List<Route<Object?>> get routes => _ledger.routes;
  Set<Route<Object?>> get presentationRoutes => _ledger.presentationRoutes;
  set onChanged(VoidCallback? callback) => _ledger.onChanged = callback;
  Route<Object?>? get top => routes.lastOrNull;
  bool get modal => top is PopupRoute && !presentationRoutes.contains(top);
  void presentation(Route<Object?> route) => presentationRoutes.add(route);
  void _changed() => _ledger.onChanged?.call();
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
    presentationRoutes.remove(route);
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
    presentationRoutes.remove(route);
    _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : routes.indexOf(oldRoute);
    if (index >= 0) {
      routes.removeAt(index);
      if (newRoute != null) routes.insert(index, newRoute);
    }
    _changed();
  }
}

class AppInputHost<C> extends StatefulWidget {
  const AppInputHost({
    super.key,
    required this.dispatcher,
    required this.routes,
    required this.child,
  });
  final ShortcutDispatcher<C> dispatcher;
  final InputRouteObserver routes;
  final Widget child;
  @override
  State<AppInputHost<C>> createState() => _AppInputHostState<C>();
}

class _AppInputHostState<C> extends State<AppInputHost<C>>
    with WidgetsBindingObserver {
  final _normalizer = InputNormalizer();
  bool _lifecycleActive = true;
  bool _viewFocused = true;
  bool get _active => _lifecycleActive && _viewFocused;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addEarlyKeyEventHandler(_key);
    FocusManager.instance.addListener(_cancel);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_pointer);
    widget.routes.onChanged = _routesChanged;
  }

  void _cancel() => widget.dispatcher.cancel(keepWorkspace: true);
  void _routesChanged() =>
      widget.dispatcher.cancel(keepWorkspace: !widget.routes.modal);

  void _resetInput() {
    widget.dispatcher.cancel();
    _normalizer.resetKeyboard();
    _normalizer.resetMouse();
    // Releases may occur in another window. A cancelled keyboard press must not
    // swallow the next real Down as the tail of the old sequence.
    widget.dispatcher.resetDevice(InputDevice.keyboard);
    widget.dispatcher.resetDevice(InputDevice.mouse);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleActive = state == AppLifecycleState.resumed;
    if (!_active) _resetInput();
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    _viewFocused = event.state == ViewFocusState.focused;
    if (!_active) _resetInput();
  }

  ShortcutContext _context() {
    final focus = FocusManager.instance.primaryFocus?.context;
    final editor = focus?.widget is EditableText
        ? focus?.widget as EditableText
        : focus?.findAncestorWidgetOfExactType<EditableText>();
    final scope = focus == null ? null : InputProtection.maybeOf(focus);
    return ShortcutContext(
      activeWindow: _active,
      editing: scope?.editing == true || (editor != null && !editor.readOnly),
      reserveActivation:
          scope?.reserveActivation == true ||
          (focus != null &&
              !identical(
                FocusManager.instance.primaryFocus,
                scope?.activationFocus,
              ) &&
              (focus.findAncestorWidgetOfExactType<FocusableActionDetector>() !=
                      null ||
                  focus.findAncestorWidgetOfExactType<InkWell>() != null)),
      modal: widget.routes.modal || widget.dispatcher.barriers != 0,
      topRoute: widget.routes.top,
    );
  }

  KeyEventResult _key(KeyEvent event) {
    if (!_active) return KeyEventResult.ignored;
    return widget.dispatcher
            .dispatch(
              _normalizer.key(event, viewId: View.maybeOf(context)?.viewId),
              _context(),
            )
            .claimed
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  void _pointer(PointerEvent event) {
    if (!_active) return;
    for (final stroke in _normalizer.pointer(event)) {
      widget.dispatcher.dispatch(stroke, _context());
    }
  }

  @override
  void dispose() {
    _cancel();
    widget.routes.onChanged = null;
    FocusManager.instance.removeEarlyKeyEventHandler(_key);
    FocusManager.instance.removeListener(_cancel);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointer);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InputModifierScope(
    isPressed: _normalizer.isKeyPressed,
    child: InputScope<C>(
      dispatcher: widget.dispatcher,
      routes: widget.routes,
      child: FocusScope(autofocus: true, child: widget.child),
    ),
  );
}
