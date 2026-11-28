import 'dart:convert';

import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/domain/recommendation_settings.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/data/sqlite_settings_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_category.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:bilisail/features/settings/presentation/settings_screen.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved recommendation sources persist and missing values use platform defaults', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = SqliteSettingsRepository(database);
    final mobile = SqliteSettingsRepository(
      database,
      defaultRecommendationSource: RecommendationSource.app,
    );
    expect(
      (await repository.load()).recommendations.source,
      RecommendationSource.web,
    );
    expect(
      (await mobile.load()).recommendations.source,
      RecommendationSource.app,
    );
    for (final source in RecommendationSource.values) {
      await repository.save(
        AppSettings(recommendations: RecommendationSettings(source: source)),
      );
      expect((await repository.load()).recommendations.source, source);
      expect((await mobile.load()).recommendations.source, source);
    }
    for (final featured in FeaturedSource.values) {
      await repository.save(
        AppSettings(
          recommendations: RecommendationSettings(
            source: RecommendationSource.web,
            featuredSource: featured,
          ),
        ),
      );
      expect((await mobile.load()).recommendations.featuredSource, featured);
      expect(
        (await mobile.load()).recommendations.source,
        RecommendationSource.web,
      );
    }
    for (final recommendations in <Object?>[
      null,
      {'source': 'unknown'},
      {'source': 2},
      {'keepPrevious': true},
    ]) {
      await database.writeSetting(
        'preferences.v1',
        jsonEncode({'recommendations': recommendations}),
      );
      expect(
        (await repository.load()).recommendations.source,
        RecommendationSource.web,
      );
      expect(
        (await mobile.load()).recommendations.source,
        RecommendationSource.app,
      );
    }
    expect((await mobile.load()).recommendations.keepPrevious, isTrue);
    expect(
      const RecommendationSettings.defaults().source,
      RecommendationSource.web,
    );
  });

  testWidgets('custom threshold validates, saves and remains selectable', (
    tester,
  ) async {
    final repository = _Settings();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: Scaffold(
            body: SettingsScreen(category: SettingsCategory.recommendation),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final group = find.byKey(const ValueKey('recommendation-like-ratio'));
    final custom = find.descendant(
      of: group,
      matching: find.widgetWithText(ActionChip, '自定义'),
    );
    await tester.ensureVisible(custom);
    await tester.pumpAndSettle();
    await tester.tap(custom);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('recommendation-custom-threshold'));
    await tester.enterText(field, '101');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('请输入 0 到 100 的整数'), findsOneWidget);
    await tester.enterText(field, '7');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(repository.value.recommendations.minimumLikeRatio, 7);
    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '7%')).selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
  test(
    'legacy SQLite snapshots, round-trip and reset keep unrelated preferences',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = SqliteSettingsRepository(database);
      await database.writeSetting(
        'preferences.v1',
        jsonEncode({
          'theme': 'dark',
          'navigationMode': 'singlePage',
          'recommendations': {'keepPrevious': false},
        }),
      );
      final legacy = await repository.load();
      expect(legacy.recommendations.reportInteractions, isTrue);
      expect(
        legacy.recommendations.toJson(),
        const RecommendationSettings.defaults().toJson(),
      );
      final selected = RecommendationSettings(
        openStoryCardsInFeed: false,
        reportInteractions: false,
        keepPrevious: true,
        minimumLikeRatio: 3,
        minimumDurationSeconds: 90,
        minimumPlayCount: 500,
        titleKeywords: ['spam'],
        categoryKeywords: ['游戏'],
        exemptFollowed: false,
        filterRelated: false,
      );
      await repository.save(legacy.copyWith(recommendations: selected));
      final restored = await repository.load();
      expect(restored.recommendations.toJson(), selected.toJson());
      expect(restored.theme, AppThemePreference.dark);
      expect(restored.navigationMode, WorkspaceNavigationMode.singlePage);
      expect(database.schemaVersion, 4);
      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);
      await container
          .read(settingsControllerProvider.notifier)
          .resetToDefaults();
      expect(
        (await repository.load()).recommendations.toJson(),
        const RecommendationSettings.defaults().toJson(),
      );
      expect(
        jsonDecode(
          (await database.readSetting('preferences.v1'))!,
        )['schemaVersion'],
        62,
      );
    },
  );

  for (final failSave in [false, true]) {
    testWidgets(
      'recommendation tab saves or rolls back its toggle: $failSave',
      (tester) async {
        final repository = _Settings()..failSave = failSave;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsRepositoryProvider.overrideWithValue(repository),
              settingsDefaultsProvider.overrideWithValue(
                const AppSettings.defaults(
                  recommendations: RecommendationSettings.defaults(
                    source: RecommendationSource.app,
                  ),
                ),
              ),
            ],
            child: MaterialApp(
              builder: AppNoticeHost.builder,
              home: const Scaffold(
                body: SettingsScreen(category: SettingsCategory.recommendation),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('推荐流设置'), findsOneWidget);
        final desktop = find.widgetWithText(ChoiceChip, '桌面端 / PC');
        await tester.tap(desktop);
        await tester.pumpAndSettle();
        expect(tester.widget<ChoiceChip>(desktop).selected, !failSave);
        expect(
          repository.value.recommendations.source,
          failSave ? RecommendationSource.web : RecommendationSource.desktop,
        );
        final story = find.widgetWithText(SwitchListTile, '首页 Story 卡进入上下滑模式');
        expect(tester.widget<SwitchListTile>(story).value, isTrue);
        await tester.tap(story);
        await tester.pumpAndSettle();
        expect(repository.value.recommendations.openStoryCardsInFeed, failSave);
        expect(tester.widget<SwitchListTile>(story).value, failSave);
        final reporting = find.widgetWithText(SwitchListTile, '上报推荐卡片曝光和点击');
        await tester.ensureVisible(reporting);
        expect(tester.widget<SwitchListTile>(reporting).value, isTrue);
        await tester.tap(reporting);
        await tester.pumpAndSettle();
        expect(repository.value.recommendations.reportInteractions, failSave);
        expect(tester.widget<SwitchListTile>(reporting).value, failSave);
        final toggle = find.widgetWithText(SwitchListTile, '保留首页推荐刷新');
        await tester.ensureVisible(toggle);
        expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
        final marker = find.widgetWithText(SwitchListTile, '显示上次看到位置提示');
        expect(tester.widget<SwitchListTile>(marker).onChanged, isNull);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(repository.value.recommendations.keepPrevious, !failSave);
        expect(tester.widget<SwitchListTile>(toggle).value, !failSave);
        expect(repository.value.theme, AppThemePreference.dark);
        if (failSave) {
          expect(find.text('设置保存失败，请重试'), findsOneWidget);
        } else {
          final reset = find.text('恢复推荐流默认设置');
          await tester.ensureVisible(reset);
          await tester.pumpAndSettle();
          await tester.tap(reset);
          await tester.pumpAndSettle();
          expect(
            repository.value.recommendations.source,
            RecommendationSource.app,
          );
          expect(repository.value.recommendations.keepPrevious, isFalse);
          expect(repository.value.recommendations.openStoryCardsInFeed, isTrue);
          expect(repository.value.theme, AppThemePreference.dark);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'keyword editor validates limits, cancels drafts and saves literal terms',
    (tester) async {
      final repository = _Settings();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
            home: Scaffold(
              body: SettingsScreen(category: SettingsCategory.recommendation),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final editor = find.widgetWithText(ListTile, '标题关键词过滤');
      await tester.ensureVisible(editor);
      await tester.pumpAndSettle();
      await tester.tap(editor);
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('recommendation-keywords'));
      await tester.enterText(field, 'a' * 65);
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.text('每个关键词最多 64 字符'), findsOneWidget);
      await tester.enterText(
        field,
        'SPAM\n'
        r'(a+)+$',
      );
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(repository.value.recommendations.titleKeywords, isEmpty);
      await tester.tap(editor);
      await tester.pumpAndSettle();
      await tester.enterText(
        field,
        ' SPAM \n'
        r'(a+)+$'
        '\nSPAM',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(repository.value.recommendations.titleKeywords, [
        'SPAM',
        r'(a+)+$',
      ]);
      expect(tester.takeException(), isNull);
    },
  );
}

final class _Settings implements SettingsRepository {
  AppSettings value = AppSettings(theme: AppThemePreference.dark);
  bool failSave = false;
  @override
  Future<AppSettings> load() async => value;
  @override
  Future<void> save(AppSettings settings) async {
    if (failSave) throw StateError('disk full');
    value = settings;
  }
}
