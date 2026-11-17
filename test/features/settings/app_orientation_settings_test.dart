import 'dart:convert';

import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/core/presentation/window_orientation_host.dart';
import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/data/sqlite_settings_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_category.dart';
import 'package:bilisail/features/settings/presentation/settings_screen.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_settings_repository.dart';

void main() {
  test(
    'orientation defaults, old snapshots and invalid values stay automatic',
    () async {
      expect(AppSettings().orientation, AppOrientationPreference.automatic);
      expect(
        const AppSettings.defaults().orientation,
        AppOrientationPreference.automatic,
      );
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = SqliteSettingsRepository(database);
      expect(
        (await repository.load()).orientation,
        AppOrientationPreference.automatic,
      );
      for (final snapshot in [
        {'schemaVersion': 52},
        for (final invalid in [null, true, 1, 'unknown', <String>[]])
          {'schemaVersion': 53, 'orientation': invalid},
      ]) {
        await database.writeSetting(
          'preferences.v1',
          jsonEncode({
            ...snapshot,
            'theme': 'dark',
            'navigationMode': 'singlePage',
          }),
        );
        final loaded = await repository.load();
        expect(loaded.orientation, AppOrientationPreference.automatic);
        expect(loaded.theme, AppThemePreference.dark);
        expect(loaded.navigationMode, WorkspaceNavigationMode.singlePage);
      }
      expect(database.schemaVersion, 3);
    },
  );

  test(
    'every orientation survives saving, unrelated edits, reload and reset',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = SqliteSettingsRepository(database);
      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);
      for (final orientation in AppOrientationPreference.values) {
        await container
            .read(settingsControllerProvider.notifier)
            .setOrientation(orientation);
        await container
            .read(settingsControllerProvider.notifier)
            .setTheme(AppThemePreference.dark);
        final restored = await SqliteSettingsRepository(database).load();
        expect(restored.orientation, orientation);
        expect(
          restored.copyWith(cacheImages: false).normalized().orientation,
          orientation,
        );
        container.invalidate(settingsControllerProvider);
        expect(
          (await container.read(settingsControllerProvider.future)).orientation,
          orientation,
        );
      }
      final snapshot = jsonDecode(
        (await database.readSetting('preferences.v1'))!,
      ) as Map<String, Object?>;
      expect(snapshot['schemaVersion'], 53);
      expect(snapshot['orientation'], 'landscape');
      await container
          .read(settingsControllerProvider.notifier)
          .resetToDefaults();
      expect(
        (await repository.load()).orientation,
        AppOrientationPreference.automatic,
      );
    },
  );

  testWidgets(
    'mobile choices apply, reload, roll back failed saves and reset',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.display.size = const Size(390, 844);
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.display.resetSize);
      addTearDown(tester.view.resetPhysicalSize);
      final applied = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            applied.add(call.arguments);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final repository = MemorySettingsRepository();
      final window = _MobileWindow();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
          child: Consumer(
            builder: (context, ref, child) {
              final settings =
                  ref.watch(settingsControllerProvider).value ??
                  const AppSettings.defaults();
              return MaterialApp(
                builder: (context, child) => WindowOrientationHost(
                  window: window,
                  orientation: settings.orientation,
                  child: AppNoticeHost(child: child!),
                ),
                home: const Scaffold(
                  body: SettingsScreen(category: SettingsCategory.appearance),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('应用方向'), findsOneWidget);
      final landscape = find.widgetWithText(ChoiceChip, '横屏');
      final portrait = find.widgetWithText(ChoiceChip, '竖屏');
      final page = tester.state(find.byType(SettingsScreen));
      final container = ProviderScope.containerOf(tester.element(landscape));
      await tester.ensureVisible(landscape);
      await tester.tap(landscape);
      await tester.pumpAndSettle();
      expect(repository.value.orientation, AppOrientationPreference.landscape);
      expect(applied.last, [
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ]);
      container.invalidate(settingsControllerProvider);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(landscape).selected, isTrue);
      expect(tester.state(find.byType(SettingsScreen)), same(page));
      repository.failWrites = true;
      await tester.ensureVisible(portrait);
      await tester.tap(portrait);
      await tester.pumpAndSettle();
      expect(find.text('设置保存失败，请重试'), findsOneWidget);
      expect(tester.widget<ChoiceChip>(landscape).selected, isTrue);
      expect(repository.value.orientation, AppOrientationPreference.landscape);
      expect(applied.last, [
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ]);
      repository.failWrites = false;
      await tester.tap(portrait);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(portrait).selected, isTrue);
      expect(applied.last, ['DeviceOrientation.portraitUp']);
      await container
          .read(settingsControllerProvider.notifier)
          .resetToDefaults();
      await tester.pumpAndSettle();
      expect(repository.value.orientation, AppOrientationPreference.automatic);
      expect(tester.widget<ChoiceChip>(portrait).selected, isFalse);
      expect(window.allowsAutomaticRotation, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(applied.last, isEmpty);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'desktop direction choices default to automatic and persist',
    (tester) async {
      final repository = MemorySettingsRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
            home: Scaffold(
              body: SettingsScreen(category: SettingsCategory.appearance),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('应用方向'), findsOneWidget);
      final automatic = find.widgetWithText(ChoiceChip, '自动').first;
      expect(tester.widget<ChoiceChip>(automatic).selected, isTrue);
      for (final (label, orientation) in [
        ('竖屏', AppOrientationPreference.portrait),
        ('横屏', AppOrientationPreference.landscape),
        ('自动', AppOrientationPreference.automatic),
      ]) {
        final choice = find.widgetWithText(ChoiceChip, label).first;
        await tester.ensureVisible(choice);
        await tester.tap(choice);
        await tester.pumpAndSettle();
        expect(repository.value.orientation, orientation);
        expect(tester.widget<ChoiceChip>(choice).selected, isTrue);
      }
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    }),
  );
}

class _MobileWindow extends WindowService {
  @override
  bool get hasDesktopWindow => false;
}
