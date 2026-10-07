import '../support/input_test_app.dart';

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
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows,
    TargetPlatform.macOS,
  ]) {
    for (final mode in WorkspaceNavigationMode.values) {
      _workspaceTestWidgets('$platform workspace chrome in $mode', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final mobile =
            platform == TargetPlatform.android ||
            platform == TargetPlatform.iOS;
        final router = _router(
          (_, tab) =>
              SizedBox.expand(key: ValueKey('body-${tab.location.path}')),
          navigationMode: mode,
          customCaption: true,
          accountBuilder: (_) => const SizedBox(width: 34, height: 34),
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(InputTestApp.router(routerConfig: router));
        for (final width in [420.0, 1280.0]) {
          tester.view.physicalSize = Size(width, 850);
          for (final location in [
            '/',
            '/video/BV1234567890',
            '/user/123',
            '/search?q=test',
            '/settings',
            '/history',
          ]) {
            router.go(location);
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('single-page-header')),
              !mobile && mode == WorkspaceNavigationMode.singlePage
                  ? findsOneWidget
                  : findsNothing,
            );
            expect(
              find.byKey(const ValueKey('workspace-tab-strip')),
              !mobile && mode == WorkspaceNavigationMode.multipleTabs
                  ? findsOneWidget
                  : findsNothing,
            );
            expect(
              find.byKey(const ValueKey('workspace-back')),
              mobile ? findsNothing : findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('workspace-home')),
              !mobile &&
                      mode == WorkspaceNavigationMode.singlePage &&
                      location != '/'
                  ? findsOneWidget
                  : findsNothing,
            );
            expect(
              find.byKey(const ValueKey('caption-controls')),
              mobile ? findsNothing : findsOneWidget,
            );
            if (location.startsWith('/video/') ||
                location.startsWith('/user/')) {
              expect(
                tester.getTopLeft(find.byKey(ValueKey('body-$location'))).dy,
                mobile ? 0 : 42,
              );
            }
            expect(tester.takeException(), isNull);
          }
        }
        router.go('/video/BV1234567890');
        await tester.pumpAndSettle();
        router.go('/user/123');
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          '/video/BV1234567890',
        );
      }, variant: TargetPlatformVariant.only(platform));
    }
  }

  for (final width in [420.0, 1280.0]) {
    for (final location in [
      '/',
      '/search?q=test',
      '/settings',
      '/history',
      '/video/BV1234567890',
      '/user/123',
    ]) {
      _workspaceTestWidgets(
        'single page retains window controls at $width on $location',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 850);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          var windowDrags = 0;
          final router = _router(
            (_, tab) => SizedBox.expand(key: ValueKey('page-${tab.id}')),
            navigationMode: WorkspaceNavigationMode.singlePage,
            initialLocation: location,
            customCaption: true,
            onWindowDrag: () => windowDrags++,
            accountBuilder: (_) => const SizedBox(width: 34, height: 34),
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(InputTestApp.router(routerConfig: router));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('single-page-header')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('workspace-tab-strip')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('caption-controls')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('caption-drag-region')),
            findsOneWidget,
          );
          await tester.drag(
            find.byKey(const ValueKey('caption-drag-region')),
            const Offset(40, 0),
          );
          await tester.pumpAndSettle();
          expect(windowDrags, 1);
          expect(
            tester
                .getTopRight(find.byKey(const ValueKey('caption-controls')))
                .dx,
            width,
          );
          if (location.startsWith('/video/') || location.startsWith('/user/')) {
            expect(
              tester.getTopLeft(find.byKey(const ValueKey('page-tab-1'))).dy,
              42,
            );
          } else {
            expect(
              tester
                  .getTopLeft(find.byKey(const ValueKey('workspace-search')))
                  .dy,
              42 + 9 + (width >= 760 ? 3 : 0),
            );
          }
          if (location != '/') {
            await tester.tap(find.byKey(const ValueKey('workspace-home')));
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('page-home')), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  _workspaceTestWidgets(
    'window deactivation cancels held workspace repeats until release',
    (tester) async {
      final router = _router((_, tab) => Text('page ${tab.id}'));
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-workspace-tab')));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.text('page home'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.text('page home'), findsOneWidget);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('page tab-1'), findsOneWidget);
    },
  );
  _workspaceTestWidgets(
    'fixed tab cycling repeats across page activation with master switch disabled',
    (tester) async {
      final router = _router(
        (_, tab) => Text('page ${tab.id}'),
        shortcuts: const ShortcutSettings.defaults().withEnabled(false),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-workspace-tab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-workspace-tab')));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.text('page home'), findsOneWidget);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.text('page tab-1'), findsOneWidget);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.text('page tab-2'), findsOneWidget);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    },
  );

  _workspaceTestWidgets(
    'background page navigation updates its tab without selecting it',
    (tester) async {
      final navigation = <String, ValueChanged<Uri>>{};
      final router = _router(
        (_, tab) => Builder(
          builder: (context) {
            navigation[tab.id] = WorkspacePageNavigation.maybeOf(context)!
                .navigate;
            return Text('page ${tab.id} ${tab.location.path}');
          },
        ),
        initialLocation: '/video/BV1234567890?queue=fixture',
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      router.go('/search?q=still-reading');
      await tester.pumpAndSettle();
      navigation['tab-1']!(Uri.parse('/video/BV0987654321?queue=fixture'));
      await tester.pumpAndSettle();
      expect(find.text('page tab-2 /search'), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/search');
      expect(
        router.routeInformationProvider.value.uri.queryParameters['q'],
        'still-reading',
      );
      expect(find.byKey(const ValueKey('workspace-tab-tab-3')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('workspace-back')));
      await tester.pumpAndSettle();
      expect(find.text('page tab-1 /video/BV0987654321'), findsOneWidget);
      expect(
        router.routeInformationProvider.value.uri.queryParameters['queue'],
        'fixture',
      );
      navigation['tab-1']!(Uri.parse('/video/BV1234567890?queue=fixture'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/video/BV1234567890',
      );
      expect(find.byKey(const ValueKey('workspace-tab-tab-3')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  _workspaceTestWidgets(
    'single page back restores state, releases popped pages and handles system back',
    (tester) async {
      final disposed = <String>[];
      final router = _router(
        (context, tab) => _CounterPage(tab: tab, onDispose: disposed.add),
        navigationMode: WorkspaceNavigationMode.singlePage,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('single-page-header')), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-tab-strip')), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('workspace-search'))).dy,
        54,
      );
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

  _workspaceTestWidgets(
    'a single-page deep link can return home and modal back stays in the page',
    (tester) async {
      final router = _router(
        (_, tab) => Text('page ${tab.id}'),
        navigationMode: WorkspaceNavigationMode.singlePage,
        initialLocation: '/video/BV1234567890',
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
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
    _workspaceTestWidgets(
      '$platform default mode is stable across window resizing',
      (tester) async {
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
        await tester.pumpWidget(InputTestApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        await tester.tap(find.text('count 0'));
        router.go('/search?q=test');
        await tester.pumpAndSettle();
        await tester.tap(find.text('count 0'));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('workspace-tab-strip')),
          singlePage ? findsNothing : findsOneWidget,
        );
        tester.view.physicalSize = const Size(1280, 850);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('workspace-tab-strip')),
          singlePage ? findsNothing : findsOneWidget,
        );
        expect(find.text('count 1'), findsOneWidget);
        tester.view.physicalSize = const Size(420, 850);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('workspace-tab-strip')),
          singlePage ? findsNothing : findsOneWidget,
        );
        expect(find.text('count 1'), findsOneWidget);
        expect(disposed, isEmpty);
        if (singlePage) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.byKey(const ValueKey('workspace-back')));
        }
        await tester.pumpAndSettle();
        expect(find.text('count 1'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  _workspaceTestWidgets(
    'multiple tabs can go back through visits without closing pages',
    (tester) async {
      final router = _router((_, tab) => Text('page ${tab.id}'));
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
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
    _workspaceTestWidgets(
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
          InputTestApp.router(
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

  _workspaceTestWidgets(
    'keyboard closes tabs after a mouse click unfocuses search',
    (tester) async {
      final router = _router((context, tab) => Text('page ${tab.id}'));
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
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
    },
  );

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
    _workspaceTestWidgets('unfocused workspace respects $name', (tester) async {
      final router = _router(
        (context, tab) => Text('page ${tab.id}'),
        shortcuts: settings,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
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

  _workspaceTestWidgets(
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
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
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

      await tester.pumpWidget(const InputTestApp(home: Text('replacement')));
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
      _workspaceTestWidgets('$key closes pages with editor focus in $mode', (
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
        await tester.pumpWidget(InputTestApp.router(routerConfig: router));
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
    _workspaceTestWidgets('$action with $key still reserves editor input', (
      tester,
    ) async {
      final router = _router(
        (_, tab) => Text('page ${tab.id}'),
        shortcuts: const ShortcutSettings.defaults().withKeys(action, [key]),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
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
    _workspaceTestWidgets(
      'mouse side key closes the active tab when enabled=$enabled',
      (tester) async {
        final router = _router(
          (context, tab) => Text('page ${tab.id}'),
          shortcuts: const ShortcutSettings.defaults()
              .withKeys(ShortcutAction.closeTab, ['MouseBack'])
              .withActionEnabled(ShortcutAction.closeTab, enabled),
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(InputTestApp.router(routerConfig: router));
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
      },
    );
  }

  _workspaceTestWidgets(
    'settings categories replace home channels and keep the same tab',
    (tester) async {
      final router = _router(
        (context, tab) =>
            Text('page ${tab.id} ${tab.location.queryParameters['section']}'),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
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
  _workspaceTestWidgets(
    'browse tabs preserve page state and dispose closed pages',
    (tester) async {
      final disposed = <String>[];
      final router = _router(
        (context, tab) => _CounterPage(tab: tab, onDispose: disposed.add),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        InputTestApp.router(
          builder: AppNoticeHost.builder,
          routerConfig: router,
        ),
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
    },
  );

  _workspaceTestWidgets(
    'keyboard creates, cycles and closes tabs without closing home',
    (tester) async {
      final router = _router((context, tab) => Text('page ${tab.id}'));
      addTearDown(router.dispose);
      await tester.pumpWidget(
        InputTestApp.router(
          builder: AppNoticeHost.builder,
          routerConfig: router,
        ),
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
    },
  );

  _workspaceTestWidgets(
    'hidden video pages stay mounted until explicitly closed',
    (tester) async {
      final mounted = <String>{};
      final router = _router(
        (context, tab) => tab.isVideo
            ? _VideoOwner(id: tab.id, mountedOwners: mounted)
            : Text('page ${tab.id}'),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        InputTestApp.router(
          builder: AppNoticeHost.builder,
          routerConfig: router,
        ),
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
    },
  );

  _workspaceTestWidgets(
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
        InputTestApp.router(
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

void _workspaceTestWidgets(
  String description,
  WidgetTesterCallback callback, {
  TargetPlatformVariant? variant,
}) => testWidgets(
  description,
  callback,
  variant: variant ?? TargetPlatformVariant.only(TargetPlatform.windows),
);

GoRouter _router(
  WorkspacePageBuilder builder, {
  bool customCaption = false,
  WidgetBuilder? accountBuilder,
  VoidCallback? onWindowDrag,
  ShortcutSettings shortcuts = const ShortcutSettings.defaults(),
  WorkspaceNavigationMode? navigationMode =
      WorkspaceNavigationMode.multipleTabs,
  String initialLocation = '/',
}) => GoRouter(
  observers: [],
  initialLocation: initialLocation,
  routes: [
    ShellRoute(
      observers: [],
      builder: (context, state, child) => BiliAppShell(
        shortcuts: shortcuts,
        navigationMode: navigationMode,
        location: state.uri.toString(),
        accountBuilder: accountBuilder,
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
        dragRegionBuilder: customCaption
            ? (_, child) => GestureDetector(
                key: const ValueKey('caption-drag-region'),
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => onWindowDrag?.call(),
                child: child,
              )
            : null,
        child: child,
      ),
      routes: [
        for (final path in [
          '/',
          '/video/:bvid',
          '/user/:mid',
          '/search',
          '/settings',
          '/history',
        ])
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
