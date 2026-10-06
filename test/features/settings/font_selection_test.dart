import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/platform/system_font_catalog.dart';
import 'package:bilisail/domain/system_font_catalog.dart';
import 'package:bilisail/features/playback/presentation/player_settings_dialog.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/application/system_fonts_controller.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_category.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:bilisail/features/settings/presentation/settings_screen.dart';
import 'package:bilisail/shared/ui/system_font_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('both themes resolve bundled and installed fonts', () {
    for (final theme in [BiliTheme.light, BiliTheme.dark]) {
      expect(
        theme(font: AppFontPreference.alibabaPuHuiTi)
            .textTheme
            .bodyMedium
            ?.fontFamily,
        'Alibaba PuHuiTi 3.0',
      );
      expect(
        theme(
          font: AppFontPreference.installed,
          systemFontFamily: 'Segoe UI',
        ).textTheme.bodyMedium?.fontFamily,
        'Segoe UI',
      );
    }
  });

  test('native catalog normalizes names and preserves platform failures', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      NativeSystemFontCatalog.channel,
      (_) async => ['Segoe UI', 'Arial', 'Arial', '  ', '@Vertical', ' 微软雅黑 '],
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        NativeSystemFontCatalog.channel,
        null,
      ),
    );
    // The platform capability is tested in the native Windows integration test.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const catalog = NativeSystemFontCatalog();
    expect(await catalog.loadFamilies(), ['Arial', 'Segoe UI', '微软雅黑']);
    messenger.setMockMethodCallHandler(
      NativeSystemFontCatalog.channel,
      (_) async => [123],
    );
    await expectLater(catalog.loadFamilies(), throwsFormatException);
    messenger.setMockMethodCallHandler(
      NativeSystemFontCatalog.channel,
      (_) async => throw PlatformException(code: 'unavailable'),
    );
    await expectLater(
      catalog.loadFamilies(),
      throwsA(isA<PlatformException>()),
    );
  });

  for (final entry in ['appearance', 'danmaku', 'player']) {
    testWidgets('$entry saves bundled and installed fonts independently', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(650, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Repository();
      final catalog = _Catalog();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(repository),
            systemFontCatalogProvider.overrideWithValue(catalog),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: entry == 'player'
                  ? Builder(
                      builder: (context) => TextButton(
                        onPressed: () => showPlayerSettings(context, tab: 1),
                        child: const Text('打开播放器配置'),
                      ),
                    )
                  : SettingsScreen(
                      category: entry == 'appearance'
                          ? SettingsCategory.appearance
                          : SettingsCategory.danmaku,
                    ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(catalog.reads, 0);
      if (entry == 'player') {
        await tester.tap(find.text('打开播放器配置'));
        await tester.pumpAndSettle();
      }
      if (entry != 'appearance') {
        final dropdown = find.byKey(const ValueKey('danmaku-font'));
        await tester.ensureVisible(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('阿里巴巴普惠体 3.0').last);
      await tester.pumpAndSettle();
      expect(
        entry == 'appearance'
            ? repository.value.fontFamily
            : repository.value.danmakuFontFamily,
        'Alibaba PuHuiTi 3.0',
      );
      final picker = find.byType(SystemFontPicker);
      await tester.ensureVisible(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择系统字体'));
      await tester.pumpAndSettle();
      expect(catalog.reads, 1);
      await tester.enterText(find.widgetWithText(TextField, '搜索字体'), 'segoe');
      await tester.pumpAndSettle();
      expect(find.text('Arial'), findsNothing);
      await tester.tap(find.text('Segoe UI'));
      await tester.pumpAndSettle();
      expect(
        entry == 'appearance'
            ? repository.value.fontFamily
            : repository.value.danmakuFontFamily,
        'Segoe UI',
      );
      expect(
        entry == 'appearance'
            ? repository.value.danmakuFont
            : repository.value.font,
        entry == 'appearance'
            ? DanmakuFontPreference.system
            : AppFontPreference.harmonyOsSans,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'unavailable saved font, refresh failure and cancel preserve selection',
    (tester) async {
      final catalog = _Catalog()..fail = true;
      String? selected;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [systemFontCatalogProvider.overrideWithValue(catalog)],
          child: MaterialApp(
            home: Scaffold(
              body: SystemFontPicker(
                family: 'Removed Font',
                onSelected: (family) => selected = family,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('系统字体：Removed Font'));
      await tester.pumpAndSettle();
      expect(find.text('读取系统字体失败，请刷新重试'), findsOneWidget);
      catalog.fail = false;
      await tester.tap(find.text('刷新字体列表'));
      await tester.pumpAndSettle();
      expect(find.text('已选字体当前不可用，文字由系统回退显示；可重新选择'), findsOneWidget);
      expect(catalog.reads, 2);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
    },
  );
}

final class _Catalog implements SystemFontCatalog {
  bool fail = false;
  int reads = 0;
  @override
  bool get supported => true;
  @override
  Future<List<String>> loadFamilies() async {
    ++reads;
    if (fail) throw StateError('unavailable');
    return ['Arial', 'Segoe UI'];
  }
}

final class _Repository implements SettingsRepository {
  AppSettings value = const AppSettings.defaults();
  @override
  Future<AppSettings> load() async => value;
  @override
  Future<void> save(AppSettings settings) async => value = settings;
}
