import 'package:bilisail/features/playback/presentation/player_settings_dialog.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_category.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:bilisail/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final inPlayer in [false, true]) {
    testWidgets(
      'style, filtering, offset and density save through both entrances (player: $inPlayer)',
      (tester) async {
        tester.view.physicalSize = const Size(400, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = _Repository();
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
                          onPressed: () => showPlayerSettings(context, tab: 1),
                          child: const Text('打开配置'),
                        ),
                      )
                    : const SettingsScreen(category: SettingsCategory.danmaku),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (inPlayer) {
          await tester.tap(find.text('打开配置'));
          await tester.pumpAndSettle();
        }

        for (final title in ['隐藏滚动弹幕', '字体加粗', '合并重复弹幕', '屏蔽彩色弹幕']) {
          final toggle = find.widgetWithText(SwitchListTile, title);
          await tester.ensureVisible(toggle);
          await tester.pumpAndSettle();
          await tester.tap(toggle);
          await tester.pumpAndSettle();
        }
        expect(repository.value.danmakuScrollEnabled, isFalse);
        expect(repository.value.danmakuBold, isTrue);
        expect(repository.value.danmakuMergeDuplicates, isTrue);
        expect(repository.value.danmakuBlockColored, isTrue);
        for (final entry in {
          'danmaku-font': 'HarmonyOS Sans',
          'danmaku-style': '描边',
        }.entries) {
          final dropdown = find.byKey(ValueKey(entry.key));
          await tester.ensureVisible(dropdown);
          await tester.pumpAndSettle();
          await tester.tap(dropdown);
          await tester.pumpAndSettle();
          await tester.tap(find.text(entry.value).last);
          await tester.pumpAndSettle();
        }
        expect(
          repository.value.danmakuFont,
          DanmakuFontPreference.harmonyOsSans,
        );
        expect(repository.value.danmakuStyle, DanmakuStylePreference.stroke);
        final offset = find.byKey(const ValueKey('danmaku-offset'));
        await tester.ensureVisible(offset);
        await tester.pumpAndSettle();
        await tester.enterText(offset, '-1.5');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(
          repository.value.danmakuOffset,
          const Duration(milliseconds: -1500),
        );
        await tester.tap(find.text('+1 秒'));
        await tester.pumpAndSettle();
        expect(
          repository.value.danmakuOffset,
          const Duration(milliseconds: -500),
        );
        for (final entry in {
          'danmaku-font-scale': 0.0,
          'danmaku-density': 0.0,
          'danmaku-on-screen': .1,
          'danmaku-weight': .5,
        }.entries) {
          final slider = find.descendant(
            of: find.byKey(ValueKey(entry.key)),
            matching: find.byType(Slider),
          );
          await tester.ensureVisible(slider);
          await tester.pumpAndSettle();
          final rect = tester.getRect(slider);
          await tester.tapAt(
            Offset(
              rect.left + 24 + (rect.width - 48) * entry.value,
              rect.center.dy,
            ),
          );
          await tester.pumpAndSettle();
        }
        expect(repository.value.danmakuFontScale, .2);
        expect(repository.value.danmakuMaxPerSecond, 0);
        expect(repository.value.danmakuMaxOnScreen, 12);
        expect(repository.value.danmakuMinimumWeight, 5);
        final word = find.byKey(const ValueKey('danmaku-blocked-word'));
        await tester.ensureVisible(word);
        await tester.pumpAndSettle();
        await tester.enterText(word, '剧透');
        await tester.ensureVisible(find.text('添加关键词'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('添加关键词'));
        await tester.pumpAndSettle();
        expect(repository.value.danmakuBlockedWords, ['剧透']);
        expect(find.textContaining('同步'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('failed save restores the switch and preserves typed offset', (
    tester,
  ) async {
    final repository = _Repository()..fail = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: Scaffold(
            body: SettingsScreen(category: SettingsCategory.danmaku),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final toggle = find.widgetWithText(SwitchListTile, '字体加粗');
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(repository.value.danmakuBold, isFalse);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(find.text('设置保存失败，请重试'), findsOneWidget);
    final offset = find.byKey(const ValueKey('danmaku-offset'));
    await tester.ensureVisible(offset);
    await tester.pumpAndSettle();
    await tester.enterText(offset, 'bad');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(repository.value.danmakuOffset, Duration.zero);
    expect(find.text('弹幕偏移请输入 -60 到 60 秒'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final class _Repository implements SettingsRepository {
  AppSettings value = const AppSettings.defaults();
  bool fail = false;
  @override
  Future<AppSettings> load() async => value;
  @override
  Future<void> save(AppSettings settings) async {
    if (fail) throw StateError('save');
    value = settings;
  }
}
