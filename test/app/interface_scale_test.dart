import 'dart:convert';

import 'package:bilisail/app/interface_scale.dart';
import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/data/sqlite_settings_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/presentation/settings_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/memory_settings_repository.dart';

void main() {
  test(
    'manual scale survives unrelated writes and resets to automatic',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = SqliteSettingsRepository(database);
      for (final value in [null, '150', -1, 0, 777]) {
        await database.writeSetting(
          'preferences.v1',
          jsonEncode({
            'schemaVersion': 56,
            'theme': 'dark',
            'interfaceScalePercent': ?value,
          }),
        );
        final loaded = await repository.load();
        expect(loaded.theme, AppThemePreference.dark);
        expect(loaded.interfaceScale, InterfaceScalePreference.automatic);
      }
      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);
      final settings = container.read(settingsControllerProvider.notifier);
      for (final scale in InterfaceScalePreference.values) {
        await settings.setInterfaceScale(scale);
        await settings.setTheme(AppThemePreference.light);
        expect((await repository.load()).interfaceScale, scale);
      }
      await settings.resetToDefaults();
      expect(
        (await repository.load()).interfaceScale,
        InterfaceScalePreference.automatic,
      );
    },
  );

  testWidgets('appearance changes scale in place and restores automatic', (
    tester,
  ) async {
    final repository = MemorySettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
        child: const InterfaceScale(
          child: MaterialApp(home: Scaffold(body: SettingsScreen())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final section = find
        .ancestor(of: find.text('界面缩放'), matching: find.byType(Column))
        .first;
    Finder choice(String label) => find.descendant(
      of: section,
      matching: find.widgetWithText(ChoiceChip, label),
    );
    final screen = find.byType(SettingsScreen);
    final state = tester.state(screen);
    for (final (label, scale) in [
      ('150%', InterfaceScalePreference.percent150),
      ('自动', InterfaceScalePreference.automatic),
    ]) {
      final chip = choice(label);
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect((await repository.load()).interfaceScale, scale);
      expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
      expect(tester.state(screen), same(state));
    }
  });

  testWidgets(
    'layout, paint, hits and insets use the same scale across changes',
    (tester) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.viewInsets = const FakeViewPadding(bottom: 120);
      addTearDown(tester.view.reset);
      final repository = MemorySettingsRepository();
      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final key = GlobalKey();
      var hits = 0;
      late MediaQueryData media;
      late BoxConstraints layout;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: InterfaceScale(
            automaticFactor: 1.5,
            child: LayoutBuilder(
              builder: (context, constraints) {
                media = MediaQuery.of(context);
                layout = constraints;
                return Stack(
                  alignment: Alignment.topLeft,
                  children: [
                    Positioned(
                      left: 100,
                      top: 60,
                      width: 40,
                      height: 20,
                      child: GestureDetector(
                        key: key,
                        behavior: HitTestBehavior.opaque,
                        onTap: () => hits++,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final original = key.currentContext;
      final settings = container.read(settingsControllerProvider.notifier);
      for (final (preference, factor) in [
        (InterfaceScalePreference.automatic, 1.5),
        (InterfaceScalePreference.percent100, 1.0),
        (InterfaceScalePreference.percent75, 0.75),
        (InterfaceScalePreference.percent200, 2.0),
        (InterfaceScalePreference.automatic, 1.5),
      ]) {
        await settings.setInterfaceScale(preference);
        await tester.pumpAndSettle();
        expect(key.currentContext, same(original));
        expect(layout.biggest, const Size(600, 400) / factor);
        expect(media.size, layout.biggest);
        expect(media.devicePixelRatio, 2 * factor);
        expect(media.viewInsets.bottom, 60 / factor);
        final box = key.currentContext!.findRenderObject()! as RenderBox;
        expect(box.localToGlobal(Offset.zero), const Offset(100, 60) * factor);
        expect(
          box.localToGlobal(const Offset(40, 20)),
          const Offset(140, 80) * factor,
        );
        final previous = hits;
        await tester.tapAt(const Offset(120, 70) * factor);
        await tester.tapAt(const Offset(142, 82) * factor);
        expect(hits, previous + 1);
      }
      repository.failWrites = true;
      await expectLater(
        settings.setInterfaceScale(InterfaceScalePreference.percent125),
        throwsStateError,
      );
      await tester.pumpAndSettle();
      expect(media.devicePixelRatio, 3);
    },
  );
}
