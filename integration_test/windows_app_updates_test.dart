import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/settings/application/app_update_controller.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/data/github_update_repository.dart';
import 'package:bilisail/features/settings/data/installed_app_version.dart';
import 'package:bilisail/features/settings/data/sqlite_settings_repository.dart';
import 'package:bilisail/features/settings/data/sqlite_update_check_store.dart';
import 'package:bilisail/features/settings/domain/settings_category.dart';
import 'package:bilisail/features/settings/presentation/app_update_host.dart';
import 'package:bilisail/features/settings/presentation/settings_screen.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Windows installed version, startup prompt, daily store and Release navigation',
    (tester) async {
      final installed = await loadInstalledAppVersion();
      final package = await PackageInfo.fromPlatform();
      expect(installed.major, greaterThanOrEqualTo(0));
      debugPrint(
        'Installed version: ${installed.label}; package: ${package.version}+${package.buildNumber}',
      );
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final nextVersion =
          '${installed.major}.${installed.minor}.${installed.patch}+${installed.build + 1}';
      final releaseUrl = Uri.https(
        'github.com',
        '/CKopoer/BiliSail/releases/tag/v$nextVersion',
      );
      final repository = GitHubUpdateRepository(
        versionLoader: loadInstalledAppVersion,
        fetcher: (_) async => jsonEncode([
          {
            'tag_name': 'v$nextVersion',
            'draft': false,
            'prerelease': true,
            'html_url': releaseUrl.toString(),
            'body': 'Windows 原生更新提示验证：保留当前页面和播放状态，点击按钮前往 Release 查看详情。',
          },
        ]),
      );
      addTearDown(repository.close);
      final opened = <Uri>[];
      final navigatorKey = GlobalKey<NavigatorState>();
      final repaintKey = GlobalKey();
      final day = DateTime.now().toLocal();
      final localDay =
          '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appUpdateRepositoryProvider.overrideWithValue(repository),
            updateCheckStoreProvider.overrideWithValue(
              SqliteUpdateCheckStore(database),
            ),
            settingsRepositoryProvider.overrideWithValue(
              SqliteSettingsRepository(database),
            ),
            appUpdateLinkOpenerProvider.overrideWithValue((uri) async {
              opened.add(uri);
              return true;
            }),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            builder: (context, child) => AppUpdateHost(
              navigatorKey: navigatorKey,
              child: AppNoticeHost.builder(
                context,
                RepaintBoundary(
                  key: repaintKey,
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
            home: const Scaffold(
              body: SettingsScreen(category: SettingsCategory.about),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(opened, isEmpty);
      expect(
        await database.readSetting(SqliteUpdateCheckStore.lastStartupDayKey),
        localDay,
      );
      final render = repaintKey.currentContext?.findRenderObject();
      if (render is RenderRepaintBoundary) {
        final image = await render.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes != null) {
          final output = File('artifacts/app-updates-windows.png');
          await output.parent.create(recursive: true);
          await output.writeAsBytes(bytes.buffer.asUint8List());
        }
        image.dispose();
      }
      await tester.tap(find.text('前往 Release'));
      await tester.pumpAndSettle();
      expect(opened, [releaseUrl]);
      expect(
        await SqliteUpdateCheckStore(database).claimStartupDay(localDay),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  const online = bool.fromEnvironment('BILI_UPDATES_ONLINE');
  testWidgets('public GitHub Release transport without account credentials', (
    tester,
  ) async {
    final repository = GitHubUpdateRepository(
      versionLoader: loadInstalledAppVersion,
    );
    addTearDown(repository.close);
    final release = await repository.latestRelease(RequestCancellation());
    expect(release?.url.host, anyOf('github.com', isNull));
    debugPrint('Published Release: ${release?.version.label ?? "none"}');
  }, skip: !online);
}
