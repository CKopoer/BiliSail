import 'dart:async';

import 'package:bili_lite/features/settings/application/settings_controller.dart';
import 'package:bili_lite/features/settings/domain/app_settings.dart';
import 'package:bili_lite/features/settings/domain/settings_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rapid changes remain visible and save in order', () async {
    final repository = _DeferredSettingsRepository();
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    final controller = container.read(settingsControllerProvider.notifier);

    final first = controller.setTheme(AppThemePreference.dark);
    final second = controller.setDanmakuEnabled(false);
    expect(
      container.read(settingsControllerProvider).asData?.value.theme,
      AppThemePreference.dark,
    );
    expect(
      container.read(settingsControllerProvider).asData?.value.danmakuEnabled,
      isFalse,
    );

    await Future<void>.delayed(Duration.zero);
    expect(repository.writes.length, 1);
    repository.completeNext();
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(repository.writes.length, 2);
    repository.completeNext();
    await second;

    expect(repository.stored.theme, AppThemePreference.dark);
    expect(repository.stored.danmakuEnabled, isFalse);
  });

  test('a failed earlier write does not block a newer setting', () async {
    final repository = _DeferredSettingsRepository();
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    final controller = container.read(settingsControllerProvider.notifier);

    final first = controller.setTheme(AppThemePreference.dark);
    final second = controller.setDanmakuEnabled(false);
    await Future<void>.delayed(Duration.zero);
    repository.failNext();
    await expectLater(first, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    expect(repository.writes.length, 2);
    repository.completeNext();
    await second;

    expect(repository.stored.theme, AppThemePreference.dark);
    expect(repository.stored.danmakuEnabled, isFalse);
    expect(
      container.read(settingsControllerProvider).asData?.value.danmakuEnabled,
      isFalse,
    );
  });

  test('failed latest write restores the last saved settings', () async {
    final repository = _DeferredSettingsRepository();
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    final controller = container.read(settingsControllerProvider.notifier);

    final first = controller.setTheme(AppThemePreference.dark);
    await Future<void>.delayed(Duration.zero);
    repository.completeNext();
    await first;

    final second = controller.setDanmakuEnabled(false);
    await Future<void>.delayed(Duration.zero);
    repository.failNext();
    await expectLater(second, throwsStateError);

    final visible = container.read(settingsControllerProvider).asData?.value;
    expect(visible?.theme, AppThemePreference.dark);
    expect(visible?.danmakuEnabled, isTrue);
  });
  test(
    'public update normalizes composite player preferences and persists them',
    () async {
      final repository = _DeferredSettingsRepository();
      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);
      final controller = container.read(settingsControllerProvider.notifier);
      final write = controller.update(
        (current) => current.copyWith(
          defaultVolume: -10,
          danmakuBlockedWords: [' x ', 'x'],
          subtitlesEnabled: true,
          sponsorBlockMode: SponsorBlockMode.manual,
        ),
      );
      final visible = container.read(settingsControllerProvider).requireValue;
      expect(visible.defaultVolume, 0);
      expect(visible.danmakuBlockedWords, ['x']);
      expect(visible.subtitlesEnabled, isTrue);
      expect(visible.sponsorBlockMode, SponsorBlockMode.manual);
      await Future<void>.delayed(Duration.zero);
      repository.completeNext();
      await write;
      container.invalidate(settingsControllerProvider);
      final reloaded = await container.read(settingsControllerProvider.future);
      expect(reloaded.defaultVolume, 0);
      expect(reloaded.danmakuBlockedWords, ['x']);
      expect(reloaded.sponsorBlockMode, SponsorBlockMode.manual);
    },
  );
}

final class _DeferredSettingsRepository implements SettingsRepository {
  AppSettings stored = const AppSettings.defaults();
  final writes = <AppSettings>[];
  final _completions = <Completer<void>>[];

  @override
  Future<AppSettings> load() async => stored;

  @override
  Future<void> save(AppSettings settings) {
    writes.add(settings);
    final completion = Completer<void>();
    _completions.add(completion);
    return completion.future.then((_) => stored = settings);
  }

  void completeNext() => _completions.removeAt(0).complete();
  void failNext() => _completions.removeAt(0).completeError(StateError('disk'));
}
