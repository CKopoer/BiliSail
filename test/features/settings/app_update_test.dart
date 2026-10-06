import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bilisail/core/platform/external_links.dart';
import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/settings/application/app_update_controller.dart';
import 'package:bilisail/features/settings/data/github_update_repository.dart';
import 'package:bilisail/features/settings/data/installed_app_version.dart';
import 'package:bilisail/features/settings/data/sqlite_update_check_store.dart';
import 'package:bilisail/features/settings/domain/app_update.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_category.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/presentation/app_update_host.dart';
import 'package:bilisail/features/settings/presentation/settings_screen.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

AppVersion _version(String value) =>
    AppVersion.tryParse(value) ?? (throw StateError(value));
AppRelease _release(
  String value, {
  String notes = '',
  bool prerelease = false,
}) => AppRelease(
  version: _version(value),
  notes: notes,
  prerelease: prerelease,
  url: Uri.https('github.com', '/CKopoer/BiliSail/releases/tag/v$value'),
);
Map<String, Object?> _jsonRelease(
  String tag, {
  bool draft = false,
  bool prerelease = false,
  String? url,
}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': prerelease,
  'html_url':
      url ??
      Uri.https('github.com', '/CKopoer/BiliSail/releases/tag/$tag').toString(),
  'body': '更新说明',
};

