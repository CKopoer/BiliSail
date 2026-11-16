import 'dart:async';

import 'package:bilisail/domain/recommendation_settings.dart';
import 'package:bilisail/features/feed/application/app_recommendation_identity.dart';
import 'package:bilisail/features/feed/domain/app_recommendation_identity_repository.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_category.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';

import 'package:bilisail/features/settings/presentation/settings_screen.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('source saves immediately without exposing the device identity', (
    tester,
  ) async {
    final settings = _Settings();
    final identity = _Identity();
    addTearDown(identity.events.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          appRecommendationIdentityRepositoryProvider.overrideWithValue(
            identity,
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
    expect(find.text('当前使用游客推荐。'), findsNothing);
    expect(find.text('扫码授权 App 推荐'), findsNothing);
    expect(find.text('更新登录'), findsNothing);
    expect(find.textContaining('buvid'), findsNothing);
    expect(find.textContaining('设备标识'), findsNothing);
    expect(find.text(identity.device), findsNothing);
    expect(
      find.byKey(const ValueKey('app-recommendation-buvid')),
      findsNothing,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'App 推荐'));
    await tester.pumpAndSettle();
    expect(settings.value.recommendations.source, RecommendationSource.app);
    expect(settings.value.theme, AppThemePreference.dark);
    expect(identity.device, 'fixture_device_0123456789');
    expect(find.textContaining('buvid'), findsNothing);
    expect(find.textContaining('设备标识'), findsNothing);
    expect(find.text(identity.device), findsNothing);
    expect(find.text('当前使用游客推荐。'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '桌面端 / PC'));
    await tester.pumpAndSettle();
    expect(settings.value.recommendations.source, RecommendationSource.desktop);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '桌面端 / PC'))
          .selected,
      isTrue,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Web 推荐'));
    await tester.pumpAndSettle();
    expect(settings.value.recommendations.source, RecommendationSource.web);
    expect(tester.takeException(), isNull);
  });
}

final class _Settings implements SettingsRepository {
  AppSettings value = AppSettings(theme: AppThemePreference.dark);
  @override
  Future<AppSettings> load() async => value;
  @override
  Future<void> save(AppSettings settings) async {
    value = settings;
  }
}

final class _Identity implements AppRecommendationIdentityRepository {
  final events = StreamController<int>.broadcast();
  String device = 'fixture_device_0123456789';
  @override
  int revision = 0;
  @override
  Stream<int> get changes => events.stream;
  @override
  Future<AppRecommendationIdentity> load() async =>
      AppRecommendationIdentity(buvid: device);
  @override
  Future<void> setBuvid(String value) async {
    device = value;
    events.add(++revision);
  }

  @override
  Future<void> randomizeBuvid() => setBuvid('random_device_0123456789');
}
