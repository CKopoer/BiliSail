import 'dart:async';
import 'dart:convert';

import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/data/sqlite_settings_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

void main() {
  test(
    'old and invalid snapshots default to BiliSail; choices survive reload',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = SqliteSettingsRepository(database);
      for (final value in <Object?>[null, 'unknown', 1, true]) {
        await database.writeSetting(
          'preferences.v1',
          jsonEncode({'appIcon': value}),
        );
        expect((await repository.load()).appIcon, AppIconPreference.bilisail);
      }
      await repository.save(AppSettings(appIcon: AppIconPreference.bilibili));
      expect((await repository.load()).appIcon, AppIconPreference.bilibili);
      await repository.save(const AppSettings.defaults());
      expect((await repository.load()).appIcon, AppIconPreference.bilisail);
      expect(database.schemaVersion, 3);
    },
  );

  late _Icons icons;
  late _Repository repository;
  late ProviderContainer container;
  setUp(() {
    icons = _Icons();
    repository = _Repository();
    container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repository),
        appIconServiceProvider.overrideWithValue(icons),
      ],
    );
  });
  tearDown(() => container.dispose());

  test(
    'launch reconciles OS-retained mobile icon before publishing settings',
    () async {
      icons.restored = AppIconPreference.bilibili;
      final settings = await container.read(settingsControllerProvider.future);
      expect(settings.appIcon, AppIconPreference.bilibili);
      expect(repository.stored.appIcon, AppIconPreference.bilibili);
      expect(icons.applied, isEmpty);
    },
  );

  test(
    'icon restore failure leaves other settings usable and exposes retry',
    () async {
      icons.failRestore = true;
      expect(
        (await container.read(settingsControllerProvider.future)).theme,
        AppThemePreference.system,
      );
      expect(
        container.read(settingsControllerProvider.notifier).iconRestoreFailed,
        isTrue,
      );
    },
  );

  test(
    'OS change commits after save and keeps a concurrently edited theme',
    () async {
      await container.read(settingsControllerProvider.future);
      final controller = container.read(settingsControllerProvider.notifier);
      repository.pending = Completer<void>();
      final change = controller.setAppIcon(AppIconPreference.bilibili);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(settingsControllerProvider).requireValue.appIcon,
        AppIconPreference.bilisail,
      );
      final theme = controller.setTheme(AppThemePreference.dark);
      repository.pending!.complete();
      await Future.wait([change, theme]);
      expect(repository.stored.appIcon, AppIconPreference.bilibili);
      expect(repository.stored.theme, AppThemePreference.dark);
      expect(
        container.read(settingsControllerProvider).requireValue.appIcon,
        AppIconPreference.bilibili,
      );
      expect(icons.applied, [AppIconPreference.bilibili]);
    },
  );

  test(
    'failed save restores native icon; queued theme cannot resurrect it',
    () async {
      await container.read(settingsControllerProvider.future);
      final controller = container.read(settingsControllerProvider.notifier);
      repository.pending = Completer<void>();
      repository.failSave = true;
      final change = controller.setAppIcon(AppIconPreference.bilibili);
      final assertion = expectLater(change, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      final theme = controller.setTheme(AppThemePreference.dark);
      repository.pending!.complete();
      await assertion;
      await theme;
      expect(repository.stored.appIcon, AppIconPreference.bilisail);
      expect(repository.stored.theme, AppThemePreference.dark);
      expect(icons.applied, [
        AppIconPreference.bilibili,
        AppIconPreference.bilisail,
      ]);
      expect(
        container.read(settingsControllerProvider).requireValue.appIcon,
        AppIconPreference.bilisail,
      );
    },
  );

  test('native failure never commits preference and permits retry', () async {
    await container.read(settingsControllerProvider.future);
    final controller = container.read(settingsControllerProvider.notifier);
    icons.failApply = true;
    await expectLater(
      controller.setAppIcon(AppIconPreference.bilibili),
      throwsA(isA<Exception>()),
    );
    expect(repository.stored.appIcon, AppIconPreference.bilisail);
    await controller.setAppIcon(AppIconPreference.bilibili);
    expect(repository.stored.appIcon, AppIconPreference.bilibili);
    await controller.resetToDefaults();
    expect(repository.stored.appIcon, AppIconPreference.bilisail);
    expect(icons.applied.last, AppIconPreference.bilisail);
  });
}

class _Icons implements AppIconService {
  final applied = <AppIconPreference>[];
  AppIconPreference? restored;
  bool failRestore = false;
  bool failApply = false;
  @override
  AppIconSurface get surface => AppIconSurface.launcher;
  @override
  Future<AppIconPreference> restore(AppIconPreference saved) async {
    if (failRestore) throw Exception('unavailable');
    return restored ?? saved;
  }

  @override
  Future<void> apply(AppIconPreference icon) async {
    applied.add(icon);
    if (failApply) {
      failApply = false;
      throw Exception('unavailable');
    }
  }
}

class _Repository implements SettingsRepository {
  AppSettings stored = const AppSettings.defaults();
  Completer<void>? pending;
  bool failSave = false;
  @override
  Future<AppSettings> load() async => stored;
  @override
  Future<void> save(AppSettings settings) async {
    await pending?.future;
    if (failSave) {
      failSave = false;
      throw StateError('disk full');
    }
    stored = settings;
  }
}
