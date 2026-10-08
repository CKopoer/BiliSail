import 'dart:ui' show ViewFocusDirection, ViewFocusEvent, ViewFocusState;

import 'package:bilisail/core/input/input_stroke.dart';
import 'package:bilisail/core/input/shortcut_dispatcher.dart';
import 'package:bilisail/core/presentation/app_input_host.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final viewFocus in [true, false]) {
    testWidgets(
      'Windows ${viewFocus ? 'view blur' : 'lifecycle deactivation'} recovers mouse and keyboard with stale Alt',
      (tester) async {
        final calls = <String>[];
        final input = _dispatcher(calls);
        addTearDown(input.dispose);
        await _mount(tester, input);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await _back(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
        expect(calls, ['Alt+MouseBack', 'Alt+W']);

        _active(tester, false, viewFocus: viewFocus);
        await tester.pump();
        // An inactive modifier event must not repopulate the app's state.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        _active(tester, true, viewFocus: viewFocus);
        await tester.pump();
        expect(HardwareKeyboard.instance.isAltPressed, isTrue);
        expect(HardwareKeyboard.instance.isControlPressed, isTrue);
        await _back(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
        expect(calls, ['Alt+MouseBack', 'Alt+W', 'MouseBack', 'W']);

        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altRight);
        await _back(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
        expect(calls.sublist(4), ['Alt+MouseBack', 'Alt+W']);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altRight);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'Windows drops lost keyboard releases and ignores old repeats after refocus',
    (tester) async {
      final calls = <String>[];
      final input = _dispatcher(calls);
      addTearDown(input.dispose);
      await _mount(tester, input);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      expect(calls, ['W']);
      _active(tester, false, viewFocus: true);
      await tester.pump();
      _active(tester, true, viewFocus: true);
      await tester.pump();
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyW);
      expect(calls, ['W']);
      // Model engine recovery after a release outside the window without
      // delivering a KeyUp to AppInputHost. Its early handler stays registered.
      HardwareKeyboard.instance.clearState();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      expect(calls, ['W', 'W']);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'lifecycle resume cannot reactivate input while the view is unfocused',
    (tester) async {
      final calls = <String>[];
      final input = _dispatcher(calls);
      addTearDown(input.dispose);
      await _mount(tester, input);
      _active(tester, false, viewFocus: true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await _back(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      expect(calls, isEmpty);
      _active(tester, true, viewFocus: true);
      await tester.pump();
      await _back(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      expect(calls, ['MouseBack', 'W']);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

ShortcutDispatcher<String> _dispatcher(List<String> calls) {
  final input = ShortcutDispatcher<String>(
    scopeFor: (_) => CommandScope.workspace,
    repeats: (_) => true,
    editorException: (_, _) => false,
  );
  const chords = ['MouseBack', 'Alt+MouseBack', 'W', 'Alt+W'];
  input.replaceBindings({
    for (final chord in chords) ShortcutChord.parse(chord)!: chord,
  });
  input.register(
    owner: 'test',
    scope: CommandScope.workspace,
    active: () => true,
    commands: {
      for (final chord in chords)
        chord: (stroke) {
          if (stroke.phase != InputPhase.up) calls.add(chord);
          return CommandOutcome.completed;
        },
    },
  );
  return input;
}

Future<void> _mount(
  WidgetTester tester,
  ShortcutDispatcher<String> input,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AppInputHost<String>(
        dispatcher: input,
        routes: InputRouteObserver(),
        child: const SizedBox.expand(),
      ),
    ),
  );
  await tester.pump();
}

void _active(WidgetTester tester, bool active, {required bool viewFocus}) {
  if (viewFocus) {
    tester.binding.handleViewFocusChanged(
      ViewFocusEvent(
        viewId: tester.view.viewId,
        state: active ? ViewFocusState.focused : ViewFocusState.unfocused,
        direction: ViewFocusDirection.undefined,
      ),
    );
  } else {
    tester.binding.handleAppLifecycleStateChanged(
      active ? AppLifecycleState.resumed : AppLifecycleState.inactive,
    );
  }
}

Future<void> _back(WidgetTester tester) async {
  final mouse = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: kBackMouseButton,
  );
  await mouse.down(Offset.zero);
  await mouse.up();
  await mouse.removePointer();
}
