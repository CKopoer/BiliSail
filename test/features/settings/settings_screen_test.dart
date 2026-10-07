import 'package:bilisail/app/theme.dart';
import 'package:bilisail/features/playback/presentation/player_settings_dialog.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_category.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:bilisail/features/settings/presentation/settings_screen.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final inPlayer in [false, true]) {
    testWidgets('player control modes save and reload (player: $inPlayer)', (
      tester,
    ) async {
      final repository = _SettingsRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            home: Scaffold(
              body: inPlayer
                  ? Builder(
                      builder: (context) => ElevatedButton(
                        onPressed: () => showPlayerSettings(context),
                        child: const Text('播放配置'),
                      ),
                    )
                  : const SettingsScreen(category: SettingsCategory.playback),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (inPlayer) {
        await tester.tap(find.text('播放配置'));
        await tester.pumpAndSettle();
      }
      final click = find.widgetWithText(ChoiceChip, '点击');
      final dynamic = find.widgetWithText(ChoiceChip, '动态');
      expect(tester.widget<ChoiceChip>(click).selected, isTrue);
      for (final (choice, mode) in [
        (dynamic, PlayerControlsMode.dynamic),
        (click, PlayerControlsMode.click),
      ]) {
        await tester.ensureVisible(choice);
        await tester.tap(choice);
        await tester.pumpAndSettle();
        expect(repository.settings.playerControlsMode, mode);
        final container = ProviderScope.containerOf(tester.element(choice));
        container.invalidate(settingsControllerProvider);
        await tester.pumpAndSettle();
        expect(tester.widget<ChoiceChip>(choice).selected, isTrue);
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('playback CDN choices persist and default to automatic', (
    tester,
  ) async {
    final repository = _SettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: Scaffold(
            body: SettingsScreen(category: SettingsCategory.playback),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final (label, preference) in [
      ('优先常规 CDN', MediaCdnPreference.regular),
      ('优先腾讯云', MediaCdnPreference.tencent),
      ('自动（默认）', MediaCdnPreference.automatic),
    ]) {
      final choice = find.widgetWithText(ChoiceChip, label);
      await tester.ensureVisible(choice);
      await tester.pumpAndSettle();
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(repository.settings.mediaCdn, preference);
      expect(tester.widget<ChoiceChip>(choice).selected, true);
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets('appearance saves each navigation mode', (tester) async {
    final repository = _SettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, '自动'), findsNothing);
    for (final (label, mode) in [
      ('单标签页', WorkspaceNavigationMode.singlePage),
      ('多标签页', WorkspaceNavigationMode.multipleTabs),
    ]) {
      await tester.tap(find.widgetWithText(ChoiceChip, label));
      await tester.pumpAndSettle();
      expect(repository.settings.navigationMode, mode);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label))
            .selected,
        isTrue,
      );
    }
  });
  for (final mode in WorkspaceNavigationMode.values) {
    testWidgets(
      'concurrent playback switch respects ${mode.name} and retains its choice',
      (tester) async {
        final repository = _SettingsRepository()
          ..settings = AppSettings.defaults(navigationMode: mode);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsRepositoryProvider.overrideWithValue(repository),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: SettingsScreen(category: SettingsCategory.playback),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final toggle = find.widgetWithText(SwitchListTile, '允许多个标签页同时播放');
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
        expect(
          tester.widget<SwitchListTile>(toggle).onChanged != null,
          mode == WorkspaceNavigationMode.multipleTabs,
        );
        final container = ProviderScope.containerOf(
          tester.element(toggle),
          listen: false,
        );
        final controller = container.read(settingsControllerProvider.notifier);
        if (mode == WorkspaceNavigationMode.singlePage) {
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(repository.settings.allowConcurrentPlayback, isTrue);
          await controller.setNavigationMode(
            WorkspaceNavigationMode.multipleTabs,
          );
          await tester.pumpAndSettle();
        }
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(repository.settings.allowConcurrentPlayback, isFalse);
        await controller.setNavigationMode(WorkspaceNavigationMode.singlePage);
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
        expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
        await controller.setNavigationMode(
          WorkspaceNavigationMode.multipleTabs,
        );
        await tester.pumpAndSettle();
        container.invalidate(settingsControllerProvider);
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(toggle).onChanged, isNotNull);
        expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final inPlayer in [false, true]) {
    testWidgets(
      'row gap defaults to five and saves zero without a switch (player: $inPlayer)',
      (tester) async {
        final repository = _SettingsRepository();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsRepositoryProvider.overrideWithValue(repository),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: inPlayer
                    ? Builder(
                        builder: (context) => ElevatedButton(
                          onPressed: () => showPlayerSettings(context, tab: 1),
                          child: const Text('弹幕配置'),
                        ),
                      )
                    : const SettingsScreen(category: SettingsCategory.danmaku),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (inPlayer) {
          await tester.tap(find.text('弹幕配置'));
          await tester.pumpAndSettle();
        }
        final toggle = find.widgetWithText(SwitchListTile, '使用默认弹幕行距');
        final slider = find.descendant(
          of: find.byKey(const ValueKey('danmaku-line-spacing')),
          matching: find.byType(Slider),
        );
        expect(toggle, findsNothing);
        await tester.ensureVisible(slider);
        await tester.pumpAndSettle();
        expect(repository.settings.danmakuLineSpacing, 5);
        expect(tester.widget<Slider>(slider).value, 5);
        expect(tester.widget<Slider>(slider).min, 0);
        final rect = tester.getRect(slider);
        final gesture = await tester.startGesture(
          Offset(rect.left + 24, rect.center.dy),
        );
        await gesture.moveTo(
          Offset(rect.left + rect.width * .4, rect.center.dy),
        );
        await gesture.up();
        await tester.pumpAndSettle();
        final saved = repository.settings.danmakuLineSpacing;
        expect(saved, inExclusiveRange(0, 100));
        if (inPlayer) {
          await tester.tap(find.byTooltip('关闭'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('弹幕配置'));
          await tester.pumpAndSettle();
        } else {
          ProviderScope.containerOf(
            tester.element(slider),
            listen: false,
          ).invalidate(settingsControllerProvider);
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(slider);
        await tester.pumpAndSettle();
        expect(tester.widget<Slider>(slider).value, saved);
        final zeroRect = tester.getRect(slider);
        await tester.tapAt(Offset(zeroRect.left + 24, zeroRect.center.dy));
        await tester.pumpAndSettle();
        expect(repository.settings.danmakuLineSpacing, 0);
        expect(tester.widget<Slider>(slider).value, 0);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets('top margin slider saves 4-pixel steps (player: $inPlayer)', (
      tester,
    ) async {
      final repository = _SettingsRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            home: Scaffold(
              body: inPlayer
                  ? Builder(
                      builder: (context) => ElevatedButton(
                        onPressed: () => showPlayerSettings(context, tab: 1),
                        child: const Text('弹幕配置'),
                      ),
                    )
                  : const SettingsScreen(category: SettingsCategory.danmaku),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (inPlayer) {
        await tester.tap(find.text('弹幕配置'));
        await tester.pumpAndSettle();
      }
      final slider = find.byWidgetPredicate(
        (widget) => widget is Slider && widget.min == 0 && widget.max == 200,
      );
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(slider).value, 0);
      expect(tester.widget<Slider>(slider).divisions, 50);
      final rect = tester.getRect(slider);
      final gesture = await tester.startGesture(
        Offset(rect.left + 24, rect.center.dy),
      );
      await gesture.moveTo(Offset(rect.left + rect.width * .4, rect.center.dy));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(repository.settings.danmakuTopMargin, inExclusiveRange(0, 200));
      expect(repository.settings.danmakuTopMargin % 4, 0);
      expect(
        tester.widget<Slider>(slider).value,
        repository.settings.danmakuTopMargin,
      );
      if (inPlayer) {
        await tester.tap(find.byTooltip('关闭'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('弹幕配置'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(slider);
        await tester.pumpAndSettle();
        expect(
          tester.widget<Slider>(slider).value,
          repository.settings.danmakuTopMargin,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('codec and decoding choices save in a narrow playback page', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repository = _SettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: Scaffold(
            body: SettingsScreen(category: SettingsCategory.playback),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final (label, codec) in const [
      ('H.265 / HEVC', VideoCodecPreference.hevc),
      ('AV1', VideoCodecPreference.av1),
    ]) {
      final choice = find.widgetWithText(ChoiceChip, label);
      await tester.ensureVisible(choice);
      await tester.pumpAndSettle();
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(repository.settings.preferredVideoCodec, codec);
      expect(tester.widget<ChoiceChip>(choice).selected, isTrue);
    }
    final software = find.widgetWithText(ChoiceChip, '软件解码');
    await tester.ensureVisible(software);
    await tester.pumpAndSettle();
    await tester.tap(software);
    await tester.pumpAndSettle();
    expect(repository.settings.videoDecoding, VideoDecodingPreference.software);
    expect(tester.widget<ChoiceChip>(software).selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('default volume saves a continuous dragged value', (
    tester,
  ) async {
    final repository = _SettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: Scaffold(
            body: SettingsScreen(category: SettingsCategory.playback),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final slider = find.byType(Slider);
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(slider).divisions, isNull);
    final rect = tester.getRect(slider);
    final gesture = await tester.startGesture(rect.center);
    await gesture.moveTo(Offset(rect.left + rect.width * .38, rect.center.dy));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(repository.settings.defaultVolume, inExclusiveRange(25, 50));
    expect(
      repository.settings.defaultVolume,
      isNot(repository.settings.defaultVolume.roundToDouble()),
    );
    expect(
      tester.widget<Slider>(slider).value,
      repository.settings.defaultVolume,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('cache category exposes persisted image toggle', (tester) async {
    final repository = _SettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: Scaffold(
            body: SettingsScreen(category: SettingsCategory.cache),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('缓存图片'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(repository.settings.cacheImages, isFalse);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
  });
  testWidgets(
    'appearance offers the bundled default font and persists system font',
    (tester) async {
      final repository = _SettingsRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'HarmonyOS Sans'),
            )
            .selected,
        isTrue,
      );
      expect(find.text('自动播放'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, '系统默认'));
      await tester.pumpAndSettle();
      expect(repository.settings.font, AppFontPreference.system);
      expect(
        BiliTheme.light().textTheme.bodyMedium?.fontFamily,
        'HarmonyOS Sans',
      );
      expect(
        BiliTheme.dark().textTheme.bodyMedium?.fontFamily,
        'HarmonyOS Sans',
      );
      expect(
        BiliTheme.light(font: repository.settings.font)
            .textTheme
            .bodyMedium
            ?.fontFamily,
        isNot('HarmonyOS Sans'),
      );
    },
  );
  testWidgets('default playback speed uses fixed choices including 3.0x', (
    tester,
  ) async {
    final repository = _SettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: Scaffold(
            body: SettingsScreen(category: SettingsCategory.playback),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final rate = find.widgetWithText(ChoiceChip, '3.0x');
    await tester.ensureVisible(rate);
    await tester.pumpAndSettle();
    await tester.tap(rate);
    await tester.pumpAndSettle();
    expect(repository.settings.defaultPlaybackRate, 3);
    expect(tester.widget<ChoiceChip>(rate).selected, isTrue);
    expect(find.widgetWithText(ChoiceChip, '1.75x'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('theme choices wrap at large text and still save changes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repository = _SettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          builder: AppNoticeHost.builder,
          theme: BiliTheme.light(),
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(body: SettingsScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final darkChoice = find.widgetWithText(ChoiceChip, '深色');
    await tester.ensureVisible(darkChoice);
    await tester.tap(darkChoice);
    await tester.pumpAndSettle();
    expect(repository.settings.theme, AppThemePreference.dark);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed save rolls back visible preference and shows feedback', (
    tester,
  ) async {
    final repository = _SettingsRepository()..failSave = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          builder: AppNoticeHost.builder,
          home: const Scaffold(body: SettingsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '深色'));
    await tester.pumpAndSettle();
    expect(repository.settings.theme, AppThemePreference.system);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '跟随系统'))
          .selected,
      isTrue,
    );
    expect(find.text('设置保存失败，请重试'), findsOneWidget);
  });
}

final class _SettingsRepository implements SettingsRepository {
  AppSettings settings = const AppSettings.defaults();
  bool failSave = false;

  @override
  Future<AppSettings> load() async => settings;

  @override
  Future<void> save(AppSettings value) async {
    if (failSave) throw StateError("disk");
    settings = value;
  }
}
