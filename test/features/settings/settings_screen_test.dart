import 'package:bilisail/app/theme.dart';
import 'package:bilisail/features/playback/presentation/player_settings_dialog.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_category.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:bilisail/features/settings/presentation/settings_screen.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final failSave in [false, true]) {
    testWidgets(
      'global volume memory retains defaults and rolls back on failure: $failSave',
      (tester) async {
        final repository = _SettingsRepository()
          ..settings = AppSettings(defaultVolume: 35.5)
          ..failSave = failSave;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsRepositoryProvider.overrideWithValue(repository),
            ],
            child: MaterialApp(
              builder: AppNoticeHost.builder,
              home: const Scaffold(
                body: SettingsScreen(category: SettingsCategory.playback),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final toggle = find.widgetWithText(SwitchListTile, '全局音量记忆');
        final slider = find.byType(Slider);
        expect(tester.widget<Slider>(slider).onChanged, isNotNull);
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(repository.settings.rememberVolumeGlobally, !failSave);
        expect(repository.settings.defaultVolume, 35.5);
        expect(tester.widget<SwitchListTile>(toggle).value, !failSave);
        expect(
          tester.widget<Slider>(slider).onChanged,
          failSave ? isNotNull : isNull,
        );
        expect(tester.widget<Slider>(slider).value, 35.5);
        if (failSave) {
          expect(find.text('设置保存失败，请重试'), findsOneWidget);
        } else {
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(repository.settings.rememberVolumeGlobally, isFalse);
          expect(tester.widget<Slider>(slider).onChanged, isNotNull);
          expect(repository.settings.defaultVolume, 35.5);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final failSave in [false, true]) {
    testWidgets('default comments save or roll back (failure: $failSave)', (
      tester,
    ) async {
      final repository = _SettingsRepository()..failSave = failSave;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            builder: AppNoticeHost.builder,
            home: const Scaffold(
              body: SettingsScreen(category: SettingsCategory.playback),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final toggle = find.widgetWithText(SwitchListTile, '进入播放页默认显示评论区');
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(repository.settings.defaultShowComments, !failSave);
      expect(repository.settings.autoPlay, isTrue);
      expect(tester.widget<SwitchListTile>(toggle).value, !failSave);
      if (failSave) {
        expect(find.text('设置保存失败，请重试'), findsOneWidget);
      }
      ProviderScope.containerOf(tester.element(toggle))
          .invalidate(settingsControllerProvider);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, !failSave);
      if (!failSave) {
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(repository.settings.defaultShowComments, isFalse);
      }
      expect(tester.takeException(), isNull);
    });
  }
  for (final player in [false, true]) {
    for (final failSave in [false, true]) {
      testWidgets(
        'player swipe toggle saves or rolls back (player: $player, failure: $failSave)',
        (tester) async {
          final repository = _SettingsRepository()..failSave = failSave;
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                settingsRepositoryProvider.overrideWithValue(repository),
              ],
              child: MaterialApp(
                builder: AppNoticeHost.builder,
                home: player
                    ? Builder(
                        builder: (context) => Scaffold(
                          body: TextButton(
                            onPressed: () => showPlayerSettings(context),
                            child: const Text('open'),
                          ),
                        ),
                      )
                    : const Scaffold(
                        body: SettingsScreen(
                          category: SettingsCategory.playback,
                        ),
                      ),
              ),
            ),
          );
          if (player) await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          final toggle = find.widgetWithText(
            SwitchListTile,
            player ? '滑动调节亮度和音量（左侧亮度，右侧音量）' : '滑动调节亮度和音量',
          );
          await tester.ensureVisible(toggle);
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(repository.settings.fullscreenSwipeControls, failSave);
          expect(tester.widget<SwitchListTile>(toggle).value, failSave);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'reset requires confirmation, applies defaults and reloads them',
    (tester) async {
      const defaults = AppSettings.defaults(
        danmakuArea: .5,
        danmakuFontScale: .6,
      );
      final repository = _SettingsRepository()
        ..settings = defaults.copyWith(
          defaultShowComments: true,
          fullscreenSwipeControls: false,
          sidebarStyle: SidebarStyle.compact,
          sidebarCollapsed: true,
          theme: AppThemePreference.dark,
          danmakuArea: 1,
          shortcuts: const ShortcutSettings.defaults().withEnabled(false),
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(repository),
            settingsDefaultsProvider.overrideWithValue(defaults),
          ],
          child: MaterialApp(
            builder: AppNoticeHost.builder,
            home: const Scaffold(body: SettingsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final reset = find.byKey(const ValueKey('reset-settings'));
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(repository.settings.theme, AppThemePreference.dark);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(repository.settings.theme, AppThemePreference.dark);
      expect(tester.widget<TextButton>(reset).onPressed, isNotNull);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认恢复'));
      await tester.pumpAndSettle();
      expect(repository.settings.theme, AppThemePreference.system);
      expect(repository.settings.defaultShowComments, isFalse);
      expect(repository.settings.danmakuArea, .5);
      expect(repository.settings.danmakuFontScale, .6);
      expect(repository.settings.shortcuts.enabled, isTrue);
      expect(repository.settings.fullscreenSwipeControls, isTrue);
      expect(repository.settings.sidebarStyle, SidebarStyle.automatic);
      expect(repository.settings.sidebarCollapsed, isFalse);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '跟随系统'))
            .selected,
        isTrue,
      );
      expect(find.text('已恢复当前平台的默认设置'), findsOneWidget);
      final container = ProviderScope.containerOf(tester.element(reset));
      container.invalidate(settingsControllerProvider);
      await tester.pumpAndSettle();
      expect(
        container.read(settingsControllerProvider).requireValue.danmakuArea,
        .5,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reset failure keeps the saved preference and reports the failure',
    (tester) async {
      final repository = _SettingsRepository()
        ..settings = const AppSettings.defaults().copyWith(
          theme: AppThemePreference.dark,
        )
        ..failSave = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            builder: AppNoticeHost.builder,
            home: const Scaffold(
              body: SettingsScreen(category: SettingsCategory.playback),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reset-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认恢复'));
      await tester.pumpAndSettle();
      expect(repository.settings.theme, AppThemePreference.dark);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsScreen)),
      );
      expect(
        container.read(settingsControllerProvider).requireValue.theme,
        AppThemePreference.dark,
      );
      expect(find.text('恢复默认设置失败，请重试'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('title and category strip stay above the scrolling settings', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(_SettingsRepository()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SettingsScreen(category: SettingsCategory.shortcuts),
          ),
        ),
      ),
    );
    final title = find.byKey(const ValueKey('settings-page-title'));
    final strip = find.byKey(const ValueKey('settings-category-strip'));
    final content = find.byKey(const PageStorageKey('settings-shortcuts'));
    for (final width in [320.0, 600.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpAndSettle();
      expect(find.text('设置'), findsOneWidget);
      expect(tester.getTopLeft(title).dx, 20);
      expect(
        tester.getTopLeft(strip).dy,
        greaterThan(tester.getBottomLeft(title).dy),
      );
      expect(
        tester.getTopLeft(content).dy,
        greaterThan(tester.getBottomLeft(strip).dy),
      );
      final headerRect = tester.getRect(title);
      final stripRect = tester.getRect(strip);
      final position = tester
          .state<ScrollableState>(
            find
                .descendant(of: content, matching: find.byType(Scrollable))
                .first,
          )
          .position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(tester.getRect(title), headerRect);
      expect(tester.getRect(strip), stripRect);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'desktop category strip keeps horizontal wheel and local selection',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(_SettingsRepository()),
          ],
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.windows),
            home: const Scaffold(body: SettingsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final strip = find.byKey(const ValueKey('settings-category-strip'));
      final position = tester
          .state<ScrollableState>(
            find.descendant(of: strip, matching: find.byType(Scrollable)).first,
          )
          .position;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(strip),
          scrollDelta: const Offset(0, 160),
        ),
      );
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      expect(
        find.byKey(const PageStorageKey('settings-appearance')),
        findsOneWidget,
      );
      final category = find.byKey(const ValueKey('settings-category-cache'));
      await tester.ensureVisible(category);
      await tester.pumpAndSettle();
      await tester.tap(category);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const PageStorageKey('settings-cache')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('settings-page-title')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'appearance wheel damping saves, reloads and restores the default',
    (tester) async {
      final repository = _SettingsRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
        ),
      );
      await tester.pumpAndSettle();
      final slider = find.byWidgetPredicate(
        (widget) => widget is Slider && widget.min == .5 && widget.max == 2,
      );
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      final reset = find.byKey(const ValueKey('reset-wheel-damping-ratio'));
      expect(tester.widget<TextButton>(reset).onPressed, isNull);
      expect(find.text('滚轮阻尼比 · 1.30'), findsOneWidget);
      final control = tester.widget<Slider>(slider);
      control.onChanged?.call(1.55);
      await tester.pump();
      expect(repository.settings.wheelDampingRatio, 1.3);
      control.onChangeEnd?.call(1.55);
      await tester.pumpAndSettle();
      expect(repository.settings.wheelDampingRatio, 1.55);
      expect(find.text('滚轮阻尼比 · 1.55'), findsOneWidget);
      final container = ProviderScope.containerOf(tester.element(slider));
      container.invalidate(settingsControllerProvider);
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(slider).value, 1.55);
      await tester.ensureVisible(reset);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(repository.settings.wheelDampingRatio, 1.3);
      expect(find.text('滚轮阻尼比 · 1.30'), findsOneWidget);
      expect(tester.widget<TextButton>(reset).onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final inPlayer in [false, true]) {
    testWidgets('subtitle bottom distance saves 240 px (player: $inPlayer)', (
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
                      builder: (context) => TextButton(
                        onPressed: () => showPlayerSettings(context, tab: 2),
                        child: const Text('字幕设置'),
                      ),
                    )
                  : const SettingsScreen(category: SettingsCategory.subtitles),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (inPlayer) {
        await tester.tap(find.text('字幕设置'));
        await tester.pumpAndSettle();
      }
      final slider = find.byWidgetPredicate(
        (widget) => widget is Slider && widget.max == 240,
      );
      await tester.scrollUntilVisible(
        slider,
        100,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      await tester.drag(slider, const Offset(800, 0));
      await tester.pumpAndSettle();
      expect(repository.settings.subtitleBottomPadding, 240);
      final container = ProviderScope.containerOf(tester.element(slider));
      container.invalidate(settingsControllerProvider);
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(slider).value, 240);
    });
  }
  for (final inPlayer in [false, true]) {
    testWidgets(
      'high energy toggle persists in both settings entries: $inPlayer',
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
                        builder: (context) => TextButton(
                          onPressed: () => showPlayerSettings(context),
                          child: const Text('配置'),
                        ),
                      )
                    : const SettingsScreen(category: SettingsCategory.playback),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (inPlayer) {
          await tester.tap(find.text('配置'));
          await tester.pumpAndSettle();
        }
        final toggle = find.widgetWithText(
          SwitchListTile,
          inPlayer ? '高能进度条（有章节时不显示）' : '高能进度条',
        );
        await tester.scrollUntilVisible(
          toggle,
          120,
          scrollable: find
              .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await Scrollable.ensureVisible(tester.element(toggle), alignment: .5);
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(repository.settings.highEnergyProgressEnabled, isTrue);
        expect(repository.settings.danmakuEnabled, isTrue);
        final container = ProviderScope.containerOf(tester.element(toggle));
        container.invalidate(settingsControllerProvider);
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      },
    );
  }
  for (final inPlayer in [false, true]) {
    testWidgets('live default quality saves separately (player: $inPlayer)', (
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
      expect(find.text('视频默认清晰度'), findsOneWidget);
      if (inPlayer) {
        await tester.scrollUntilVisible(
          find.text('直播默认清晰度'),
          120,
          scrollable: find
              .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable),
              )
              .first,
        );
      }
      expect(find.text('直播默认清晰度'), findsOneWidget);
      final liveDropdown = find.byKey(const ValueKey('preferred-live-quality'));
      for (final (label, quality) in [('自动', 0), ('超清', 250)]) {
        final choice = find.widgetWithText(ChoiceChip, label);
        if (inPlayer) {
          await Scrollable.ensureVisible(
            tester.element(liveDropdown),
            alignment: .5,
          );
          await tester.pumpAndSettle();
          await tester.tap(liveDropdown);
          await tester.pumpAndSettle();
          await tester.tap(find.text(label).last);
        } else {
          await tester.ensureVisible(choice);
          await tester.pumpAndSettle();
          await tester.tap(choice);
        }
        await tester.pumpAndSettle();
        expect(repository.settings.preferredLiveQuality, quality);
        expect(repository.settings.preferredQuality, 80);
        final container = ProviderScope.containerOf(
          tester.element(find.text('直播默认清晰度')),
        );
        container.invalidate(settingsControllerProvider);
        await tester.pumpAndSettle();
        if (inPlayer) {
          expect(
            tester.widget<DropdownButton<int>>(liveDropdown).value,
            quality,
          );
        } else {
          expect(tester.widget<ChoiceChip>(choice).selected, isTrue);
        }
      }
      final videoTile = find.widgetWithText(ListTile, '视频默认清晰度');
      if (inPlayer) {
        await tester.scrollUntilVisible(
          videoTile,
          -180,
          scrollable: find
              .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        final videoDropdown = find.descendant(
          of: videoTile,
          matching: find.byType(DropdownButton<int>),
        );
        await tester.ensureVisible(videoDropdown);
        await tester.pumpAndSettle();
        await tester.tap(videoDropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('720P').last);
      } else {
        final videoChoice = find.widgetWithText(ChoiceChip, '720P');
        await tester.ensureVisible(videoChoice);
        await tester.pumpAndSettle();
        await tester.tap(videoChoice);
      }
      await tester.pumpAndSettle();
      expect(repository.settings.preferredQuality, 64);
      expect(repository.settings.preferredLiveQuality, 250);
      expect(tester.takeException(), isNull);
    });
  }
  for (final failSave in [false, true]) {
    testWidgets(
      'hover playback toggle saves or rolls back (failure: $failSave)',
      (tester) async {
        final repository = _SettingsRepository()..failSave = failSave;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsRepositoryProvider.overrideWithValue(repository),
            ],
            child: MaterialApp(
              builder: AppNoticeHost.builder,
              home: const Scaffold(
                body: SettingsScreen(category: SettingsCategory.playback),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final toggle = find.widgetWithText(SwitchListTile, '视频卡悬停播放');
        expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(repository.settings.videoCardHoverPlayback, failSave);
        expect(repository.settings.autoPlay, isTrue);
        expect(tester.widget<SwitchListTile>(toggle).value, failSave);
        if (failSave) {
          expect(find.text('设置保存失败，请重试'), findsOneWidget);
        }
        ProviderScope.containerOf(tester.element(toggle))
            .invalidate(settingsControllerProvider);
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(toggle).value, failSave);
      },
    );
  }

  testWidgets('continuous playback toggle saves and reloads independently', (
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
    final toggle = find.widgetWithText(SwitchListTile, '连续播放');
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(repository.settings.continuousPlayback, isTrue);
    expect(repository.settings.autoPlay, isTrue);
    ProviderScope.containerOf(tester.element(toggle))
        .invalidate(settingsControllerProvider);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
  });
  for (final failSave in [false, true]) {
    testWidgets(
      'related autoplay saves independently and rolls back: $failSave',
      (tester) async {
        final repository = _SettingsRepository()..failSave = failSave;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsRepositoryProvider.overrideWithValue(repository),
            ],
            child: MaterialApp(
              builder: AppNoticeHost.builder,
              home: const Scaffold(
                body: SettingsScreen(category: SettingsCategory.playback),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final toggle = find.widgetWithText(SwitchListTile, '连续播放相关视频');
        expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(repository.settings.continuousRelatedPlayback, !failSave);
        expect(repository.settings.continuousPlayback, isFalse);
        expect(repository.settings.autoPlay, isTrue);
        ProviderScope.containerOf(tester.element(toggle))
            .invalidate(settingsControllerProvider);
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(toggle).value, !failSave);
      },
    );
  }
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
      final tile = find.byKey(const ValueKey('cdn-settings'));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      final choice = find.byKey(ValueKey('cdn-option-${preference.name}'));
      expect(find.text(label), findsOneWidget);
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(repository.settings.mediaCdn, preference);
      expect(find.text('当前：$label · 点击选择并测速'), findsOneWidget);
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
    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '自动')).selected,
      isTrue,
    );
    for (final (label, mode) in [
      ('单标签页', WorkspaceNavigationMode.singlePage),
      ('双标签页', WorkspaceNavigationMode.dualTabs),
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
        expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
        expect(
          tester.widget<SwitchListTile>(toggle).onChanged != null,
          mode == WorkspaceNavigationMode.multipleTabs,
        );
        final container = ProviderScope.containerOf(
          tester.element(toggle),
          listen: false,
        );
        final controller = container.read(settingsControllerProvider.notifier);
        if (mode != WorkspaceNavigationMode.multipleTabs) {
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(repository.settings.allowConcurrentPlayback, isFalse);
          await controller.setNavigationMode(
            WorkspaceNavigationMode.multipleTabs,
          );
          await tester.pumpAndSettle();
        }
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(repository.settings.allowConcurrentPlayback, isTrue);
        await controller.setNavigationMode(WorkspaceNavigationMode.dualTabs);
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
        expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
        await controller.setNavigationMode(
          WorkspaceNavigationMode.multipleTabs,
        );
        await tester.pumpAndSettle();
        container.invalidate(settingsControllerProvider);
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(toggle).onChanged, isNotNull);
        expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
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
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, '系统默认'));
      await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
    expect(darkChoice.hitTestable(), findsOneWidget);
    final viewport = tester.getRect(
      find.byKey(const PageStorageKey('settings-appearance')),
    );
    final choice = tester.getRect(darkChoice);
    expect(choice.top, greaterThanOrEqualTo(viewport.top));
    expect(choice.bottom, lessThanOrEqualTo(viewport.bottom));
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
    final dark = find.widgetWithText(ChoiceChip, '深色');
    await tester.ensureVisible(dark);
    await tester.pumpAndSettle();
    await tester.tap(dark);
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
