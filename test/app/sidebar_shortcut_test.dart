import '../support/input_test_app.dart';

import 'package:bilisail/app/platform_defaults.dart';
import 'package:bilisail/app/shell.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _region = find.byKey(const ValueKey('workspace-sidebar-region'));

void main() {
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
          find.byTooltip(
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
