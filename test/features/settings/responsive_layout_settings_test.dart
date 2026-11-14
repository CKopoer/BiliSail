import 'dart:convert';

import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/domain/responsive_layout_settings.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/data/sqlite_settings_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'defaults, immutable overrides and invalid inputs retain safe rules',
    () {
      for (final settings in [AppSettings(), const AppSettings.defaults()]) {
        expect(settings.responsiveLayout.videoGridMinWidths, isNull);
        expect(settings.responsiveLayout.navigationBarBreakpoint, 600);
        expect(settings.responsiveLayout.sidebarExpandedWidth, 1600);
        expect(settings.responsiveLayout.playbackSideBySideWidth, 1000);
      }
      final source = [...ResponsiveLayoutSettings.defaultVideoGridMinWidths];
      final custom = ResponsiveLayoutSettings(videoGridMinWidths: source);
      source[0] = 9999;
      expect(custom.videoGridMinWidths?.first, 300);
      expect(
        () => custom.videoGridMinWidths?.add(4000),
        throwsUnsupportedError,
      );
      for (final invalid in [
        <int>[],
        [300, 400],
        [for (var i = 0; i < 11; i++) 300],
        [199, ...ResponsiveLayoutSettings.defaultVideoGridMinWidths.skip(1)],
        [...ResponsiveLayoutSettings.defaultVideoGridMinWidths.take(10), 12001],
      ]) {
        expect(
          ResponsiveLayoutSettings(videoGridMinWidths: invalid)
              .videoGridMinWidths,
          isNull,
        );
      }
      final invalid = ResponsiveLayoutSettings(
        navigationBarBreakpoint: 319,
        sidebarExpandedWidth: 599,
        playbackSideBySideWidth: 6001,
      );
      expect(invalid.navigationBarBreakpoint, 600);
      expect(invalid.sidebarExpandedWidth, 1600);
      expect(invalid.playbackSideBySideWidth, 1000);
      expect(custom.copyWith(resetVideoGrid: true).videoGridMinWidths, isNull);
    },
  );

  group('SQLite snapshots', () {
    late AppDatabase database;
    late SqliteSettingsRepository repository;
    setUp(() {
      database = AppDatabase(NativeDatabase.memory());
      repository = SqliteSettingsRepository(database);
    });
    tearDown(() => database.close());

    test('old sidebar thresholds are retained separately from the new navigation threshold', () async {
      final widths = [...ResponsiveLayoutSettings.defaultVideoGridMinWidths]
        ..[2] = 1000;
      await database.writeSetting(
        'preferences.v1',
        jsonEncode({
          'schemaVersion': 48,
          'theme': 'dark',
          'responsiveLayout': {
            'sidebarExpandedWidth': 1280,
            'videoGridMinWidths': widths,
            'playbackSideBySideWidth': 900,
          },
        }),
      );
      final loaded = await repository.load();
      expect(loaded.responsiveLayout.navigationBarBreakpoint, 600);
      expect(loaded.responsiveLayout.sidebarExpandedWidth, 1280);
      expect(loaded.responsiveLayout.videoGridMinWidths, widths);
      expect(loaded.responsiveLayout.playbackSideBySideWidth, 900);
      expect(loaded.theme, AppThemePreference.dark);
      await repository.save(loaded);
      final Object? raw = jsonDecode(
        (await database.readSetting('preferences.v1')) ?? '{}',
      );
      expect(
        raw,
        isA<Map<String, Object?>>().having(
          (map) => map['responsiveLayout'],
          'layout',
          isA<Map<String, Object?>>().having(
            (layout) => layout['sidebarExpandedWidth'],
            'sidebar threshold',
            1280,
          ),
        ),
      );
    });

    test(
      'old, malformed and partial snapshots preserve unrelated settings',
      () async {
        for (final raw in [
          null,
          'invalid',
          <String, Object?>{},
          {
            'videoGridMinWidths': [300, 300],
            'navigationBarBreakpoint': 319,
            'playbackSideBySideWidth': '900',
          },
          {
            'videoGridMinWidths': [
              300,
              492.5,
              ...ResponsiveLayoutSettings.defaultVideoGridMinWidths.skip(2),
            ],
            'navigationBarBreakpoint': 7000,
            'playbackSideBySideWidth': -1,
          },
        ]) {
          await database.writeSetting(
            'preferences.v1',
            jsonEncode({
              'schemaVersion': 47,
              'theme': 'dark',
              'responsiveLayout': raw,
            }),
          );
          final loaded = await repository.load();
          expect(loaded.theme, AppThemePreference.dark);
          expect(loaded.responsiveLayout.videoGridMinWidths, isNull);
          expect(loaded.responsiveLayout.navigationBarBreakpoint, 600);
          expect(loaded.responsiveLayout.playbackSideBySideWidth, 1000);
        }
        await database.writeSetting(
          'preferences.v1',
          jsonEncode({
            'responsiveLayout': {'navigationBarBreakpoint': 1280},
          }),
        );
        final partial = (await repository.load()).responsiveLayout;
        expect(partial.navigationBarBreakpoint, 1280);
        expect(partial.playbackSideBySideWidth, 1000);
        expect(partial.videoGridMinWidths, isNull);
      },
    );

    test(
      'custom settings round trip and defaults restore without a DB migration',
      () async {
        final widths = [...ResponsiveLayoutSettings.defaultVideoGridMinWidths]
          ..[2] = 1000;
        await repository.save(
          AppSettings(
            responsiveLayout: ResponsiveLayoutSettings(
              videoGridMinWidths: widths,
              navigationBarBreakpoint: 1280,
              sidebarExpandedWidth: 1800,
              playbackSideBySideWidth: 900,
            ),
          ),
        );
        final loaded = (await repository.load()).responsiveLayout;
        expect(loaded.videoGridMinWidths, widths);
        expect(loaded.navigationBarBreakpoint, 1280);
        expect(loaded.sidebarExpandedWidth, 1800);
        expect(loaded.playbackSideBySideWidth, 900);
        final Object? raw = jsonDecode(
          (await database.readSetting('preferences.v1')) ?? '{}',
        );
        expect(
          raw,
          isA<Map<String, Object?>>().having(
            (map) => map['schemaVersion'],
            'schema version',
            50,
          ),
        );
        expect(database.schemaVersion, 3);
        await repository.save(const AppSettings.defaults());
        expect(
          (await repository.load()).responsiveLayout.videoGridMinWidths,
          isNull,
        );
      },
    );
  });

  test(
    'controller merges queued edits, rolls back failed saves and resets',
    () async {
      final repository = _Repository();
      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);
      final controller = container.read(settingsControllerProvider.notifier);
      await Future.wait([
        controller.setNavigationBreakpoints(800, 1280),
        controller.setPlaybackSideBySideWidth(900),
        controller.setVideoGridMinWidths(
          [...ResponsiveLayoutSettings.defaultVideoGridMinWidths]..[2] = 1000,
        ),
      ]);
      expect(repository.value.responsiveLayout.navigationBarBreakpoint, 800);
      expect(repository.value.responsiveLayout.sidebarExpandedWidth, 1280);
      expect(repository.value.responsiveLayout.playbackSideBySideWidth, 900);
      expect(repository.value.responsiveLayout.videoGridMinWidths?[2], 1000);
      repository.fail = true;
      await expectLater(
        controller.setNavigationBreakpoints(1500, 1800),
        throwsStateError,
      );
      expect(
        container
            .read(settingsControllerProvider)
            .requireValue
            .responsiveLayout
            .navigationBarBreakpoint,
        800,
      );
      repository.fail = false;
      expect(
        container
            .read(settingsControllerProvider)
            .requireValue
            .responsiveLayout
            .sidebarExpandedWidth,
        1280,
      );
      await controller.setVideoGridMinWidths(null);
      expect(repository.value.responsiveLayout.videoGridMinWidths, isNull);
      expect(repository.value.responsiveLayout.playbackSideBySideWidth, 900);
      await controller.resetToDefaults();
      expect(repository.value.responsiveLayout.navigationBarBreakpoint, 600);
      expect(repository.value.responsiveLayout.sidebarExpandedWidth, 1600);
      expect(repository.value.responsiveLayout.playbackSideBySideWidth, 1000);
    },
  );
}

class _Repository implements SettingsRepository {
  AppSettings value = const AppSettings.defaults();
  bool fail = false;
  @override
  Future<AppSettings> load() async => value;
  @override
  Future<void> save(AppSettings settings) async {
    if (fail) throw StateError('save failed');
    value = settings;
  }
}
