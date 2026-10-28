import 'dart:ui' show ViewFocusDirection, ViewFocusEvent, ViewFocusState;

import 'package:bilisail/app/shell.dart';
import 'package:bilisail/app/workspace_playback_window.dart';
import 'package:bilisail/core/platform/detached_playback_window.dart';
import 'package:bilisail/core/presentation/window_input_focus.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/detached_window_fake.dart';
import '../support/input_test_app.dart';

void main() {
  testWidgets(
    'macOS sidebar remains interactive after Meta+W closes playback',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 850);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final harness = _Harness(tester, 'Meta+W', earlyFocus: true);
      addTearDown(harness.router.dispose);
      await harness.mount();
      final sidebar = find.byKey(const ValueKey('workspace-sidebar-region'));
      final toggle = find.byKey(const ValueKey('workspace-sidebar-toggle'));
      final browser = tester.element(toggle);
      expect(tester.getSize(sidebar).width, 76);

      for (var index = 0; index < 2; index++) {
        if (index != 0) {
          harness.router.go('/video/BV2234567890');
          await tester.pumpAndSettle();
        }
        final window = harness.windows.lastWindow!;
        // Native focus changes can leave the old view without the mouse Up.
        // A retained button must not keep that unfinished tap after returning.
        harness.focus(tester.view.viewId);
        await tester.pumpAndSettle();
        final interrupted = await tester.startGesture(
          tester.getCenter(toggle),
          pointer: 73 + index,
          kind: PointerDeviceKind.mouse,
        );
        harness.focus(window.viewId);
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
        await tester.pumpAndSettle();
        expect(window.disposed, isTrue);
        // The browser must accept the next click, including before Cmd is up.
        await tester.tap(toggle, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(tester.getSize(sidebar).width, 0);
        expect(find.byTooltip('展开侧栏'), findsOneWidget);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.tap(toggle, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(tester.getSize(sidebar).width, 76);
        expect(tester.element(toggle), same(browser));
        await interrupted.cancel();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'native keyWindow snapshot restores Space without an engine focus event',
    (tester) async {
      final harness = _Harness(tester, 'Space', nativeSnapshot: true);
      addTearDown(harness.router.dispose);
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('bilisail/application_window'),
          null,
        );
      });
      await harness.mount();
      final window = harness.windows.lastWindow!;
      expect(WindowInputFocus.instance.source, 'native');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(window.disposed, isTrue);
      expect(harness.activations, 1);
      expect(
        harness.router.routeInformationProvider.value.uri.path,
        '/user/42',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'early native focus enables Meta+W through history, blur and reopening',
    (tester) async {
      final harness = _Harness(tester, 'Meta+W', earlyFocus: true);
      addTearDown(harness.router.dispose);
      await harness.mount();
      final first = harness.windows.lastWindow!;
      harness.router.go('/video/BV2234567890');
      await tester.pumpAndSettle();

      Future<void> closeKey() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
        await tester.pumpAndSettle();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();
      }

      // No post-mount focus event: creation emitted it before View existed.
      await closeKey();
      expect(first.disposed, isFalse);
      expect(find.text('/video/BV1234567890'), findsOneWidget);
      expect(harness.activations, 0);

      tester.binding.handleViewFocusChanged(
        ViewFocusEvent(
          viewId: first.viewId,
          state: ViewFocusState.unfocused,
          direction: ViewFocusDirection.undefined,
        ),
      );
      await closeKey();
      expect(first.disposed, isFalse);
      harness.focus(tester.view.viewId);
      await tester.pumpAndSettle();
      harness.focus(first.viewId);
      // Late main-window blur cannot erase playback focus.
      tester.binding.handleViewFocusChanged(
        ViewFocusEvent(
          viewId: tester.view.viewId,
          state: ViewFocusState.unfocused,
          direction: ViewFocusDirection.undefined,
        ),
      );
      await tester.pumpAndSettle();
      await closeKey();
      expect(first.disposed, isTrue);
      expect(harness.activations, 1);
      // The closing key's tail must not also navigate the browser.
      expect(
        harness.router.routeInformationProvider.value.uri.path,
        '/user/42',
      );

      harness.router.go('/video/BV3234567890');
      await tester.pumpAndSettle();
      final second = harness.windows.lastWindow!;
      expect(second, isNot(same(first)));
      await closeKey();
      expect(second.disposed, isTrue);
      expect(harness.activations, 2);
      expect(
        harness.router.routeInformationProvider.value.uri.path,
        '/user/42',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'switching back during creation keeps the new playback host inactive',
    (tester) async {
      final harness = _Harness(
        tester,
        'Meta+W',
        earlyFocus: true,
        returnFocusDuringCreation: true,
      );
      addTearDown(harness.router.dispose);
      await harness.mount();
      final window = harness.windows.lastWindow!;
      harness.pointer(
        PointerDownEvent(
          viewId: window.viewId,
          kind: PointerDeviceKind.mouse,
          buttons: kBackMouseButton,
        ),
      );
      harness.pointer(
        PointerUpEvent(viewId: window.viewId, kind: PointerDeviceKind.mouse),
      );
      await tester.pumpAndSettle();
      expect(window.disposed, isFalse);
      expect(harness.activations, 0);
      harness.focus(window.viewId);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(window.disposed, isTrue);
      expect(harness.activations, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final (key, button) in [
    ('MouseBack', kBackMouseButton),
    ('MouseForward', kForwardMouseButton),
  ]) {
    testWidgets(
      '$key closes playback without returning the browser on window handoff',
      (tester) async {
        final harness = _Harness(tester, key);
        addTearDown(harness.router.dispose);
        await harness.mount();
        final window = harness.windows.lastWindow!;

        harness.buttons = button;
        harness.pointer(
          PointerDownEvent(
            viewId: window.viewId,
            pointer: 1,
            kind: PointerDeviceKind.mouse,
            buttons: button,
          ),
        );
        await tester.pumpAndSettle();
        harness.buttons = 0;
        harness.pointer(
          PointerUpEvent(
            viewId: window.disposed ? tester.view.viewId : window.viewId,
            pointer: window.disposed ? 2 : 1,
            kind: PointerDeviceKind.mouse,
          ),
        );
        await tester.pumpAndSettle();

        expect(window.disposed, isTrue);
        expect(harness.activations, 1);
        expect(
          harness.router.routeInformationProvider.value.uri.path,
          '/user/42',
        );
        expect(find.text('/user/42'), findsOneWidget);

        // A separate click in the browser still performs its own Back.
        harness.pointer(
          PointerDownEvent(
            viewId: tester.view.viewId,
            pointer: 3,
            kind: PointerDeviceKind.mouse,
            buttons: button,
          ),
        );
        harness.pointer(
          PointerUpEvent(
            viewId: tester.view.viewId,
            pointer: 3,
            kind: PointerDeviceKind.mouse,
          ),
        );
        await tester.pumpAndSettle();
        expect(harness.router.routeInformationProvider.value.uri.path, '/');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets('playback side-button cancellation does not navigate', (
    tester,
  ) async {
    final harness = _Harness(tester, 'MouseBack');
    addTearDown(harness.router.dispose);
    await harness.mount();
    final window = harness.windows.lastWindow!;
    harness.pointer(
      PointerDownEvent(
        viewId: window.viewId,
        pointer: 1,
        kind: PointerDeviceKind.mouse,
        buttons: kBackMouseButton,
      ),
    );
    await tester.pumpAndSettle();
    expect(window.disposed, isFalse);
    harness.pointer(
      PointerCancelEvent(
        viewId: window.viewId,
        pointer: 1,
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();
    expect(window.disposed, isFalse);
    expect(harness.activations, 0);

    // Keyboard close keeps its press-time behavior.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await tester.pumpAndSettle();
    expect(window.disposed, isTrue);
    expect(harness.router.routeInformationProvider.value.uri.path, '/user/42');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('playback side-button release after refocus does not navigate', (
    tester,
  ) async {
    final harness = _Harness(tester, 'MouseBack');
    addTearDown(harness.router.dispose);
    await harness.mount();
    final window = harness.windows.lastWindow!;
    harness.pointer(
      PointerDownEvent(
        viewId: window.viewId,
        pointer: 1,
        kind: PointerDeviceKind.mouse,
        buttons: kBackMouseButton,
      ),
    );
    harness.focus(tester.view.viewId);
    await tester.pumpAndSettle();
    harness.focus(window.viewId);
    await tester.pumpAndSettle();
    harness.pointer(
      PointerUpEvent(
        viewId: window.viewId,
        pointer: 1,
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();
    expect(window.disposed, isFalse);
    expect(harness.activations, 0);
    expect(find.text('/user/42'), findsOneWidget);
    expect(find.text('/video/BV1234567890'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}

class _Harness {
  _Harness(
    this.tester,
    String key, {
    this.earlyFocus = false,
    this.nativeSnapshot = false,
    this.returnFocusDuringCreation = false,
  }) : windows = FakeDetachedWindowFactory(tester.view),
       shortcuts = const ShortcutSettings.defaults().withKeys(
         ShortcutAction.closeTab,
         ['Ctrl+W', if (earlyFocus) 'MouseBack', key],
       );

  final WidgetTester tester;
  final FakeDetachedWindowFactory windows;
  final ShortcutSettings shortcuts;
  final bool earlyFocus;
  final bool nativeSnapshot;
  final bool returnFocusDuringCreation;
  int buttons = 0;

  DetachedPlaybackWindow createWindow({
    required String title,
    required VoidCallback onCloseRequested,
  }) {
    final window = windows.call(
      title: title,
      onCloseRequested: onCloseRequested,
    );
    if (nativeSnapshot) {
      // Match createRegularWindow: the old delegate reports blur, but the new
      // delegate is not installed until after its window has become key.
      tester.binding.handleViewFocusChanged(
        ViewFocusEvent(
          viewId: tester.view.viewId,
          state: ViewFocusState.unfocused,
          direction: ViewFocusDirection.undefined,
        ),
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('bilisail/application_window'),
        (_) async => {
          'viewId': window.viewId,
          'revision': windows.creationCount,
          'active': true,
        },
      );
      window.onPrepare = WindowInputFocus.instance.synchronizeNativeFocus;
    }
    if (earlyFocus) {
      focus(window.viewId);
      if (returnFocusDuringCreation) focus(tester.view.viewId);
    }
    return window;
  }

  int activations = 0;

  void pointer(PointerEvent event) => tester.binding.handlePointerEvent(event);

  void focus(int viewId) => tester.binding.handleViewFocusChanged(
    ViewFocusEvent(
      viewId: viewId,
      state: ViewFocusState.focused,
      direction: ViewFocusDirection.undefined,
    ),
  );

  void activateBrowser() {
    activations++;
    focus(tester.view.viewId);
    // Model the pinned Windows embedder: entering a view while a button is
    // held starts a Down in that view. Defer delivery until the current event
    // has finished, as native window messages do.
    final pressed = buttons;
    Future<void>.microtask(() {
      if (pressed != 0) {
        pointer(
          PointerCancelEvent(
            viewId: windows.lastWindow!.viewId,
            pointer: 1,
            kind: PointerDeviceKind.mouse,
          ),
        );
      }
      pointer(
        PointerRemovedEvent(
          viewId: windows.lastWindow!.viewId,
          kind: PointerDeviceKind.mouse,
        ),
      );
      pointer(
        PointerAddedEvent(
          viewId: tester.view.viewId,
          kind: PointerDeviceKind.mouse,
        ),
      );
      if (pressed != 0) {
        pointer(
          PointerDownEvent(
            viewId: tester.view.viewId,
            pointer: 2,
            kind: PointerDeviceKind.mouse,
            buttons: pressed,
          ),
        );
      }
    });
  }

  late final router = GoRouter(
    routes: [
      ShellRoute(
        observers: [],
        builder: (context, state, child) => BiliAppShell(
          location: state.uri.toString(),
          navigationMode: WorkspaceNavigationMode.dualTabs,
          shortcuts: shortcuts,
          onActivateBrowser: activateBrowser,
          pageBuilder: (_, tab) => Center(child: Text(tab.location.path)),
          playbackWindowBuilder:
              (
                context, {
                required child,
                required playback,
                required keepPlaybackMounted,
                required activationToken,
                required onClose,
                required onBack,
                required onHome,
                required onError,
              }) => DesktopPlaybackWindow(
                keepPlaybackMounted: keepPlaybackMounted,
                windowFactory: createWindow,
                activationToken: activationToken,
                onCloseRequested: onClose,
                onError: onError,
                playback: playback == null
                    ? null
                    : WorkspacePlaybackWindow(
                        theme: ThemeData(),
                        shortcuts: shortcuts,
                        onBack: onBack,
                        onHome: onHome,
                        onClose: onClose,
                        onActivateBrowser: activateBrowser,
                        child: playback,
                      ),
                child: child,
              ),
          child: child,
        ),
        routes: [
          for (final path in ['/', '/user/:id', '/video/:id'])
            GoRoute(path: path, builder: (_, _) => const SizedBox()),
        ],
      ),
    ],
  );

  Future<void> mount() async {
    await tester.pumpWidget(
      InputTestApp.router(routerConfig: router, shortcuts: shortcuts),
    );
    await tester.pumpAndSettle();
    router.go('/user/42');
    await tester.pumpAndSettle();
    router.go('/video/BV1234567890');
    await tester.pumpAndSettle();
    if (!earlyFocus && !nativeSnapshot) focus(windows.lastWindow!.viewId);
    await tester.pumpAndSettle();
  }
}
