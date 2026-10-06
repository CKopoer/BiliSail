import 'package:bilisail/app/shell.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:bilisail/app/workspace_tabs.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/search/application/search_controller.dart'
    hide SearchController;
import 'package:bilisail/features/search/domain/search_repository.dart';
import 'package:bilisail/features/search/domain/search_result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets(
    'single page back restores state, releases popped pages and handles system back',
    (tester) async {
      final disposed = <String>[];
      final router = _router(
        (context, tab) => _CounterPage(tab: tab, onDispose: disposed.add),
        navigationMode: WorkspaceNavigationMode.singlePage,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('single-page-header')), findsOneWidget);
      expect(find.byKey(const ValueKey('new-workspace-tab')), findsNothing);
      await tester.tap(find.text('count 0'));
      router.go('/search?q=test');
      await tester.pumpAndSettle();
      await tester.tap(find.text('count 0'));
      await tester.pump();
      await tester.tap(find.text('count 1'));
      router.go('/video/BV1234567890');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-back')));
      await tester.pumpAndSettle();
      expect(find.text('count 2'), findsOneWidget);
      expect(disposed, ['tab-2']);
      expect(router.routeInformationProvider.value.uri.path, '/search');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('count 1'), findsOneWidget);
      expect(disposed, ['tab-2', 'tab-1']);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('workspace-back')))
            .onPressed,
        isNull,
      );
      expect(await router.routerDelegate.popRoute(), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a single-page deep link can return home and modal back stays in the page',
    (tester) async {
      final router = _router(
        (_, tab) => Text('page ${tab.id}'),
        navigationMode: WorkspaceNavigationMode.singlePage,
        initialLocation: '/video/BV1234567890',
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      final context = tester.element(find.text('page tab-1'));
      final dialog = showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('modal')),
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await dialog;
      expect(find.text('page tab-1'), findsOneWidget);
      await _shortcut(tester, LogicalKeyboardKey.keyT);
      await _shortcut(tester, LogicalKeyboardKey.tab);
      expect(find.text('page tab-1'), findsOneWidget);
      await _shortcut(tester, LogicalKeyboardKey.keyW);
      expect(find.text('page home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.android,
  ]) {
    testWidgets('$platform default mode is stable across window resizing', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 850);
      final singlePage = platform == TargetPlatform.android;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final disposed = <String>[];
      final router = _router(
        (context, tab) => _CounterPage(tab: tab, onDispose: disposed.add),
        navigationMode: null,
        customCaption: true,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.text('count 0'));
      router.go('/search?q=test');
      await tester.pumpAndSettle();
      await tester.tap(find.text('count 0'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('single-page-header')),
        singlePage ? findsOneWidget : findsNothing,
      );
      tester.view.physicalSize = const Size(1280, 850);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('single-page-header')),
        singlePage ? findsOneWidget : findsNothing,
      );
      expect(find.text('count 1'), findsOneWidget);
      tester.view.physicalSize = const Size(420, 850);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('single-page-header')),
        singlePage ? findsOneWidget : findsNothing,
      );
      expect(find.text('count 1'), findsOneWidget);
      expect(disposed, isEmpty);
      await tester.tap(find.byKey(const ValueKey('workspace-back')));
      await tester.pumpAndSettle();
      expect(find.text('count 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(platform));
  }

  testWidgets(
    'multiple tabs can go back through visits without closing pages',
    (tester) async {
      final router = _router((_, tab) => Text('page ${tab.id}'));
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      router.go('/search?q=test');
      await tester.pumpAndSettle();
      router.go('/video/BV1234567890');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-tab-home')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-back')));
      await tester.pumpAndSettle();
      expect(find.text('page tab-2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('workspace-back')));
      await tester.pumpAndSettle();
      expect(find.text('page tab-1'), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-tab-tab-2')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [420.0, 1000.0]) {
    testWidgets(
      'home channel strip scrolls to its final tab using a mouse wheel at width $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 850);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final router = _router(
          (_, tab) =>
              Text('channel ${tab.location.queryParameters['channel']}'),
          navigationMode: WorkspaceNavigationMode.multipleTabs,
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MaterialApp.router(
            theme: ThemeData(platform: TargetPlatform.windows),
            routerConfig: router,
          ),
        );
        await tester.pumpAndSettle();
        final strip = find.byKey(const ValueKey('home-channel-strip'));
        final scrollable = tester.state<ScrollableState>(
          find.descendant(of: strip, matching: find.byType(Scrollable)),
        );
        expect(scrollable.position.maxScrollExtent, greaterThan(0));
        await tester.sendEventToBinding(
          PointerScrollEvent(
            kind: PointerDeviceKind.mouse,
            position: tester.getCenter(strip),
            scrollDelta: const Offset(0, 2000),
          ),
        );
        await tester.pumpAndSettle();
        expect(scrollable.position.pixels, scrollable.position.maxScrollExtent);
        final favorites = find.byKey(const ValueKey('channel-favorites'));
        expect(favorites.hitTestable(), findsOneWidget);
        await tester.tap(favorites);
        await tester.pumpAndSettle();
        expect(find.text('channel favorites'), findsOneWidget);
        await tester.sendEventToBinding(
          PointerScrollEvent(
            kind: PointerDeviceKind.mouse,
            position: tester.getCenter(strip),
            scrollDelta: const Offset(0, -2000),
          ),
        );
        await tester.pumpAndSettle();
        expect(scrollable.position.pixels, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('keyboard closes tabs after a mouse click unfocuses search', (
    tester,
  ) async {
    final router = _router((context, tab) => Text('page ${tab.id}'));
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    for (var index = 0; index < 2; index++) {
      await tester.tap(find.byKey(const ValueKey('new-workspace-tab')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('workspace-search')));
    await tester.pumpAndSettle();
    final editor = tester.widget<EditableText>(find.byType(EditableText));
    expect(editor.focusNode.hasFocus, isTrue);
    await tester.tap(find.text('page tab-2'), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(editor.focusNode.hasFocus, isFalse);

    await _shortcut(tester, LogicalKeyboardKey.keyW);
    expect(find.text('page tab-1'), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-tab-tab-2')), findsNothing);
    await _shortcut(tester, LogicalKeyboardKey.keyW);
    await _shortcut(tester, LogicalKeyboardKey.keyW);
    expect(find.text('page home'), findsOneWidget);
  });

  for (final (name, settings) in [
    (
      'custom binding',
      const ShortcutSettings.defaults().withKeys(ShortcutAction.closeTab, [
        'Ctrl+Q',
      ]),
    ),
    (
      'disabled action',
      const ShortcutSettings.defaults().withActionEnabled(
        ShortcutAction.closeTab,
        false,
      ),
    ),
    (
      'disabled shortcuts',
      const ShortcutSettings.defaults().withEnabled(false),
    ),
    (
      'unbound action',
      const ShortcutSettings.defaults().withKeys(ShortcutAction.closeTab, []),
    ),
  ]) {
    testWidgets('unfocused workspace respects $name', (tester) async {
      final router = _router(
        (context, tab) => Text('page ${tab.id}'),
        shortcuts: settings,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-workspace-tab')));
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await _shortcut(tester, LogicalKeyboardKey.keyW);
      expect(find.text('page tab-1'), findsOneWidget);
      await _shortcut(tester, LogicalKeyboardKey.keyQ);
      expect(
        find.text(
          settings.actionFor('Ctrl+Q') == ShortcutAction.closeTab
              ? 'page home'
              : 'page tab-1',
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets(
    'new tabs respect editors and workspace commands respect modal routes',
    (tester) async {
      final router = _router(
        (context, tab) => Text('page ${tab.id}'),
        shortcuts: const ShortcutSettings.defaults().withKeys(
          ShortcutAction.closeTab,
          ['Ctrl+W', 'MouseBack'],
        ),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-workspace-tab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-search')));
      await tester.pumpAndSettle();
      await _shortcut(tester, LogicalKeyboardKey.keyT);
      expect(find.text('page tab-1'), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-tab-tab-2')), findsNothing);
      await tester.tap(find.text('page tab-1'), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      for (final requestFocus in [false, true]) {
        final context = tester.element(find.text('page tab-1'));
        final dialog = showDialog<void>(
          context: context,
          requestFocus: requestFocus,
          builder: (_) => const AlertDialog(content: Text('modal')),
        );
        await tester.pumpAndSettle();
        await _shortcut(tester, LogicalKeyboardKey.keyW);
        await _shortcut(tester, LogicalKeyboardKey.keyT);
        final pointer = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kBackMouseButton,
        );
        await pointer.down(tester.getCenter(find.text('modal')));
        await pointer.up();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('workspace-tab-tab-1')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('workspace-tab-tab-2')), findsNothing);
        Navigator.of(context, rootNavigator: true).pop();
        await dialog;
        await tester.pumpAndSettle();
      }
      await _shortcut(tester, LogicalKeyboardKey.keyT);
      expect(find.text('page tab-2'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      await tester.pumpAndSettle();
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('page tab-1'), findsOneWidget);
      await _shortcut(tester, LogicalKeyboardKey.keyW);
      expect(find.text('page home'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('new-workspace-tab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-search')));
      await tester.pumpAndSettle();
      await _shortcut(tester, LogicalKeyboardKey.keyW);
      expect(find.text('page home'), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-tab-tab-3')), findsNothing);

      await tester.pumpWidget(const MaterialApp(home: Text('replacement')));
      await tester.pumpAndSettle();
      await _shortcut(tester, LogicalKeyboardKey.keyT);
      await _shortcut(tester, LogicalKeyboardKey.keyW);
      expect(find.text('replacement'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in WorkspaceNavigationMode.values) {
    for (final (key, button) in [
      ('MouseBack', kBackMouseButton),
      ('MouseForward', kForwardMouseButton),
    ]) {
      testWidgets('$key closes pages with editor focus in $mode', (
        tester,
      ) async {
        final router = _router(
          (_, tab) => Column(
            children: [
              Text('page ${tab.id}'),
              TextField(key: ValueKey('composer-${tab.id}')),
            ],
          ),
          navigationMode: mode,
          shortcuts: const ShortcutSettings.defaults().withKeys(
            ShortcutAction.closeTab,
            ['Ctrl+W', key],
          ),
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        router.go('/search?q=retained');
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('composer-tab-1')),
          'retained draft',
        );
        router.go('/settings');
        await tester.pumpAndSettle();
        final composer = find.byKey(const ValueKey('composer-tab-2'));
        await tester.enterText(composer, 'current draft');
        await tester.pump();
        final editor = tester.widget<EditableText>(
          find.descendant(of: composer, matching: find.byType(EditableText)),
        );
        expect(editor.focusNode.hasFocus, isTrue);

        final pointer = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: button,
        );
        await pointer.down(tester.getCenter(composer));
        await tester.pumpAndSettle();
        expect(find.text('page tab-1'), findsOneWidget);
        expect(find.text('page tab-2'), findsNothing);
        expect(find.text('retained draft'), findsOneWidget);
        // Holding the side button across the rebuild must not close again.
        await pointer.moveTo(tester.getCenter(find.text('page tab-1')));
        await tester.pumpAndSettle();
        expect(find.text('page tab-1'), findsOneWidget);
        await pointer.up();

        final search = find.byKey(const ValueKey('workspace-search'));
        await tester.tap(search);
        await tester.pumpAndSettle();
        final searchEditor = tester.widget<EditableText>(
          find.descendant(of: search, matching: find.byType(EditableText)),
        );
        expect(searchEditor.focusNode.hasFocus, isTrue);
        await pointer.down(tester.getCenter(search));
        await pointer.up();
        await tester.pumpAndSettle();
        expect(find.text('page home'), findsOneWidget);

        await pointer.down(tester.getCenter(find.text('page home')));
        await pointer.up();
        await tester.pumpAndSettle();
        expect(find.text('page home'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final (action, key) in [
    (ShortcutAction.closeTab, 'W'),
    (ShortcutAction.closeTab, 'F8'),
    (ShortcutAction.newTab, 'MouseBack'),
  ]) {
    testWidgets('$action with $key still reserves editor input', (
      tester,
    ) async {
      final router = _router(
        (_, tab) => Text('page ${tab.id}'),
        shortcuts: const ShortcutSettings.defaults().withKeys(action, [key]),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-workspace-tab')));
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('workspace-search'));
      await tester.enterText(search, 'draft');
      await tester.pump();
      if (key == 'MouseBack') {
        final pointer = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kBackMouseButton,
        );
        await pointer.down(tester.getCenter(search));
        await pointer.up();
      } else {
        await tester.sendKeyEvent(
          key == 'W' ? LogicalKeyboardKey.keyW : LogicalKeyboardKey.f8,
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('page tab-1'), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-tab-tab-2')), findsNothing);
      expect(find.text('draft'), findsOneWidget);
    });
  }

  for (final enabled in [true, false]) {
    testWidgets('mouse side key closes the active tab when enabled=$enabled', (
      tester,
    ) async {
      final router = _router(
        (context, tab) => Text('page ${tab.id}'),
        shortcuts: const ShortcutSettings.defaults()
            .withKeys(ShortcutAction.closeTab, ['MouseBack'])
            .withActionEnabled(ShortcutAction.closeTab, enabled),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-workspace-tab')));
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('workspace-search'));
      await tester.tap(search);
      await tester.pumpAndSettle();
      final pointer = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kBackMouseButton,
      );
      await pointer.down(tester.getCenter(search));
      await pointer.up();
      await tester.pumpAndSettle();
      expect(find.text(enabled ? 'page home' : 'page tab-1'), findsOneWidget);
      if (enabled) {
        await pointer.down(tester.getCenter(find.text('page home')));
        await pointer.up();
        await tester.pumpAndSettle();
        expect(find.text('page home'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'settings categories replace home channels and keep the same tab',
    (tester) async {
      final router = _router(
        (context, tab) =>
            Text('page ${tab.id} ${tab.location.queryParameters['section']}'),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      router.go('/settings');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('channel-recommended')), findsNothing);
      expect(find.byKey(const ValueKey('channel-popular')), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('settings-category-shortcuts')),
      );
      await tester.pumpAndSettle();
      expect(find.text('page tab-1 shortcuts'), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-tab-tab-2')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('workspace-tab-home')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('channel-recommended')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('workspace-tab-tab-1')));
      await tester.pumpAndSettle();
      expect(find.text('page tab-1 shortcuts'), findsOneWidget);
    },
  );
  testWidgets('browse tabs preserve page state and dispose closed pages', (
    tester,
  ) async {
    final disposed = <String>[];
    final router = _router(
      (context, tab) => _CounterPage(tab: tab, onDispose: disposed.add),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(builder: AppNoticeHost.builder, routerConfig: router),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('count 0'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('new-workspace-tab')));
    await tester.pumpAndSettle();
    expect(find.text('count 0'), findsOneWidget);
    await tester.tap(find.text('count 0'));
    await tester.pump();
    await tester.tap(find.text('count 1'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('workspace-tab-home')));
    await tester.pumpAndSettle();
    expect(find.text('count 1'), findsOneWidget);
    expect(disposed, isEmpty);
    await tester.tap(find.byKey(const ValueKey('workspace-tab-tab-1')));
    await tester.pumpAndSettle();
    expect(find.text('count 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('close-workspace-tab-tab-1')));
    await tester.pumpAndSettle();
    expect(find.text('count 1'), findsOneWidget);
    expect(disposed, ['tab-1']);
    expect(
      find.byKey(const ValueKey('close-workspace-tab-home')),
      findsNothing,
    );
  });

  testWidgets('keyboard creates, cycles and closes tabs without closing home', (
    tester,
  ) async {
    final router = _router((context, tab) => Text('page ${tab.id}'));
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(builder: AppNoticeHost.builder, routerConfig: router),
    );
    await tester.pumpAndSettle();
    await _shortcut(tester, LogicalKeyboardKey.keyT);
    expect(find.text('page tab-1'), findsOneWidget);
    await _shortcut(tester, LogicalKeyboardKey.keyT);
    expect(find.text('page tab-2'), findsOneWidget);
    await _shortcut(tester, LogicalKeyboardKey.tab);
    expect(find.text('page home'), findsOneWidget);
    await _shortcut(tester, LogicalKeyboardKey.tab, shift: true);
    expect(find.text('page tab-2'), findsOneWidget);
    await _shortcut(tester, LogicalKeyboardKey.keyW);
    expect(find.text('page tab-1'), findsOneWidget);
    await _shortcut(tester, LogicalKeyboardKey.keyW);
    await _shortcut(tester, LogicalKeyboardKey.keyW);
    expect(find.text('page home'), findsOneWidget);
  });

  testWidgets('hidden video pages stay mounted until explicitly closed', (
    tester,
  ) async {
    final mounted = <String>{};
    final router = _router(
      (context, tab) => tab.isVideo
          ? _VideoOwner(id: tab.id, mountedOwners: mounted)
          : Text('page ${tab.id}'),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(builder: AppNoticeHost.builder, routerConfig: router),
    );
    await tester.pumpAndSettle();
    router.go('/video/BV1234567890');
    await tester.pumpAndSettle();
    expect(mounted, {'tab-1'});
    router.go('/video/BV0987654321');
    await tester.pumpAndSettle();
    expect(mounted, {'tab-1', 'tab-2'});
    await tester.tap(find.byKey(const ValueKey('workspace-tab-tab-1')));
    await tester.pumpAndSettle();
    expect(mounted, {'tab-1', 'tab-2'});
    await tester.tap(find.byKey(const ValueKey('workspace-tab-home')));
    await tester.pumpAndSettle();
    expect(mounted, {'tab-1', 'tab-2'});
    await tester.tap(find.byKey(const ValueKey('close-workspace-tab-tab-1')));
    await tester.pumpAndSettle();
    expect(mounted, {'tab-2'});
  });

  testWidgets(
    'narrow caption controls and many tabs fit and selected tab is visible',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final router = _router(
        (context, tab) => Text('page ${tab.id}'),
        customCaption: true,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          builder: AppNoticeHost.builder,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();
      for (var index = 0; index < 18; index++) {
        await tester.tap(find.byKey(const ValueKey('new-workspace-tab')));
        await tester.pumpAndSettle();
      }
      expect(find.text('page tab-15'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workspace-tab-tab-15')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopRight(find.byKey(const ValueKey('caption-controls'))).dx,
        420,
      );
    },
  );
}

GoRouter _router(
  WorkspacePageBuilder builder, {
  bool customCaption = false,
  ShortcutSettings shortcuts = const ShortcutSettings.defaults(),
  WorkspaceNavigationMode? navigationMode =
      WorkspaceNavigationMode.multipleTabs,
  String initialLocation = '/',
}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    ShellRoute(
      builder: (context, state, child) => BiliAppShell(
        shortcuts: shortcuts,
        navigationMode: navigationMode,
        location: state.uri.toString(),
        pageBuilder: (context, tab) => tab.location.path == '/search'
            ? ProviderScope(
                overrides: [
                  searchRepositoryProvider.overrideWithValue(
                    _ShellSearchRepository(),
                  ),
                ],
                child: Builder(
                  builder: (context) =>
                      WorkspacePageHeader.wrap(context, builder(context, tab)),
                ),
              )
            : builder(context, tab),
        windowControlsBuilder: customCaption
            ? (_) => const SizedBox(
                key: ValueKey('caption-controls'),
                width: 138,
                height: 42,
              )
            : null,
        dragRegionBuilder: customCaption ? (_, child) => child : null,
        child: child,
      ),
      routes: [
        for (final path in ['/', '/video/:bvid', '/search', '/settings'])
          GoRoute(path: path, builder: (_, state) => const SizedBox.shrink()),
      ],
    ),
  ],
);

final class _ShellSearchRepository implements SearchRepository {
  @override
  Future<SearchPage> search({
    required String query,
    required int page,
    required SearchCategory category,
    required SearchOrder order,
    required SearchDuration duration,
    required SearchUserType userType,
    required RequestCancellation cancellation,
  }) async => SearchPage(items: [], hasMore: false);
}

Future<void> _shortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

class _CounterPage extends StatefulWidget {
  const _CounterPage({required this.tab, required this.onDispose});
  final WorkspaceTab tab;
  final ValueChanged<String> onDispose;
  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  int count = 0;
  @override
  void dispose() {
    widget.onDispose(widget.tab.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => setState(() => count++),
      child: Text('count $count'),
    ),
  );
}

class _VideoOwner extends StatefulWidget {
  const _VideoOwner({required this.id, required this.mountedOwners});
  final String id;
  final Set<String> mountedOwners;
  @override
  State<_VideoOwner> createState() => _VideoOwnerState();
}

class _VideoOwnerState extends State<_VideoOwner> {
  @override
  void initState() {
    super.initState();
    widget.mountedOwners.add(widget.id);
  }

  @override
  void dispose() {
    widget.mountedOwners.remove(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
