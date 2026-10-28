import 'package:bilisail/app/router.dart';
import 'package:bilisail/app/shell.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/platform/window_caption.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _region = find.byKey(const ValueKey('workspace-sidebar-region'));
final _toggle = find.byKey(const ValueKey('workspace-sidebar-toggle'));

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
    for (final dark in [false, true]) {
      testWidgets(
        'desktop navigation buttons match in all modes: $platform dark=$dark',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1280, 900);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          for (final mode in WorkspaceNavigationMode.values) {
            await tester.pumpWidget(
              MaterialApp(
                theme: (dark ? BiliTheme.dark() : BiliTheme.light()).copyWith(
                  platform: platform,
                ),
                home: BiliAppShell(
                  location: '/',
                  navigationMode: mode,
                  child: const SizedBox(),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final playback = find.byKey(
              const ValueKey('workspace-return-to-playback'),
            );
            for (final finder in [_toggle, playback]) {
              final button = tester.widget<IconButton>(finder);
              expect(button.style, desktopCaptionButtonStyle);
              expect(tester.getSize(finder), const Size(46, 44));
              expect(
                tester
                    .widget<Icon>(
                      find.descendant(of: finder, matching: find.byType(Icon)),
                    )
                    .size,
                18,
              );
            }
            expect(tester.widget<IconButton>(playback).onPressed, isNull);
            await tester.tap(_toggle);
            await tester.pumpAndSettle();
            expect(tester.getSize(_region).width, 0);
            await tester.tap(_toggle);
            await tester.pumpAndSettle();
            expect(tester.getSize(_region).width, 76);
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }

  for (final dark in [false, true]) {
    testWidgets('sidebar styles adapt and retain content, dark=$dark', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1600, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final style = ValueNotifier(SidebarStyle.automatic);
      addTearDown(style.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? BiliTheme.dark() : BiliTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: ValueListenableBuilder(
            valueListenable: style,
            builder: (context, value, _) => BiliAppShell(
              location: '/',
              sidebarStyle: value,
              child: const SizedBox.expand(key: ValueKey('content')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final content = tester.element(find.byKey(const ValueKey('content')));
      for (final width in [599.0, 600.0, 1280.0, 1600.0]) {
        tester.view.physicalSize = Size(width, 900);
        for (final value in SidebarStyle.values) {
          style.value = value;
          await tester.pumpAndSettle();
          final expectedWidth = width < 600
              ? 0.0
              : value == SidebarStyle.expanded ||
                    (value == SidebarStyle.automatic && width >= 1600)
              ? 164.0
              : 76.0;
          expect(tester.getSize(_region).width, expectedWidth);
          expect(_toggle, width < 600 ? findsNothing : findsOneWidget);
          if (width >= 600) {
            final home = find.byKey(const ValueKey('workspace-nav-home'));
            final icon = tester.getRect(
              find.descendant(of: home, matching: find.byType(Icon)),
            );
            final label = tester.getRect(
              find.descendant(of: home, matching: find.text('首页')),
            );
            if (expectedWidth == 164) {
              expect(icon.right, lessThan(label.left));
            } else {
              expect(icon.bottom, lessThan(label.top));
            }
          }
          expect(
            tester.element(find.byKey(const ValueKey('content'))),
            same(content),
          );
          expect(tester.takeException(), isNull, reason: '$width $value');
        }
      }
    });
  }

  testWidgets(
    'collapse reverses smoothly and survives narrow layouts without replacing the page',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1600, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          theme: BiliTheme.light(),
          home: const BiliAppShell(
            location: '/',
            child: TextField(key: ValueKey('draft')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final draft = find.byKey(const ValueKey('draft'));
      final element = tester.element(draft);
      await tester.enterText(draft, '保留草稿');
      final buttonRect = tester.getRect(_toggle);
      await tester.tap(_toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getSize(_region).width, inExclusiveRange(0, 164));
      expect(tester.getRect(_toggle), buttonRect);
      await tester.tap(_toggle);
      await tester.pumpAndSettle();
      expect(tester.getSize(_region).width, 164);
      await tester.tap(_toggle);
      await tester.pumpAndSettle();
      expect(tester.getSize(_region).width, 0);
      expect(find.byTooltip('展开侧栏'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workspace-nav-home')).hitTestable(),
        findsNothing,
      );
      tester.view.physicalSize = const Size(390, 900);
      await tester.pumpAndSettle();
      expect(_toggle, findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      tester.view.physicalSize = const Size(1600, 900);
      await tester.pumpAndSettle();
      expect(tester.getSize(_region).width, 0);
      await tester.tap(_toggle);
      await tester.pumpAndSettle();
      expect(tester.getSize(_region).width, 164);
      expect(tester.element(draft), same(element));
      expect(find.text('保留草稿'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reduced motion immediately finishes an active sidebar transition',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final reduceMotion = ValueNotifier(false);
      addTearDown(reduceMotion.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: reduceMotion,
            builder: (context, value, _) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: value),
              child: const BiliAppShell(
                location: '/',
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(_toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.getSize(_region).width, inExclusiveRange(0, 76));
      reduceMotion.value = true;
      await tester.pump();
      expect(tester.getSize(_region).width, 0);
      await tester.tap(_toggle);
      await tester.pump();
      expect(tester.getSize(_region).width, 76);
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in WorkspaceNavigationMode.values) {
    for (final failSave in [false, true]) {
      testWidgets(
        'router saves or rolls back sidebar preferences: $mode failure=$failSave',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1280, 900);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final repository = _SettingsRepository(mode)..failSave = failSave;
          final router = createBiliRouter(
            initialLocation: '/settings',
            playerBuilder: (_, detail, part) => const SizedBox(),
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                settingsRepositoryProvider.overrideWithValue(repository),
              ],
              child: MaterialApp.router(
                theme: BiliTheme.light(),
                builder: AppNoticeHost.builder,
                routerConfig: router,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final full = find.widgetWithText(ChoiceChip, '完整侧栏');
          await tester.ensureVisible(full);
          await tester.tap(full);
          await tester.pumpAndSettle();
          expect(tester.getSize(_region).width, failSave ? 76 : 164);
          expect(
            repository.settings.sidebarStyle,
            failSave ? SidebarStyle.automatic : SidebarStyle.expanded,
          );
          await tester.tap(_toggle);
          await tester.pumpAndSettle();
          expect(repository.settings.sidebarCollapsed, !failSave);
          expect(tester.getSize(_region).width, failSave ? 76 : 0);
          if (failSave) {
            expect(find.text('侧栏设置保存失败，请重试'), findsOneWidget);
          } else {
            final container = ProviderScope.containerOf(
              tester.element(_toggle),
            );
            container.invalidate(settingsControllerProvider);
            await tester.pumpAndSettle();
            expect(tester.getSize(_region).width, 0);
            await tester.tap(_toggle);
            await tester.pumpAndSettle();
            expect(tester.getSize(_region).width, 164);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

final class _SettingsRepository implements SettingsRepository {
  _SettingsRepository(WorkspaceNavigationMode mode)
    : settings = AppSettings.defaults(navigationMode: mode);
  AppSettings settings;
  bool failSave = false;
  @override
  Future<AppSettings> load() async => settings;
  @override
  Future<void> save(AppSettings value) async {
    if (failSave) throw StateError('disk');
    settings = value;
  }
}
