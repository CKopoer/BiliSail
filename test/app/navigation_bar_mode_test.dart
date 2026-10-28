import 'package:bilisail/app/router.dart';
import 'package:bilisail/app/shell.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/presentation/predictive_back_region.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:bilisail/shared/ui/primary_navigation_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

final _sidebar = find.byKey(const ValueKey('workspace-sidebar-region'));
final _toggle = find.byKey(const ValueKey('workspace-sidebar-toggle'));

void main() {
  testWidgets(
    'back animation and playback return follow navigation layout and safe area',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final mode = ValueNotifier(NavigationBarMode.automatic);
      addTearDown(mode.dispose);
      final router = GoRouter(
        routes: [
          ShellRoute(
            builder: (context, state, child) => ValueListenableBuilder(
              valueListenable: mode,
              builder: (_, value, _) => BiliAppShell(
                location: state.uri.toString(),
                navigationMode: WorkspaceNavigationMode.dualTabs,
                navigationBarMode: value,
                pageBuilder: (_, tab) => Text('page ${tab.location.path}'),
                child: child,
              ),
            ),
            routes: [
              for (final path in ['/', '/history', '/video/:bvid'])
                GoRoute(path: path, builder: (_, _) => const SizedBox()),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      var padding = 0.0;
      await tester.pumpWidget(
        MaterialApp.router(
          theme: BiliTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(padding: EdgeInsets.symmetric(horizontal: padding)),
            child: child!,
          ),
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();
      router.go('/video/test');
      await tester.pumpAndSettle();
      router.go('/history');
      await tester.pumpAndSettle();
      for (final (width, inset) in [
        (390.0, 0.0),
        (1280.0, 0.0),
        (620.0, 20.0),
      ]) {
        padding = inset;
        tester.view.physicalSize = Size(width, 900);
        for (final value in NavigationBarMode.values) {
          mode.value = value;
          await tester.pumpAndSettle();
          final bottom =
              value == NavigationBarMode.bottom || width - inset * 2 < 600;
          expect(
            tester
                .widget<PredictiveBackRegion>(find.byType(PredictiveBackRegion))
                .enabled,
            bottom,
          );
          expect(
            find.byTooltip('返回播放'),
            bottom ? findsOneWidget : findsNothing,
          );
          expect(
            find.byTooltip('回到播放页'),
            bottom ? findsNothing : findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'navigation mode respects mobile space and retains content and sidebar choices',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final settings = ValueNotifier(const AppSettings.defaults());
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: BiliTheme.light(),
          home: ValueListenableBuilder(
            valueListenable: settings,
            builder: (_, value, _) => BiliAppShell(
              location: '/',
              navigationBarMode: value.navigationBarMode,
              sidebarStyle: value.sidebarStyle,
              sidebarCollapsed: value.sidebarCollapsed,
              child: const TextField(key: ValueKey('navigation-draft')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final draft = find.byKey(const ValueKey('navigation-draft'));
      final original = tester.element(draft);
      final platform = Theme.of(tester.element(draft)).platform;
      final mobile =
          platform == TargetPlatform.android || platform == TargetPlatform.iOS;
      await tester.enterText(draft, '导航切换保留草稿');
      for (final width in [320.0, 599.0, 600.0, 1280.0, 1600.0]) {
        tester.view.physicalSize = Size(width, 900);
        for (final mode in NavigationBarMode.values) {
          for (final style in SidebarStyle.values) {
            settings.value = AppSettings(
              navigationBarMode: mode,
              sidebarStyle: style,
            );
            await tester.pumpAndSettle();
            final bottom =
                mode == NavigationBarMode.bottom ||
                (width < 600 &&
                    (mobile || mode == NavigationBarMode.automatic));
            final expectedWidth = bottom
                ? 0.0
                : style == SidebarStyle.expanded ||
                      (style == SidebarStyle.automatic && width >= 1600)
                ? 164.0
                : 76.0;
            expect(tester.getSize(_sidebar).width, expectedWidth);
            expect(
              find.byType(NavigationBar),
              bottom ? findsOneWidget : findsNothing,
            );
            expect(
              tester
                  .widget<PrimaryNavigationTransition>(
                    find.byType(PrimaryNavigationTransition),
                  )
                  .enabled,
              bottom,
            );
            expect(_toggle, bottom ? findsNothing : findsOneWidget);
            expect(tester.element(draft), same(original));
            expect(find.text('导航切换保留草稿'), findsOneWidget);
            // Live remains grouped by page width, independently of bar placement.
            expect(
              find.byKey(const ValueKey('workspace-nav-live')),
              !bottom && width >= 600 ? findsOneWidget : findsNothing,
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '$width $mode $style',
            );
          }
        }
      }
      settings.value = AppSettings(
        navigationBarMode: NavigationBarMode.sidebar,
        sidebarStyle: SidebarStyle.expanded,
        sidebarCollapsed: true,
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(_sidebar).width, 0);
      expect(_toggle, findsOneWidget);
      settings.value = settings.value.copyWith(
        navigationBarMode: NavigationBarMode.bottom,
      );
      await tester.pumpAndSettle();
      settings.value = settings.value.copyWith(
        navigationBarMode: NavigationBarMode.sidebar,
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(_sidebar).width, 0);
      expect(settings.value.sidebarStyle, SidebarStyle.expanded);
      expect(tester.element(draft), same(original));
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.windows,
    }),
  );

  for (final workspaceMode in WorkspaceNavigationMode.values) {
    for (final failSave in [false, true]) {
      testWidgets(
        'navigation choices apply, reload or roll back: $workspaceMode failure=$failSave',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1280, 1000);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final repository = _SettingsRepository(workspaceMode)
            ..failSave = failSave;
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
          final container = ProviderScope.containerOf(tester.element(_sidebar));
          for (final (label, mode) in [
            ('底栏', NavigationBarMode.bottom),
            ('侧边栏', NavigationBarMode.sidebar),
            ('自动', NavigationBarMode.automatic),
          ]) {
            final choice = find.widgetWithText(ChoiceChip, label);
            await tester.ensureVisible(choice);
            await tester.pumpAndSettle();
            await tester.tap(choice);
            await tester.pumpAndSettle();
            final expected = failSave ? NavigationBarMode.automatic : mode;
            expect(repository.settings.navigationBarMode, expected);
            expect(
              find.byType(NavigationBar),
              expected == NavigationBarMode.bottom
                  ? findsOneWidget
                  : findsNothing,
            );
            expect(
              tester.getSize(_sidebar).width,
              expected == NavigationBarMode.bottom ? 0 : 76,
            );
            container.invalidate(settingsControllerProvider);
            await tester.pumpAndSettle();
            expect(
              container
                  .read(settingsControllerProvider)
                  .requireValue
                  .navigationBarMode,
              expected,
            );
            if (failSave && mode != NavigationBarMode.automatic) {
              expect(find.text('设置保存失败，请重试'), findsOneWidget);
            }
            expect(tester.takeException(), isNull);
          }
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
