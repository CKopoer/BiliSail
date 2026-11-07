import 'dart:convert';

import 'package:bilisail/core/platform/gpu_device_catalog.dart';
import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/domain/gpu_device_catalog.dart';
import 'package:bilisail/features/settings/application/gpu_devices_controller.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/data/sqlite_settings_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_category.dart';
import 'package:bilisail/features/settings/presentation/gpu_device_setting.dart';
import 'package:bilisail/features/settings/presentation/settings_screen.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_settings_repository.dart';

const _integrated = GpuDevice(
  id: 'dxgi:intel',
  name: 'Intel Graphics',
  index: 0,
);
const _discrete = GpuDevice(id: 'dxgi:amd', name: 'AMD Radeon', index: 1);

final class _Catalog implements GpuDeviceCatalog {
  @override
  bool supported = true;
  List<GpuDevice> devices = [_integrated, _discrete];
  int calls = 0;
  bool fail = false;

  @override
  Future<List<GpuDevice>> loadDevices() async {
    calls++;
    if (fail) throw StateError('GPU catalog unavailable');
    return devices;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'resolve the hardware identity against fresh indices and missing GPUs',
    () async {
      final catalog = _Catalog();
      expect(await resolveFvpGpuDevice(catalog, ''), isNull);
      expect(catalog.calls, 0);
      expect(await resolveFvpGpuDevice(catalog, _discrete.id), 1);
      catalog.devices = [
        GpuDevice(id: _discrete.id, name: _discrete.name, index: 0),
      ];
      expect(await resolveFvpGpuDevice(catalog, _discrete.id), 0);
      expect(await resolveFvpGpuDevice(catalog, _integrated.id), isNull);
      catalog.fail = true;
      await expectLater(
        resolveFvpGpuDevice(catalog, _discrete.id),
        throwsStateError,
      );
      catalog.supported = false;
      expect(await resolveFvpGpuDevice(catalog, _discrete.id), isNull);
    },
  );

