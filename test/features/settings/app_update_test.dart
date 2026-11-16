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
import 'package:bilisail/shared/ui/app_network_image.dart';
import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
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
  AppUpdateRepository repository,
  _CheckStore store, {
  DateTime? now,
  _SettingsRepository? settings,
}) {
  final container = ProviderContainer(
    overrides: [
      appUpdateRepositoryProvider.overrideWithValue(repository),
      settingsRepositoryProvider.overrideWithValue(
        settings ?? _SettingsRepository(),
      ),
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
  Brightness brightness = Brightness.light,
  DateTime? now,
  _SettingsRepository? settings,
}) {
  final navigatorKey = GlobalKey<NavigatorState>();
  return ProviderScope(
    overrides: [
      appUpdateRepositoryProvider.overrideWithValue(repository),
      updateCheckStoreProvider.overrideWithValue(store),
      updateClockProvider.overrideWithValue(() => now ?? DateTime(2026, 10, 6)),
      settingsRepositoryProvider.overrideWithValue(
        settings ?? _SettingsRepository(),
      ),
      appUpdateLinkOpenerProvider.overrideWithValue((uri) async {
        opened.add(uri);
        return openSucceeds;
      }),
      webLinkOpenerProvider.overrideWithValue((uri) async {
        opened.add(uri);
        return openSucceeds;
      }),
    ],
    child: MaterialApp(
      theme: ThemeData(brightness: brightness),
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
  for (final failSave in [false, true]) {
    testWidgets(
      'prerelease switch controls the next check and rolls back failed saves: $failSave',
      (tester) async {
        final settings = _SettingsRepository()..failSave = failSave;
        final repository = _UpdateRepository();
        await tester.pumpWidget(
          _app(
            repository,
            _CheckStore()..day = '2026-10-06',
            [],
            settings: settings,
            home: const Scaffold(
              body: SettingsScreen(category: SettingsCategory.about),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final toggle = find.widgetWithText(SwitchListTile, '检查预发布更新');
        expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(settings.settings.checkPrereleaseUpdates, !failSave);
        expect(tester.widget<SwitchListTile>(toggle).value, !failSave);
        expect(
          find.text('设置保存失败，请重试'),
          failSave ? findsOneWidget : findsNothing,
        );
        final check = find.widgetWithText(FilledButton, '检查更新');
        await tester.ensureVisible(check);
        await tester.pumpAndSettle();
        await tester.tap(check);
        await tester.pumpAndSettle();
        expect(repository.requestedPrereleases, [!failSave]);
        expect(tester.takeException(), isNull);
      },
    );
  }
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
    'select greatest full release, excluding draft and prerelease flags',
    () {
      final release = GitHubUpdateRepository.parseReleases(
        jsonEncode([
          _jsonRelease('v8.0.0', draft: true),
          _jsonRelease('v9.0.0', prerelease: true),
          _jsonRelease('v0.2.0'),
          _jsonRelease('notes'),
          _jsonRelease(
            'v0.3.0+10',
            url: 'https://github.com/CKopoer/BiliSail/releases/tag/v0.3.0%2B10',
          ),
          _jsonRelease('v0.3.0+2'),
          _jsonRelease('v0.1.0+200'),
        ]),
      );
      expect(release?.version.label, '0.3.0+10');
      expect(release?.prerelease, isFalse);
    },
  );
  test('empty and draft/prerelease-only lists have no full release', () {
    for (final releases in [
      <Map<String, Object?>>[],
      [_jsonRelease('v9.0.0', draft: true)],
      [_jsonRelease('v9.0.0', prerelease: true)],
      [
        _jsonRelease('v9.0.0', draft: true),
        _jsonRelease('v8.0.0', prerelease: true),
        _jsonRelease('nightly', prerelease: true),
      ],
    ]) {
      expect(
        GitHubUpdateRepository.parseReleases(jsonEncode(releases)),
        isNull,
      );
    }
  });
  test('opted-in checks compare both channels and always exclude drafts', () {
    final release = GitHubUpdateRepository.parseReleases(
      jsonEncode([
        _jsonRelease('v10.0.0', draft: true),
        _jsonRelease('v11.0.0', draft: true, prerelease: true),
        _jsonRelease('v0.2.0+20'),
        _jsonRelease('v0.3.0+2', prerelease: true),
        _jsonRelease('v0.3.0+10', prerelease: true),
      ]),
      includePrereleases: true,
    );
    expect(release?.version.label, '0.3.0+10');
    expect(release?.prerelease, isTrue);
    final stable = GitHubUpdateRepository.parseReleases(
      jsonEncode([
        _jsonRelease('v0.3.0-beta.2', prerelease: true),
        _jsonRelease('v0.3.0'),
        _jsonRelease('v0.2.0+999', prerelease: true),
      ]),
      includePrereleases: true,
    );
    expect(stable?.version.label, '0.3.0');
    expect(stable?.prerelease, isFalse);
    expect(
      GitHubUpdateRepository.parseReleases(
        jsonEncode([_jsonRelease('v9.0.0', draft: true)]),
        includePrereleases: true,
      ),
      isNull,
    );
  });
  test('opted-in prereleases retain protocol and link validation', () {
    for (final release in [
      _jsonRelease('nightly', prerelease: true),
      _jsonRelease('v9.0.0', prerelease: true, url: 'https://evil.example'),
      {..._jsonRelease('v9.0.0', prerelease: true), 'draft': 'false'},
      {..._jsonRelease('v9.0.0'), 'prerelease': 'true'},
    ]) {
      expect(
        () => GitHubUpdateRepository.parseReleases(
          jsonEncode([release]),
          includePrereleases: true,
        ),
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
  test('GitHub draft and prerelease fields must be JSON booleans', () {
    for (final field in ['draft', 'prerelease']) {
      for (final value in <Object?>[null, 'false', 'true', 0, 1]) {
        expect(
          () => GitHubUpdateRepository.parseReleases(
            jsonEncode([
              {..._jsonRelease('v1.0.0'), field: value},
            ]),
          ),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.kind,
              'kind',
              AppFailureKind.protocol,
            ),
          ),
          reason: '$field: $value',
        );
      }
    }
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
  for (final automatic in [true, false]) {
    for (final includePrereleases in [false, true]) {
      for (final hasFullRelease in [true, false]) {
        test(
          '${automatic ? 'automatic' : 'manual'} check includes prereleases: '
          '$includePrereleases, '
          'with full release available: $hasFullRelease',
          () async {
            final repository = GitHubUpdateRepository(
              versionLoader: () async => _version('0.1.0+1'),
              fetcher: (_) async => jsonEncode([
                _jsonRelease('v9.0.0', prerelease: true),
                _jsonRelease('v8.0.0', draft: true),
                if (hasFullRelease) _jsonRelease('v0.2.0+1'),
              ]),
            );
            addTearDown(repository.close);
            final store = _CheckStore();
            final container = _container(
              repository,
              store,
              settings: _SettingsRepository()
                ..settings = AppSettings(
                  checkPrereleaseUpdates: includePrereleases,
                ),
            );
            final controller = container.read(
              appUpdateControllerProvider.notifier,
            );
            if (automatic) {
              await controller.checkOnStartup();
            } else {
              await controller.checkManually();
            }
            final state = container.read(appUpdateControllerProvider);
            expect(state.failure, isNull);
            final expectedVersion = includePrereleases
                ? '9.0.0'
                : hasFullRelease
                ? '0.2.0+1'
                : null;
            expect(state.pendingRelease?.version.label, expectedVersion);
            expect(
              store.promptedVersion,
              automatic
                  ? (includePrereleases
                        ? '9.0.0'
                        : hasFullRelease
                        ? '0.2.0'
                        : null)
                  : null,
            );
            if (expectedVersion == null) {
              expect(state.message, automatic ? null : '暂无已发布的正式版本');
            }
          },
        );
      }
    }
  }
  test(
    'checks wait for saved settings and honor later changes without restart',
    () async {
      final pending = Completer<AppSettings>();
      final settings = _SettingsRepository()..pending = pending;
      final repository = GitHubUpdateRepository(
        versionLoader: () async => _version('0.1.0+1'),
        fetcher: (_) async => jsonEncode([
          _jsonRelease('v9.0.0', prerelease: true),
          _jsonRelease('v0.2.0'),
        ]),
      );
      addTearDown(repository.close);
      final container = _container(
        repository,
        _CheckStore(),
        settings: settings,
      );
      final controller = container.read(appUpdateControllerProvider.notifier);
      final check = controller.checkOnStartup();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(appUpdateControllerProvider).checking, isTrue);
      expect(
        container.read(appUpdateControllerProvider).pendingRelease,
        isNull,
      );
      pending.complete(AppSettings(checkPrereleaseUpdates: true));
      await check;
      expect(
        container
            .read(appUpdateControllerProvider)
            .pendingRelease
            ?.version
            .label,
        '9.0.0',
      );
      expect(
        container.read(appUpdateControllerProvider).pendingRelease?.prerelease,
        isTrue,
      );
      final preferences = container.read(settingsControllerProvider.notifier);
      await preferences.setCheckPrereleaseUpdates(false);
      await controller.checkManually();
      expect(
        container
            .read(appUpdateControllerProvider)
            .pendingRelease
            ?.version
            .label,
        '0.2.0',
      );
      await preferences.setCheckPrereleaseUpdates(true);
      await controller.checkManually();
      expect(
        container
            .read(appUpdateControllerProvider)
            .pendingRelease
            ?.version
            .label,
        '9.0.0',
      );
    },
  );
  test(
    'opted-in manual check with only drafts reports no published versions',
    () async {
      final repository = GitHubUpdateRepository(
        versionLoader: () async => _version('0.1.0+1'),
        fetcher: (_) async => jsonEncode([_jsonRelease('v9.0.0', draft: true)]),
      );
      addTearDown(repository.close);
      final container = _container(
        repository,
        _CheckStore(),
        settings: _SettingsRepository()
          ..settings = AppSettings(checkPrereleaseUpdates: true),
      );
      await container
          .read(appUpdateControllerProvider.notifier)
          .checkManually();
      final state = container.read(appUpdateControllerProvider);
      expect(state.failure, isNull);
      expect(state.pendingRelease, isNull);
      expect(state.message, '暂无已发布的版本');
    },
  );
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
    expect(await store.claimAutomaticPrompt(_version('1.1.1+3')), isTrue);
    expect(
      await first.readSetting(SqliteUpdateCheckStore.lastPromptedVersionKey),
      '1.1.1',
    );
    await first.close();
    final second = AppDatabase(NativeDatabase(file));
    addTearDown(second.close);
    final restored = SqliteUpdateCheckStore(second);
    expect(await restored.claimStartupDay('2026-10-06'), isFalse);
    expect(await restored.claimStartupDay('2026-10-07'), isTrue);
    expect(await restored.claimAutomaticPrompt(_version('1.1.1+3')), isFalse);
    expect(await restored.claimAutomaticPrompt(_version('v1.1.1+4')), isFalse);
    expect(await restored.claimAutomaticPrompt(_version('1.1.2+0')), isTrue);
    expect(await restored.claimAutomaticPrompt(_version('1.1.1+99')), isFalse);
    expect(await restored.claimAutomaticPrompt(_version('1.2.0+0')), isTrue);
    expect(await restored.claimAutomaticPrompt(_version('2.0.0+0')), isTrue);
    expect(
      await second.readSetting('preferences.v1'),
      '{"font":"harmonyOsSans"}',
    );
    expect(second.schemaVersion, 3);
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
    expect(container.read(appUpdateControllerProvider).message, '暂无已发布的正式版本');
  });
  test('manual checks bypass automatic version reminders every time', () async {
    final repository = _UpdateRepository()..release = _release('1.1.1+4');
    final store = _CheckStore()..promptedVersion = '1.1.1';
    final container = _container(repository, store);
    final controller = container.read(appUpdateControllerProvider.notifier);
    await controller.checkOnStartup();
    expect(container.read(appUpdateControllerProvider).pendingRelease, isNull);
    for (var i = 0; i < 2; i++) {
      await controller.checkManually();
      expect(controller.takePendingRelease()?.version.label, '1.1.1+4');
      expect(
        container.read(appUpdateControllerProvider).message,
        '发现新版本 1.1.1+4',
      );
    }
    expect(repository.calls, 3);
  });
  test(
    'manual check joining automatic reminder storage still prompts',
    () async {
      final pending = Completer<bool>();
      final repository = _UpdateRepository()..release = _release('1.1.1+4');
      final store = _CheckStore()..pendingPrompt = pending;
      final container = _container(repository, store);
      final controller = container.read(appUpdateControllerProvider.notifier);
      final automatic = controller.checkOnStartup();
      await Future<void>.delayed(Duration.zero);
      final manual = controller.checkManually();
      expect(identical(automatic, manual), isTrue);
      pending.complete(false);
      await manual;
      expect(controller.takePendingRelease()?.version.label, '1.1.1+4');
      expect(repository.calls, 1);
    },
  );
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
      overrides: [
        appUpdateRepositoryProvider.overrideWithValue(repository),
        settingsRepositoryProvider.overrideWithValue(_SettingsRepository()),
      ],
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
  testWidgets('late reminder storage cannot prompt after the check deadline', (
    tester,
  ) async {
    final pending = Completer<bool>();
    final repository = _UpdateRepository()..release = _release('1.1.1+3');
    final container = _container(
      repository,
      _CheckStore()..pendingPrompt = pending,
    );
    final operation = container
        .read(appUpdateControllerProvider.notifier)
        .checkOnStartup();
    await tester.pump();
    await tester.pump(const Duration(seconds: 21));
    await operation;
    expect(repository.cancellation?.isCancelled, isTrue);
    pending.complete(true);
    await tester.pump();
    expect(container.read(appUpdateControllerProvider).pendingRelease, isNull);
    expect(container.read(appUpdateControllerProvider).message, isNull);
  });
  testWidgets(
    'automatic prompts persist across days and ignore build-only releases',
    (tester) async {
      final repository = _UpdateRepository();
      final store = _CheckStore();
      final opened = <Uri>[];
      var day = 6;
      for (final (version, shouldPrompt) in [
        ('1.1.1+3', true),
        ('1.1.1+3', false),
        ('1.1.1+4', false),
        ('1.1.2+0', true),
      ]) {
        repository.release = _release(version);
        await tester.pumpWidget(
          _app(repository, store, opened, now: DateTime(2026, 10, day++)),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(AlertDialog),
          shouldPrompt ? findsOneWidget : findsNothing,
          reason: version,
        );
        if (shouldPrompt) {
          expect(find.text('发现新版本 $version'), findsOneWidget);
          await tester.tap(find.text('稍后再说'));
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
      expect(repository.calls, 4);
      expect(opened, isEmpty);
      expect(tester.takeException(), isNull);
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
  for (final brightness in Brightness.values) {
    testWidgets(
      'Markdown release notes fit narrow windows with large text: $brightness',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 640);
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final repository = _UpdateRepository()
          ..release = _release(
            '0.2.0',
            notes:
                '''
## 更新亮点

改进**播放器**和更新面板。

- 修复播放
- 支持 `Markdown`

1. 下载新版
2. 覆盖安装

- [x] 支持格式

> 保留现有设置

| 平台 | 说明 |
| --- | --- |
| Windows | ${'long-table-cell-' * 12} |

```sh
${'long-code-line-' * 20}
```

说明末尾
''',
          );
        final opened = <Uri>[];
        await tester.pumpWidget(
          _app(repository, _CheckStore(), opened, brightness: brightness),
        );
        await tester.pumpAndSettle();
        expect(find.text('更新亮点'), findsOneWidget);
        expect(find.text('改进播放器和更新面板。'), findsOneWidget);
        expect(find.text('修复播放'), findsOneWidget);
        expect(find.text('支持 Markdown'), findsOneWidget);
        expect(find.text('覆盖安装'), findsOneWidget);
        expect(find.text('保留现有设置'), findsOneWidget);
        expect(find.byIcon(Icons.check_box), findsOneWidget);
        expect(find.byType(Table), findsOneWidget);
        expect(find.text(repository.release!.notes), findsNothing);
        final horizontalScrollables = find.byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
        );
        expect(horizontalScrollables, findsNWidgets(2));
        for (final state in tester.stateList<ScrollableState>(
          horizontalScrollables,
        )) {
          expect(state.position.maxScrollExtent, greaterThan(0));
        }
        await tester.ensureVisible(find.text('说明末尾'));
        await tester.pumpAndSettle();
        expect(find.text('说明末尾').hitTestable(), findsOneWidget);
        await tester.tap(find.text('稍后再说'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(opened, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('Markdown links open only on tap and reject local schemes', (
    tester,
  ) async {
    final repository = _UpdateRepository()
      ..release = _release(
        '0.2.0',
        notes: '''
[查看提交](https://github.com/CKopoer/BiliSail/compare/v0.1.0...v0.2.0)

[查看问题](/CKopoer/BiliSail/issues/123)

[本地文件](file:///private.txt)

[脚本链接](javascript:alert(1))
''',
      );
    final opened = <Uri>[];
    await tester.pumpWidget(_app(repository, _CheckStore(), opened));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    await tester.tap(find.text('查看提交'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看问题'));
    await tester.pumpAndSettle();
    expect(opened, [
      Uri.parse('https://github.com/CKopoer/BiliSail/compare/v0.1.0...v0.2.0'),
      Uri.parse('https://github.com/CKopoer/BiliSail/issues/123'),
    ]);
    for (final label in ['本地文件', '脚本链接']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    expect(opened, hasLength(2));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Markdown browser failure shows a notice', (tester) async {
    final repository = _UpdateRepository()
      ..release = _release('0.2.0', notes: '[查看文档](https://docs.flutter.dev)');
    await tester.pumpWidget(
      _app(repository, _CheckStore(), [], openSucceeds: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看文档'));
    await tester.pumpAndSettle();
    expect(find.text('无法打开浏览器，请稍后重试'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Markdown images cannot load files or bundled assets', (
    tester,
  ) async {
    final repository = _UpdateRepository()
      ..release = _release(
        '0.2.0',
        notes: '''
![本地图片](file:///private.png)

![内置资源](resource:assets/private.png)
''',
      );
    await tester.pumpWidget(_app(repository, _CheckStore(), []));
    await tester.pumpAndSettle();
    expect(find.text('本地图片'), findsOneWidget);
    expect(find.text('内置资源'), findsOneWidget);
    expect(find.byType(AppNetworkImage), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final notes in ['', ' \n ']) {
    testWidgets('empty release notes retain the download hint: "$notes"', (
      tester,
    ) async {
      final repository = _UpdateRepository()
        ..release = _release('0.2.0', notes: notes);
      await tester.pumpWidget(_app(repository, _CheckStore(), []));
      await tester.pumpAndSettle();
      expect(find.text('新版本已发布，可前往 Release 页面查看详情并下载。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
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
          _CheckStore()
            ..day = '2026-10-06'
            ..promptedVersion = '0.2.0',
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
  final requestedPrereleases = <bool>[];
  @override
  Future<AppVersion> installedVersion() async => _version('0.1.0+1');
  @override
  Future<AppRelease?> latestRelease(
    RequestCancellation token, {
    bool includePrereleases = false,
  }) async {
    calls++;
    requestedPrereleases.add(includePrereleases);
    cancellation = token;
    if (pending case final result?) return result.future;
    if (error case final failure?) throw failure;
    return release;
  }
}

final class _CheckStore implements UpdateCheckStore {
  String? day;
  String? promptedVersion;
  Completer<bool>? pendingPrompt;
  @override
  Future<bool> claimStartupDay(String value) async {
    if (value == day) return false;
    day = value;
    return true;
  }

  @override
  Future<bool> claimAutomaticPrompt(AppVersion version) async {
    if (pendingPrompt case final result?) return result.future;
    if (promptedVersion == version.baseVersion) return false;
    promptedVersion = version.baseVersion;
    return true;
  }
}

final class _SettingsRepository implements SettingsRepository {
  AppSettings settings = const AppSettings.defaults();
  Completer<AppSettings>? pending;
  bool failSave = false;
  @override
  Future<AppSettings> load() async => pending?.future ?? settings;
  @override
  Future<void> save(AppSettings value) async {
    if (failSave) throw StateError('disk');
    settings = value;
  }
}
