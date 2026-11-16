import 'package:bilisail/features/playback/presentation/player_settings_dialog.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/desktop_windowing.dart';

final class _Settings implements SettingsRepository {
  AppSettings value = AppSettings();
  @override
  Future<AppSettings> load() async => value;
  @override
  Future<void> save(AppSettings settings) async {
    value = settings;
  }
}

void main() {
  testWidgets(
    'player settings expose all modes and save without resetting volume',
    (tester) async {
      enableDesktopWindowing(tester);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = _Settings()..value = AppSettings(defaultVolume: 35.5);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsRepositoryProvider.overrideWithValue(settings)],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showPlayerSettings(context),
                  child: const Text('打开设置'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开设置'));
      await tester.pumpAndSettle();
      final dropdown = find.byKey(const ValueKey('player-audio-normalization'));
      await tester.scrollUntilVisible(
        dropdown,
        160,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      for (final mode in AudioNormalizationMode.values) {
        await Scrollable.ensureVisible(tester.element(dropdown), alignment: .5);
        await tester.pumpAndSettle();
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text(mode.label).last);
        await tester.pumpAndSettle();
        expect(settings.value.audioNormalization, mode);
        expect(settings.value.defaultVolume, 35.5);
        expect(
          tester.widget<DropdownButton<AudioNormalizationMode>>(dropdown).value,
          mode,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
}
