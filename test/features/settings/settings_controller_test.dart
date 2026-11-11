import 'dart:async';

import 'package:bilisail/features/settings/domain/shortcut_settings.dart';

import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'sponsor button distance saves, reloads and rolls back a failed save',
    () async {
      final repository = _DeferredSettingsRepository();
      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);
      final controller = container.read(settingsControllerProvider.notifier);
      final save = controller.setSponsorBlockBottomPadding(180);
      await Future<void>.delayed(Duration.zero);
      repository.completeNext();
      await save;
      container.invalidate(settingsControllerProvider);
      expect(
        (await container.read(settingsControllerProvider.future))
            .sponsorBlockBottomPadding,
        180,
      );
      final failed = container
          .read(settingsControllerProvider.notifier)
          .setSponsorBlockBottomPadding(40);
      final assertion = expectLater(failed, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      repository.failNext();
      await assertion;
      expect(
        container
            .read(settingsControllerProvider)
            .requireValue
            .sponsorBlockBottomPadding,
        180,
      );
      expect(repository.stored.sponsorBlockBottomPadding, 180);
    },
  );
  test('global send style queues with other settings, rolls back failures and resets', () async {
    final repository = _DeferredSettingsRepository();
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    final controller = container.read(settingsControllerProvider.notifier);
    const chosen = (mode: 5, color: 0x123456, colorful: false);
    final style = controller.setDanmakuSendStyle(chosen);
    final theme = controller.setTheme(AppThemePreference.dark);
    await Future<void>.delayed(Duration.zero);
    repository.completeNext();
    await style;
    await Future<void>.delayed(Duration.zero);
    repository.completeNext();
    await theme;
    expect(repository.stored.danmakuSendStyle, chosen);
    expect(repository.stored.theme, AppThemePreference.dark);
    final failed = controller.setDanmakuSendStyle((
      mode: 4,
      color: 1,
      colorful: false,
    ));
    final assertion = expectLater(failed, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    repository.failNext();
    await assertion;
    expect(
      container.read(settingsControllerProvider).requireValue.danmakuSendStyle,
      chosen,
    );
    final reset = controller.resetToDefaults();
    await Future<void>.delayed(Duration.zero);
    repository.completeNext();
    await reset;
    expect(repository.stored.danmakuSendStyle, (
      mode: 1,
      color: 0xffffff,
      colorful: false,
    ));
  });

  test('failed reset restores saved settings and never activates default shortcuts', () async {
    final custom = const AppSettings.defaults().copyWith(
      theme: AppThemePreference.dark,
      shortcuts: const ShortcutSettings.defaults().withEnabled(false),
    );
    final repository = _DeferredSettingsRepository()..stored = custom;
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    final controller = container.read(settingsControllerProvider.notifier);

    final reset = controller.resetToDefaults();
    final assertion = expectLater(reset, throwsStateError);
    expect(
      container.read(settingsControllerProvider).requireValue.shortcuts.enabled,
      isFalse,
    );
    await Future<void>.delayed(Duration.zero);
    repository.failNext();
    await assertion;
    expect(
      container.read(settingsControllerProvider).requireValue,
      same(custom),
    );
    expect(repository.stored, same(custom));

    final retry = controller.resetToDefaults();
    await Future<void>.delayed(Duration.zero);
    repository.completeNext();
    await retry;
    expect(
      container.read(settingsControllerProvider).requireValue.theme,
      AppThemePreference.system,
    );
    expect(
      container.read(settingsControllerProvider).requireValue.shortcuts.enabled,
      isTrue,
    );
  });

  test(
    'reset overrides an earlier shortcut save and preserves later settings',
    () async {
      final repository = _DeferredSettingsRepository();
      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);
      final controller = container.read(settingsControllerProvider.notifier);
      final shortcut = controller.setShortcuts(
        const ShortcutSettings.defaults().withEnabled(false),
      );
      await Future<void>.delayed(Duration.zero);
      final reset = controller.resetToDefaults();
      final theme = controller.setTheme(AppThemePreference.dark);
      repository.completeNext();
      await shortcut;
      await Future<void>.delayed(Duration.zero);
      expect(
        container
            .read(settingsControllerProvider)
            .requireValue
            .shortcuts
            .enabled,
        isFalse,
      );
      repository.completeNext();
      await reset;
      expect(
        container
            .read(settingsControllerProvider)
            .requireValue
            .shortcuts
            .enabled,
        isTrue,
      );
      expect(
        container.read(settingsControllerProvider).requireValue.theme,
        AppThemePreference.dark,
      );
      await Future<void>.delayed(Duration.zero);
      repository.completeNext();
      await theme;
      expect(repository.stored.theme, AppThemePreference.dark);
      expect(
        repository.stored.shortcuts.toJson(),
        const ShortcutSettings.defaults().toJson(),
      );
    },
  );

  test(
    'appearance queued after reset cannot restore old shortcut bindings',
    () async {
      final repository = _DeferredSettingsRepository()
        ..stored = const AppSettings.defaults().copyWith(
          shortcuts: const ShortcutSettings.defaults().withEnabled(false),
        );
      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);
      final controller = container.read(settingsControllerProvider.notifier);
      final reset = controller.resetToDefaults();
      final theme = controller.setTheme(AppThemePreference.dark);
      await Future<void>.delayed(Duration.zero);
      repository.completeNext();
      await reset;
      await Future<void>.delayed(Duration.zero);
      repository.completeNext();
      await theme;
      expect(repository.stored.shortcuts.enabled, isTrue);
      expect(repository.stored.theme, AppThemePreference.dark);
      expect(
        container
            .read(settingsControllerProvider)
            .requireValue
            .shortcuts
            .enabled,
        isTrue,
      );
    },
  );

  test(
    'wheel damping updates live, queues saves and rolls back failures',
    () async {
      final repository = _DeferredSettingsRepository();
      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);
      final controller = container.read(settingsControllerProvider.notifier);
      final ratio = controller.setWheelDampingRatio(1.55);
      final theme = controller.setTheme(AppThemePreference.dark);
      expect(
        container
            .read(settingsControllerProvider)
            .requireValue
            .wheelDampingRatio,
        1.55,
      );
      await Future<void>.delayed(Duration.zero);
      repository.completeNext();
      await ratio;
      await Future<void>.delayed(Duration.zero);
      repository.completeNext();
      await theme;
      container.invalidate(settingsControllerProvider);
      final loaded = await container.read(settingsControllerProvider.future);
      expect(loaded.wheelDampingRatio, 1.55);
      expect(loaded.theme, AppThemePreference.dark);

      final failure = controller.setWheelDampingRatio(.5);
      final assertion = expectLater(failure, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      repository.failNext();
      await assertion;
      expect(
        container
            .read(settingsControllerProvider)
            .requireValue
            .wheelDampingRatio,
        1.55,
      );
    },
  );

  test('queued live and video quality changes persist independently', () async {
    final repository = _DeferredSettingsRepository();
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    final controller = container.read(settingsControllerProvider.notifier);
    final live = controller.setPreferredLiveQuality(0);
    final video = controller.setPreferredQuality(120);
    final visible = container.read(settingsControllerProvider).requireValue;
    expect(visible.preferredLiveQuality, 0);
    expect(visible.preferredQuality, 120);
    await Future<void>.delayed(Duration.zero);
    repository.completeNext();
    await live;
    await Future<void>.delayed(Duration.zero);
    repository.completeNext();
    await video;
    container.invalidate(settingsControllerProvider);
    final reloaded = await container.read(settingsControllerProvider.future);
    expect(reloaded.preferredLiveQuality, 0);
    expect(reloaded.preferredQuality, 120);
  });
  test(
    'shortcut configuration becomes active only after a successful save',
    () async {
      final repository = _DeferredSettingsRepository();
      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);
      final controller = container.read(settingsControllerProvider.notifier);
      final custom = const ShortcutSettings.defaults().withKeys(
        ShortcutAction.closeTab,
        ['MouseBack'],
      );
      final failed = controller.setShortcuts(custom);
      final assertion = expectLater(failed, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      expect(
        container
            .read(settingsControllerProvider)
            .requireValue
            .shortcuts
            .keysFor(ShortcutAction.closeTab),
        ['Ctrl+W', 'MouseBack'],
      );
      repository.failNext();
      await assertion;
      final success = controller.setShortcuts(custom);
      await Future<void>.delayed(Duration.zero);
      expect(
        container
            .read(settingsControllerProvider)
            .requireValue
            .shortcuts
            .keysFor(ShortcutAction.closeTab),
        ['Ctrl+W', 'MouseBack'],
      );
      repository.completeNext();
      await success;
      expect(
        container
            .read(settingsControllerProvider)
            .requireValue
            .shortcuts
            .keysFor(ShortcutAction.closeTab),
        ['MouseBack'],
      );
    },
  );

  test(
    'queued appearance save retains newly committed shortcut configuration',
    () async {
      final repository = _DeferredSettingsRepository();
      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);
      final controller = container.read(settingsControllerProvider.notifier);
      final shortcut = controller.setShortcuts(
        const ShortcutSettings.defaults().withKeys(ShortcutAction.closeTab, [
          'MouseBack',
        ]),
      );
      await Future<void>.delayed(Duration.zero);
      final theme = controller.setTheme(AppThemePreference.dark);
      repository.completeNext();
      await shortcut;
      await Future<void>.delayed(Duration.zero);
      repository.completeNext();
      await theme;
      expect(repository.stored.shortcuts.keysFor(ShortcutAction.closeTab), [
        'MouseBack',
      ]);
      expect(repository.stored.theme, AppThemePreference.dark);
    },
  );
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
