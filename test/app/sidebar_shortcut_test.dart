import '../support/material_tooltip_finder.dart';

import '../support/input_test_app.dart';

import 'package:bilisail/app/platform_defaults.dart';
import 'package:bilisail/app/shell.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:bilisail/shared/ui/featured_navigation_scope.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

final _region = find.byKey(const ValueKey('workspace-sidebar-region'));

void main() {
  for (final (mode, detached) in [
    (NavigationBarMode.sidebar, false),
    (NavigationBarMode.bottom, false),
    (NavigationBarMode.sidebar, true),
  ]) {
    testWidgets(
      'seeded Story inherits only an inline workspace sidebar ($mode, detached=$detached)',
      (tester) async {
        _wideView(tester);
        const bvid = 'BV1234567891';
        final video = Uri(path: '/video/$bvid');
        final story = Uri(
          path: '/story/$bvid',
          queryParameters: {'cid': '1', 'returnTo': video.toString()},
        );
        final changes = <bool>[];
        final router = GoRouter(
          initialLocation: video.toString(),
          routes: [
            ShellRoute(
              builder: (context, state, child) => BiliAppShell(
                location: state.uri.toString(),
                navigationMode: detached
                    ? WorkspaceNavigationMode.dualTabs
                    : WorkspaceNavigationMode.singlePage,
                navigationBarMode: mode,
                onSidebarCollapsedChanged: changes.add,
                playbackWindowBuilder: detached ? _mountPlayback : null,
                pageBuilder: (context, tab) => switch (tab.location.path) {
                  '/video/$bvid' => Center(
                    child: TextButton(
                      onPressed: () =>
                          WorkspacePageNavigation.maybeOf(context)
                              ?.navigate(story),
                      child: const Text('上下滑观看'),
                    ),
                  ),
                  '/story/$bvid' => const Column(
                    children: [Text('Story'), FeaturedNavigationToggle()],
                  ),
                  _ => const SizedBox.shrink(),
                },
                child: child,
              ),
              routes: [
                for (final path in ['/', '/video/:bvid', '/story/:bvid'])
                  GoRoute(path: path, builder: (_, _) => const SizedBox()),
              ],
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(InputTestApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        await tester.tap(find.text('上下滑观看'));
        await tester.pumpAndSettle();
        final location = router.routeInformationProvider.value.uri;
        expect(location.path, story.path);
        expect(location.queryParameters, containsPair('cid', '1'));
        expect(
          location.queryParameters,
          containsPair('returnTo', video.toString()),
        );
        expect(find.text('Story'), findsOneWidget);

        final collapse = find.byIcon(Icons.zoom_out_map_rounded);
        if (detached || mode == NavigationBarMode.bottom) {
          expect(collapse, findsNothing);
          expect(changes, isEmpty);
          return;
        }

        expect(tester.getSize(_region).width, 76);
        await tester.tap(collapse);
        await tester.pumpAndSettle();
        expect(tester.getSize(_region).width, 0);
        expect(changes, [true]);
        await tester.tap(find.byIcon(Icons.zoom_in_map_rounded));
        await tester.pumpAndSettle();
        expect(tester.getSize(_region).width, 76);
        expect(changes, [true, false]);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  for (final mode in WorkspaceNavigationMode.values) {
    testWidgets(
      'sidebar shortcut toggles once per press and retains the page: $mode',
      (tester) async {
        _wideView(tester);
        final settings = shortcutSettingsForPlatform(defaultTargetPlatform);
        final modifier = settings.useAppleDefaults
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        await tester.pumpWidget(
          InputTestApp(
            shortcuts: settings,
            home: BiliAppShell(
              location: '/',
              shortcuts: settings,
              navigationMode: mode,
              child: const Text('retained page'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final page = tester.element(find.text('retained page'));
        expect(tester.getSize(_region).width, 76);
        expect(
          findMaterialTooltip(
            settings.useAppleDefaults ? '收起侧栏（⌘ Command+B）' : '收起侧栏（Ctrl+B）',
          ),
          findsOneWidget,
        );
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB);
        await tester.pumpAndSettle();
        expect(tester.getSize(_region).width, 0);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyB);
        await tester.pumpAndSettle();
        expect(tester.getSize(_region).width, 0);
        await tester.sendKeyUpEvent(modifier);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
        await _press(tester, modifier);
        expect(tester.getSize(_region).width, 76);
        expect(tester.element(find.text('retained page')), same(page));
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  }

  testWidgets('sidebar shortcut respects editing and modal isolation', (
    tester,
  ) async {
    _wideView(tester);
    await tester.pumpWidget(
      const InputTestApp(
        home: BiliAppShell(
          location: '/',
          child: TextField(key: ValueKey('draft')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final draft = find.byKey(const ValueKey('draft'));
    await tester.enterText(draft, 'draft');
    await _press(tester, LogicalKeyboardKey.controlLeft);
    expect(tester.getSize(_region).width, 76);
    expect(find.text('draft'), findsOneWidget);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final dialog = showDialog<void>(
      context: tester.element(draft),
      builder: (context) => AlertDialog(
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('close dialog'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.controlLeft);
    expect(tester.getSize(_region).width, 76);
    await tester.tap(find.text('close dialog'));
    await dialog;
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.controlLeft);
    expect(tester.getSize(_region).width, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar shortcut follows bindings, visibility and layout', (
    tester,
  ) async {
    _wideView(tester);
    const defaults = ShortcutSettings.defaults();
    var active = true;
    var navigationBarMode = NavigationBarMode.automatic;
    var saves = 0;
    Future<void> mount(ShortcutSettings settings) async {
      await tester.pumpWidget(
        InputTestApp(
          shortcuts: settings,
          home: WorkspaceActivity(
            active: active,
            child: BiliAppShell(
              location: '/',
              shortcuts: settings,
              navigationBarMode: navigationBarMode,
              onSidebarCollapsedChanged: (_) => saves++,
              child: const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final settings in [
      defaults.withEnabled(false),
      defaults.withActionEnabled(ShortcutAction.toggleSidebar, false),
      defaults.withKeys(ShortcutAction.toggleSidebar, []),
      defaults.withKeys(ShortcutAction.toggleSidebar, ['Alt+B']),
    ]) {
      await mount(settings);
      await _press(tester, LogicalKeyboardKey.controlLeft);
      expect(tester.getSize(_region).width, 76);
      expect(saves, 0);
    }
    await _press(tester, LogicalKeyboardKey.altLeft);
    expect(tester.getSize(_region).width, 0);
    expect(saves, 1);
    await _press(tester, LogicalKeyboardKey.altLeft);
    expect(tester.getSize(_region).width, 76);
    saves = 0;
    active = false;
    await mount(defaults);
    await _press(tester, LogicalKeyboardKey.controlLeft);
    expect(tester.getSize(_region).width, 76);
    expect(saves, 0);
    active = true;
    navigationBarMode = NavigationBarMode.bottom;
    await mount(defaults);
    await _press(tester, LogicalKeyboardKey.controlLeft);
    expect(saves, 0);
    navigationBarMode = NavigationBarMode.automatic;
    await mount(defaults);
    tester.view.physicalSize = const Size(390, 900);
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.controlLeft);
    expect(saves, 0);
    tester.view.physicalSize = const Size(1280, 900);
    await tester.pumpAndSettle();
    expect(tester.getSize(_region).width, 76);
    await _press(tester, LogicalKeyboardKey.controlLeft);
    expect(tester.getSize(_region).width, 0);
    expect(saves, 1);
    expect(tester.takeException(), isNull);
  });
}

Widget _mountPlayback(
  BuildContext context, {
  required Widget child,
  required Widget? playback,
  required bool keepPlaybackMounted,
  required Object? activationToken,
  required VoidCallback onClose,
  required VoidCallback onBack,
  required VoidCallback onHome,
  required ValueChanged<Object> onError,
}) => Stack(fit: StackFit.expand, children: [child, ?playback]);

void _wideView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey modifier) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}