  test(
    'GPU preference migrates, survives unrelated settings and resets',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = SqliteSettingsRepository(database);
      for (final value in [
        null,
        123,
        ['bad'],
        'x' * 257,
      ]) {
        await database.writeSetting(
          'preferences.v1',
          jsonEncode({
            'schemaVersion': 42,
            'fvpGpuDeviceId': value,
            'playbackBackend': 'fvp',
            'videoDecoding': 'software',
            'defaultVolume': 37,
          }),
        );
        final loaded = await repository.load();
        expect(loaded.fvpGpuDeviceId, '');
        expect(loaded.playbackBackend, PlaybackBackendPreference.fvp);
        expect(loaded.videoDecoding, VideoDecodingPreference.software);
        expect(loaded.defaultVolume, 37);
      }
      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);
      final controller = container.read(settingsControllerProvider.notifier);
      await controller.setFvpGpuDevice(_discrete.id);
      await controller.setTheme(AppThemePreference.dark);
      await controller.setPlaybackBackend(PlaybackBackendPreference.mediaKit);
      expect((await repository.load()).fvpGpuDeviceId, _discrete.id);
      await controller.resetToDefaults();
      final reset = await repository.load();
      expect(reset.fvpGpuDeviceId, '');
      expect(reset.playbackBackend, PlaybackBackendPreference.mediaKit);
      expect(reset.videoDecoding, VideoDecodingPreference.automatic);
    },
  );

  testWidgets(
    'native catalog validates device replies and excludes unsupported platforms',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Object? response = [
        {'id': _discrete.id, 'name': _discrete.name, 'index': 1},
      ];
      messenger.setMockMethodCallHandler(NativeGpuDeviceCatalog.channel, (
        call,
      ) async {
        expect(call.method, 'listDevices');
        return response;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          NativeGpuDeviceCatalog.channel,
          null,
        ),
      );
      const catalog = NativeGpuDeviceCatalog();
      final devices = await catalog.loadDevices();
      expect(devices.single.id, _discrete.id);
      expect(devices.single.index, 1);
      for (final invalid in [
        null,
        {},
        [
          {'id': '', 'name': 'GPU', 'index': 0},
        ],
        [
          {'id': 'gpu', 'name': 'GPU', 'index': -1},
        ],
      ]) {
        response = invalid;
        await expectLater(catalog.loadDevices(), throwsFormatException);
      }
      messenger.setMockMethodCallHandler(
        NativeGpuDeviceCatalog.channel,
        (_) async => throw PlatformException(code: 'unavailable'),
      );
      await expectLater(
        catalog.loadDevices(),
        throwsA(isA<PlatformException>()),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'only fvp enumerates devices; selection, rollback, missing GPU and refresh',
    (tester) async {
      final catalog = _Catalog();
      final repository = MemorySettingsRepository();
      late WidgetRef settingsRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(repository),
            gpuDeviceCatalogProvider.overrideWithValue(catalog),
          ],
          child: MaterialApp(
            builder: AppNoticeHost.builder,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  settingsRef = ref;
                  final settings = ref
                      .watch(settingsControllerProvider)
                      .asData
                      ?.value;
                  return settings == null
                      ? const SizedBox.shrink()
                      : GpuDeviceSetting(settings: settings);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(catalog.calls, 0);
      expect(find.textContaining('直通硬解跟随'), findsOneWidget);
      final controller = settingsRef.read(settingsControllerProvider.notifier);
      await controller.setPlaybackBackend(PlaybackBackendPreference.fvp);
      await tester.pumpAndSettle();
      expect(catalog.calls, 1);
      await tester.tap(find.text('AMD Radeon（设备 1）'));
      await tester.pumpAndSettle();
      expect(repository.value.fvpGpuDeviceId, _discrete.id);
      repository.failWrites = true;
      await tester.tap(find.text('Intel Graphics（设备 0）'));
      await tester.pumpAndSettle();
      expect(repository.value.fvpGpuDeviceId, _discrete.id);
      expect(
        tester
            .widget<ChoiceChip>(
              find.ancestor(
                of: find.text('AMD Radeon（设备 1）'),
                matching: find.byType(ChoiceChip),
              ),
            )
            .selected,
        true,
      );
      repository.failWrites = false;
      catalog.devices = [_integrated];
      await tester.tap(find.text('刷新 GPU 设备'));
      await tester.pumpAndSettle();
      expect(find.textContaining('已保存的 GPU 当前不可用'), findsOneWidget);
      expect(repository.value.fvpGpuDeviceId, _discrete.id);
      catalog.fail = true;
      await tester.tap(find.text('刷新 GPU 设备'));
      await tester.pumpAndSettle();
      expect(find.textContaining('无法读取 GPU 设备'), findsOneWidget);
      catalog.fail = false;
      await tester.tap(find.text('自动选择'));
      await tester.pumpAndSettle();
      expect(repository.value.fvpGpuDeviceId, '');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'software mode hides hardware controls and keeps codec, audio and saved choices',
    (tester) async {
      final repository = MemorySettingsRepository()
        ..value = AppSettings(
          playbackBackend: PlaybackBackendPreference.fvp,
          fvpGpuDeviceId: _discrete.id,
          androidVideoOutput: AndroidVideoOutputPreference.directTexture,
        );
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
      await tester.scrollUntilVisible(
        find.text('软件解码'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('视频解码方式')).dy,
        lessThan(tester.getTopLeft(find.text('播放后端')).dy),
      );
      await tester.tap(find.text('软件解码'));
      await tester.pumpAndSettle();
      expect(find.text('播放后端'), findsNothing);
      expect(find.text('GPU 设备'), findsNothing);
      expect(find.text('Android 视频输出'), findsNothing);
      expect(find.text('优先视频编码'), findsOneWidget);
      expect(find.text('优先音质'), findsOneWidget);
      expect(repository.value.playbackBackend, PlaybackBackendPreference.fvp);
      expect(repository.value.fvpGpuDeviceId, _discrete.id);
      await tester.ensureVisible(find.text('硬件解码（优先）'));
      await tester.tap(find.text('硬件解码（优先）'));
      await tester.pumpAndSettle();
      expect(find.text('播放后端'), findsOneWidget);
      expect(find.text('GPU 设备'), findsOneWidget);
      expect(
        repository.value.androidVideoOutput,
        AndroidVideoOutputPreference.directTexture,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
