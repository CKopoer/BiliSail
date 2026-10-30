import 'dart:io';

import 'package:bilisail/core/platform/app_icon_service.dart';
import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/data/sqlite_settings_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/presentation/app_icon_settings.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'desktop icon selection reaches native runner and survives reload',
    (tester) async {
      if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = SqliteSettingsRepository(database);
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(repository),
          appIconServiceProvider.overrideWithValue(
            const NativeAppIconService(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.runAsync(
        () => container.read(settingsControllerProvider.future),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: AppNoticeHost.builder,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, child) {
                  final settings = ref
                      .watch(settingsControllerProvider)
                      .requireValue;
                  return AppIconSettings(value: settings.appIcon);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final television = find.widgetWithText(ChoiceChip, '粉红小电视');
      await tester.tap(television);
      for (var count = 0; count < 40; count++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
        if (container.read(settingsControllerProvider).requireValue.appIcon ==
            AppIconPreference.bilibili) {
          break;
        }
      }
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(television).selected, isTrue);
      expect(find.text('应用图标切换失败，请重试'), findsNothing);
      container.invalidate(settingsControllerProvider);
      final restored = await tester.runAsync(
        () => container.read(settingsControllerProvider.future),
      );
      expect(restored!.appIcon, AppIconPreference.bilibili);
      await tester.runAsync(
        () => container
            .read(settingsControllerProvider.notifier)
            .resetToDefaults(),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '哔帆'))
            .selected,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
