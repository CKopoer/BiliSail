import 'dart:async';
import 'dart:ui' show ViewFocusDirection, ViewFocusEvent, ViewFocusState;

import 'package:bilisail/core/input/input_stroke.dart';
import 'package:bilisail/core/input/shortcut_dispatcher.dart';
import 'package:bilisail/core/presentation/app_input_host.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/detached_window_fake.dart';

void main() {
  for (final viewFocus in [false, true]) {
    testWidgets(
      'lost mouse Up cannot leave a button stuck after ${viewFocus ? 'view blur' : 'lifecycle deactivation'}',
      (tester) async {
        final input = _dispatcher([]);
        addTearDown(input.dispose);
        var presses = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: AppInputHost<String>(
              dispatcher: input,
              routes: InputRouteObserver(),
              child: Scaffold(
                body: Center(
                  child: IconButton(
                    tooltip: 'toggle',
                    onPressed: () => presses++,
                    icon: const Icon(Icons.menu),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final button = find.byTooltip('toggle');
        final interrupted = await tester.startGesture(
          tester.getCenter(button),
          pointer: 73,
          kind: PointerDeviceKind.mouse,
        );
        _active(tester, false, viewFocus: viewFocus);
        await tester.pump();
        _active(tester, true, viewFocus: viewFocus);
        await tester.pumpAndSettle();
        expect(presses, 0);
        await tester.tap(button, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(presses, 1);
        // A late release of the cancelled gesture must not activate the button.
        await interrupted.up();
        await tester.pumpAndSettle();
        expect(presses, 1);
        await tester.tap(button, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(presses, 2);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }),
    );
  }

  testWidgets('reparent resets held keys and restores only the native view', (
    tester,
  ) async {
    final mainCalls = <String>[];
    final playbackCalls = <String>[];
    final mainInput = _dispatcher(mainCalls);
    final playbackInput = _dispatcher(playbackCalls);
    addTearDown(mainInput.dispose);
    addTearDown(playbackInput.dispose);
    final secondary = FakeSecondaryFlutterView(
      tester.view,
      viewId: 100,
      size: const Size(800, 600),
    );
    final key = GlobalKey();
    final routes = InputRouteObserver();
    Widget tree(bool detached) {
      final playback = AppInputHost<String>(
        key: key,
        dispatcher: playbackInput,
        routes: routes,
        child: const SizedBox.expand(),
      );
      return MaterialApp(
        home: AppInputHost<String>(
          dispatcher: mainInput,
          routes: InputRouteObserver(),
          child: ViewAnchor(
            view: detached ? View(view: secondary, child: playback) : null,
            child: detached ? const SizedBox.expand() : playback,
          ),
        ),
      );
    }

    await tester.pumpWidget(tree(false));
    await tester.pumpAndSettle();
    final retained = tester.state(find.byKey(key));
    // A held key in the old view is cancelled on native handoff/reparent.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    mainCalls.clear();
    playbackCalls.clear();
    tester.binding.handleViewFocusChanged(
      const ViewFocusEvent(
        viewId: 100,
        state: ViewFocusState.focused,
        direction: ViewFocusDirection.undefined,
      ),
    );
    await tester.pumpWidget(tree(true));
    await tester.pumpAndSettle();
    expect(tester.state(find.byKey(key)), same(retained));
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    expect(mainCalls, isEmpty);
    expect(playbackCalls, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    expect(mainCalls, isEmpty);
    expect(playbackCalls, ['W']);
    _active(tester, true, viewFocus: true);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    expect(mainCalls, ['W']);
    expect(playbackCalls, ['W']);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('another view cannot dispatch into this window input host', (
    tester,
  ) async {
    final calls = <String>[];
    final input = _dispatcher(calls);
    addTearDown(input.dispose);
    await _mount(tester, input);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    expect(calls, ['W']);
    calls.clear();
    tester.binding.handleViewFocusChanged(
      ViewFocusEvent(
        viewId: tester.view.viewId + 1,
        state: ViewFocusState.focused,
        direction: ViewFocusDirection.undefined,
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    expect(calls, isEmpty);
    _active(tester, true, viewFocus: true);
    tester.binding.handlePointerEvent(
      PointerDownEvent(
        viewId: tester.view.viewId + 1,
        kind: PointerDeviceKind.mouse,
        buttons: kBackMouseButton,
      ),
    );
    tester.binding.handlePointerEvent(
      PointerUpEvent(
        viewId: tester.view.viewId + 1,
        kind: PointerDeviceKind.mouse,
      ),
    );
    expect(calls, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    expect(calls, ['W']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'IME host replacement waits for the previous focus tree to detach',
    (tester) async {
      final calls = <String>[];
      final input = _dispatcher(calls);
      final editing = <bool>[];
      addTearDown(input.dispose);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: TextField(autofocus: true))),
      );
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: AppInputHost<String>(
            dispatcher: input,
            routes: InputRouteObserver(),
            onEditingChanged: (value) async => editing.add(value),
            child: const Scaffold(body: Text('player')),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(editing.last, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'IME follows editable focus and restores when the host is removed',
    (tester) async {
      final editing = <bool>[];
      final calls = <String>[];
      final input = _dispatcher(calls);
      final field = FocusNode();
      final readOnly = FocusNode();
      final surface = FocusNode();
      addTearDown(input.dispose);
      addTearDown(field.dispose);
      addTearDown(readOnly.dispose);
      addTearDown(surface.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: AppInputHost<String>(
            dispatcher: input,
            routes: InputRouteObserver(),
            onEditingChanged: (value) async => editing.add(value),
            child: Scaffold(
              body: Column(
                children: [
                  TextField(focusNode: field),
                  TextField(focusNode: readOnly, readOnly: true),
                  Focus(focusNode: surface, child: const Text('player')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(editing, [false]);
      field.requestFocus();
      await tester.pumpAndSettle();
      expect(editing, [false, true]);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      expect(calls, isEmpty);
      readOnly.requestFocus();
      await tester.pumpAndSettle();
      expect(editing, [false, true, false]);
      surface.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      expect(calls, ['W']);
      expect(editing, [false, true, false]);
      field.requestFocus();
      await tester.pumpAndSettle();
      surface.requestFocus();
      await tester.pumpAndSettle();
      expect(editing, [false, true, false, true, false]);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(editing.last, isTrue);
    },
  );

  testWidgets('dialog editor restores IME and retains punctuation input', (
    tester,
  ) async {
    final editing = <bool>[];
    final calls = <String>[];
    final input = _dispatcher(calls);
    final routes = InputRouteObserver();
    addTearDown(input.dispose);
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [routes],
        builder: (_, child) => AppInputHost<String>(
          dispatcher: input,
          routes: routes,
          onEditingChanged: (value) async => editing.add(value),
          child: child!,
        ),
        home: const Scaffold(body: Text('player')),
      ),
    );
    await tester.pump();
    final context = tester.element(find.text('player'));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: TextField(autofocus: true)),
      ),
    );
    await tester.pumpAndSettle();
    expect(editing.last, isTrue);
    await tester.enterText(find.byType(TextField), '中文；‘’');
    await tester.sendKeyEvent(LogicalKeyboardKey.semicolon);
    await tester.sendKeyEvent(LogicalKeyboardKey.quote);
    expect(calls, isEmpty);
    expect(find.text('中文；‘’'), findsOneWidget);
    Navigator.of(tester.element(find.byType(TextField))).pop();
    await tester.pumpAndSettle();
    expect(editing.last, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  for (final viewFocus in [true, false]) {
    for (final editing in [true, false]) {
      testWidgets(
        'IME resyncs $editing policy after ${viewFocus ? 'view refocus' : 'lifecycle resume'} with unchanged Flutter focus',
        (tester) async {
          final policies = <bool>[];
          final input = _dispatcher([]);
          addTearDown(input.dispose);
          await tester.pumpWidget(
            MaterialApp(
              home: AppInputHost<String>(
                dispatcher: input,
                routes: InputRouteObserver(),
                onEditingChanged: (value) async => policies.add(value),
                child: Scaffold(
                  body: editing
                      ? const TextField(autofocus: true)
                      : const Text('player'),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(policies.last, editing);
          final focus = FocusManager.instance.primaryFocus;
          policies.clear();
          _active(tester, false, viewFocus: viewFocus);
          await tester.pump();
          expect(policies, [false]);
          _active(tester, true, viewFocus: viewFocus);
          await tester.pumpAndSettle();
          expect(FocusManager.instance.primaryFocus, same(focus));
          expect(policies, [false, editing]);
          await tester.pump();
          expect(policies, [false, editing]);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }

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