ProviderContainer _container(
  _UpdateRepository repository,
  _CheckStore store, {
  DateTime? now,
}) {
  final container = ProviderContainer(
    overrides: [
      appUpdateRepositoryProvider.overrideWithValue(repository),
      updateCheckStoreProvider.overrideWithValue(store),
      updateClockProvider.overrideWithValue(() => now ?? DateTime(2026, 10, 6)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _app(
  _UpdateRepository repository,
  _CheckStore store,
  List<Uri> opened, {
  Widget home = const Scaffold(body: Text('首页')),
  bool openSucceeds = true,
}) {
  final navigatorKey = GlobalKey<NavigatorState>();
  return ProviderScope(
    overrides: [
      appUpdateRepositoryProvider.overrideWithValue(repository),
      updateCheckStoreProvider.overrideWithValue(store),
      updateClockProvider.overrideWithValue(() => DateTime(2026, 10, 6)),
      settingsRepositoryProvider.overrideWithValue(_SettingsRepository()),
      appUpdateLinkOpenerProvider.overrideWithValue((uri) async {
        opened.add(uri);
        return openSucceeds;
      }),
    ],
    child: MaterialApp(
      navigatorKey: navigatorKey,
      builder: (context, child) => AppUpdateHost(
        navigatorKey: navigatorKey,
        child: AppNoticeHost.builder(context, child),
      ),
      home: home,
    ),
  );
}

void main() {
  for (final (older, newer) in [
    ('0.1.0+1', 'v0.1.0+2'),
    ('0.9.0+90', '0.10.0+1'),
    ('1.0.9', '1.0.10'),
    ('1.0.0-beta.9', '1.0.0-beta.10'),
    ('1.0.0-rc.9', '1.0.0'),
    ('1.0.0-alpha', '1.0.0-alpha.1'),
    ('1.0.0-1', '1.0.0-alpha'),
  ]) {
    test('numeric version precedence: $older < $newer', () {
      expect(_version(newer).compareTo(_version(older)), greaterThan(0));
      expect(_version(older).compareTo(_version(newer)), lessThan(0));
    });
  }
  test('non-numeric build metadata has no semantic precedence', () {
    expect(_version('1.0.0+sha.a').compareTo(_version('1.0.0+sha.b')), 0);
    for (final invalid in [
      '1.2',
      '01.2.3',
      '1.2.3-01',
      '1.2.3+',
      'v../../x',
      '1.2.3\n',
      '1.2.3+9999999999999999999999',
    ]) {
      expect(AppVersion.tryParse(invalid), isNull, reason: invalid);
    }
  });
  test(
    'select greatest published version, including preview and encoded + tag',
    () {
      final release = GitHubUpdateRepository.parseReleases(
        jsonEncode([
          _jsonRelease('v8.0.0', draft: true),
          _jsonRelease('v0.2.0'),
          _jsonRelease('notes'),
          _jsonRelease(
            'v0.3.0+2',
            prerelease: true,
            url: 'https://github.com/CKopoer/BiliSail/releases/tag/v0.3.0%2B2',
          ),
          _jsonRelease('v0.1.0+200'),
        ]),
      );
      expect(release?.version.label, '0.3.0+2');
      expect(release?.prerelease, isTrue);
    },
  );
  test('empty release list and draft-only list have no published version', () {
    expect(GitHubUpdateRepository.parseReleases('[]'), isNull);
    expect(
      GitHubUpdateRepository.parseReleases(
        jsonEncode([_jsonRelease('v9.0.0', draft: true)]),
      ),
      isNull,
    );
  });
  test('malformed and untrusted release responses are failures', () {
    for (final body in [
      '{}',
      '[null]',
      'not-json',
      jsonEncode([_jsonRelease('nightly')]),
      jsonEncode([_jsonRelease('v1.0.0', url: 'https://evil.example/release')]),
      jsonEncode([
        _jsonRelease(
          'v1.0.0',
          url: 'https://github.com/Other/Repo/releases/tag/v1.0.0',
        ),
      ]),
      jsonEncode([
        _jsonRelease(
          'v1.0.0',
          url: 'https://user:pass@github.com/CKopoer/BiliSail/releases/tag/v1.0.0',
        ),
      ]),
      jsonEncode([
        _jsonRelease(
          'v1.0.0',
          url:
              'https://github.com/CKopoer/BiliSail/releases/tag/v1.0.0?token=x',
        ),
      ]),
    ]) {
      expect(
        () => GitHubUpdateRepository.parseReleases(body),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.kind,
            'kind',
            AppFailureKind.protocol,
          ),
        ),
      );
    }
  });
  test('release body and displayed notes have capacity limits', () {
    expect(
      () => GitHubUpdateRepository.parseReleases(
        ' ' * (GitHubUpdateRepository.maxResponseBytes + 1),
      ),
      throwsA(isA<AppFailure>()),
    );
    final release = GitHubUpdateRepository.parseReleases(
      jsonEncode([
        {..._jsonRelease('v1.0.0'), 'body': 'a' * 13000},
      ]),
    );
    expect(release?.notes.length, lessThan(12100));
    expect(release?.notes, contains('完整说明'));
  });
  test('cancelled repository reads do not return late success', () async {
    final result = Completer<String>();
    final cancellation = RequestCancellation();
    final repository = GitHubUpdateRepository(
      versionLoader: () async => _version('0.1.0+1'),
      fetcher: (_) => result.future,
    );
    final read = repository.latestRelease(cancellation);
    final expectation = expectLater(
      read,
      throwsA(
        isA<AppFailure>().having(
          (e) => e.kind,
          'kind',
          AppFailureKind.cancelled,
        ),
      ),
    );
    cancellation.cancel();
    result.complete('[]');
    await expectation;
    repository.close();
  });
  test(
    'external links allow this project and reject other GitHub destinations',
    () {
      for (final uri in [
        AppUpdateLinks.repository,
        AppUpdateLinks.releases,
        _release('0.1.0+2').url,
        Uri.parse('https://www.bilibili.com/video/BV1'),
      ]) {
        expect(isAllowedExternalLink(uri), isTrue);
      }
      for (final url in [
        'https://github.com/Other/Repo',
        'http://github.com/CKopoer/BiliSail',
        'https://github.com:444/CKopoer/BiliSail',
        'https://user@github.com/CKopoer/BiliSail',
        'https://github.com/CKopoer/BiliSail?token=x',
        'https://github.com/CKopoer/BiliSail/issues',
        'https://github.com.evil.example/CKopoer/BiliSail',
      ]) {
        expect(isAllowedExternalLink(Uri.parse(url)), isFalse, reason: url);
      }
    },
  );
  test(
    'installed version uses package metadata or exact Release build override',
    () async {
      PackageInfo.setMockInitialValues(
        appName: 'BiliSail',
        packageName: 'dev.bilisail.bilisail',
        version: '9.8.7',
        buildNumber: '42',
        buildSignature: '',
      );
      const override = String.fromEnvironment('BILISAIL_RELEASE_VERSION');
      expect(
        (await loadInstalledAppVersion()).label,
        override.isEmpty ? '9.8.7+42' : override,
      );
    },
  );
  test('startup day persists across repository and database reopening without clearing preferences', () async {
    final directory = await Directory.systemTemp.createTemp(
      'bilisail-updates-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/updates.sqlite');
    final first = AppDatabase(NativeDatabase(file));
    await first.writeSetting('preferences.v1', '{"font":"harmonyOsSans"}');
    final store = SqliteUpdateCheckStore(first);
    expect(await store.claimStartupDay('2026-10-06'), isTrue);
    expect(await store.claimStartupDay('2026-10-06'), isFalse);
    await first.close();
    final second = AppDatabase(NativeDatabase(file));
    addTearDown(second.close);
    final restored = SqliteUpdateCheckStore(second);
    expect(await restored.claimStartupDay('2026-10-06'), isFalse);
    expect(await restored.claimStartupDay('2026-10-07'), isTrue);
    expect(
      await second.readSetting('preferences.v1'),
      '{"font":"harmonyOsSans"}',
    );
    expect(second.schemaVersion, 2);
  });
  test(
    'automatic check runs once per local day, including failed attempts',
    () async {
      final repository = _UpdateRepository()
        ..error = const AppFailure(AppFailureKind.network, '网络错误');
      final store = _CheckStore();
      final first = _container(
        repository,
        store,
        now: DateTime(2026, 10, 6, 23, 59),
      );
      await first.read(appUpdateControllerProvider.notifier).checkOnStartup();
      expect(first.read(appUpdateControllerProvider).message, isNull);
      final restarted = _container(
        repository,
        store,
        now: DateTime(2026, 10, 6, 23, 59),
      );
      await restarted
          .read(appUpdateControllerProvider.notifier)
          .checkOnStartup();
      expect(repository.calls, 1);
      final tomorrow = _container(
        repository,
        store,
        now: DateTime(2026, 10, 7),
      );
      await tomorrow
          .read(appUpdateControllerProvider.notifier)
          .checkOnStartup();
      expect(repository.calls, 2);
      expect(store.day, '2026-10-07');
    },
  );
  test('manual check bypasses daily limit and does not treat old versions as updates', () async {
    final repository = _UpdateRepository()..release = _release('0.1.0+1');
    final container = _container(repository, _CheckStore()..day = '2026-10-06');
    final controller = container.read(appUpdateControllerProvider.notifier);
    await controller.checkOnStartup();
    await controller.checkManually();
    expect(repository.calls, 1);
    expect(
      container.read(appUpdateControllerProvider).message,
      contains('最新版本'),
    );
    expect(container.read(appUpdateControllerProvider).pendingRelease, isNull);
    repository.release = _release('0.0.9+99');
    await controller.checkManually();
    expect(container.read(appUpdateControllerProvider).pendingRelease, isNull);
    repository.release = null;
    await controller.checkManually();
    expect(container.read(appUpdateControllerProvider).message, '暂无已发布版本');
  });
  test(
    'manual check shares the automatic request and surfaces its failure',
    () async {
      final pending = Completer<AppRelease?>();
      final repository = _UpdateRepository()..pending = pending;
      final container = _container(repository, _CheckStore());
      final controller = container.read(appUpdateControllerProvider.notifier);
      final automatic = controller.checkOnStartup();
      await Future<void>.delayed(Duration.zero);
      final manual = controller.checkManually();
      expect(identical(automatic, manual), isTrue);
      pending.completeError(
        const AppFailure(AppFailureKind.rateLimited, 'GitHub 请求受限'),
      );
      await manual;
      expect(repository.calls, 1);
      expect(
        container.read(appUpdateControllerProvider).failure,
        AppFailureKind.rateLimited,
      );
      expect(
        container.read(appUpdateControllerProvider).message,
        'GitHub 请求受限',
      );
    },
  );
  test('dispose cancels requests and prevents late prompts', () async {
    final repository = _UpdateRepository()..pending = Completer<AppRelease?>();
    final container = ProviderContainer(
      overrides: [appUpdateRepositoryProvider.overrideWithValue(repository)],
    );
    final operation = container
        .read(appUpdateControllerProvider.notifier)
        .checkManually();
    await Future<void>.delayed(Duration.zero);
    container.dispose();
    expect(repository.cancellation?.isCancelled, isTrue);
    repository.pending?.complete(_release('9.0.0'));
    await operation;
  });
  testWidgets(
    'deadline cancels check and a late result cannot restore a prompt',
    (tester) async {
      final repository = _UpdateRepository()
        ..pending = Completer<AppRelease?>();
      final container = _container(repository, _CheckStore());
      final operation = container
          .read(appUpdateControllerProvider.notifier)
          .checkManually();
      await tester.pump();
      await tester.pump(const Duration(seconds: 21));
      await operation;
      expect(repository.cancellation?.isCancelled, isTrue);
      expect(
        container.read(appUpdateControllerProvider).failure,
        AppFailureKind.timeout,
      );
      repository.pending?.complete(_release('9.0.0'));
      await tester.pump();
      expect(
        container.read(appUpdateControllerProvider).pendingRelease,
        isNull,
      );
    },
  );
  testWidgets(
    'startup prompt appears outside settings and opens exact Release only on click',
    (tester) async {
      final repository = _UpdateRepository()
        ..release = _release('0.1.0+2', notes: '修复播放问题', prerelease: true);
      final opened = <Uri>[];
      await tester.pumpWidget(_app(repository, _CheckStore(), opened));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 0.1.0+2'), findsOneWidget);
      expect(find.text('修复播放问题'), findsOneWidget);
      expect(opened, isEmpty);
      expect(repository.calls, 1);
      await tester.tap(find.text('前往 Release'));
      await tester.pumpAndSettle();
      expect(opened, [_release('0.1.0+2').url]);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'about links, loading control and manual prompt fit a narrow window',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = Completer<AppRelease?>();
      final repository = _UpdateRepository()..pending = pending;
      final opened = <Uri>[];
      await tester.pumpWidget(
        _app(
          repository,
          _CheckStore()..day = '2026-10-06',
          opened,
          home: const Scaffold(
            body: SettingsScreen(category: SettingsCategory.about),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0.1.0+1'), findsOneWidget);
      expect(find.text('https://github.com/CKopoer/BiliSail'), findsOneWidget);
      expect(find.textContaining('Huawei'), findsNothing);
      expect(find.textContaining('阿里巴巴'), findsNothing);
      await tester.tap(find.text('GitHub'));
      await tester.pumpAndSettle();
      expect(opened, [AppUpdateLinks.repository]);
      await tester.tap(find.text('检查更新'));
      await tester.pump();
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '正在检查更新…'),
      );
      expect(button.onPressed, isNull);
      pending.complete(_release('0.2.0', notes: '更新说明\n' * 150));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('发现新版本 0.2.0'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('稍后再说'));
      await tester.pumpAndSettle();
      expect(opened, [AppUpdateLinks.repository]);
      expect(repository.calls, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'automatic failure is quiet and browser failure shows useful notice',
    (tester) async {
      final repository = _UpdateRepository()
        ..error = const AppFailure(AppFailureKind.network, '检查更新失败');
      final opened = <Uri>[];
      await tester.pumpWidget(_app(repository, _CheckStore(), opened));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('检查更新失败'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      repository.error = null;
      repository.release = _release('0.2.0');
      await tester.pumpWidget(
        _app(repository, _CheckStore(), opened, openSucceeds: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('前往 Release'));
      await tester.pumpAndSettle();
      expect(find.text('无法打开浏览器，请在关于页查看 GitHub 地址'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

final class _UpdateRepository implements AppUpdateRepository {
  AppRelease? release;
  AppFailure? error;
  Completer<AppRelease?>? pending;
  RequestCancellation? cancellation;
  int calls = 0;
  @override
  Future<AppVersion> installedVersion() async => _version('0.1.0+1');
  @override
  Future<AppRelease?> latestRelease(RequestCancellation token) async {
    calls++;
    cancellation = token;
    if (pending case final result?) return result.future;
    if (error case final failure?) throw failure;
    return release;
  }
}

final class _CheckStore implements UpdateCheckStore {
  String? day;
  @override
  Future<bool> claimStartupDay(String value) async {
    if (value == day) return false;
    day = value;
    return true;
  }
}

final class _SettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> load() async => const AppSettings.defaults();
  @override
  Future<void> save(AppSettings settings) async {}
}
