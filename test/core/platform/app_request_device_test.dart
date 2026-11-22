import 'package:bilisail/core/platform/app_request_device.dart';
import 'package:bilisail/core/platform/live_network.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.bilisail/app_request_device');
  const network = MethodChannel('dev.bilisail/live_network');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(network, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('default live quality follows the platform network rule', () async {
    for (final desktop in [TargetPlatform.windows, TargetPlatform.macOS]) {
      debugDefaultTargetPlatformOverride = desktop;
      expect(await defaultNetworkLiveQuality(), 250);
    }
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    for (final type in ['wifi', 'mobile', '']) {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'network': type},
      );
      expect(await defaultNetworkLiveQuality(), type == 'wifi' ? 10000 : 250);
    }
    messenger.setMockMethodCallHandler(channel, null);
    expect(await defaultNetworkLiveQuality(), 10000);
    for (final platform in [TargetPlatform.iOS, TargetPlatform.linux]) {
      debugDefaultTargetPlatformOverride = platform;
      for (final original in [true, false]) {
        messenger.setMockMethodCallHandler(network, (call) async {
          expect(call.method, 'preferOriginal');
          return original;
        });
        expect(await defaultNetworkLiveQuality(), original ? 10000 : 250);
      }
      messenger.setMockMethodCallHandler(
        network,
        (_) async => throw PlatformException(code: 'unavailable'),
      );
      expect(await defaultNetworkLiveQuality(), 10000);
    }
  });

  test('Android reads current public device facts on every request', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var mobile = false;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'model': 'Pixel 9',
        'osVersion': '16',
        'network': mobile ? 'mobile' : 'wifi',
      },
    );
    const service = AppRequestDevice();
    final wifi = await service.load();
    expect(wifi.model, 'Pixel 9');
    expect(wifi.osVersion, '16');
    expect(wifi.network, 'wifi');
    mobile = true;
    expect((await service.load()).network, 'mobile');
  });

  test(
    'non Android uses the fixed profile without invoking a native channel',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw StateError('unused'),
      );
      final info = await const AppRequestDevice().load();
      expect(info.model, 'android_hd');
      expect(info.osVersion, '15');
    },
  );

  test('unavailable native facts remain unknown and control characters are rejected', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'model': 'bad\r\nheader',
        'osVersion': '16',
        'network': 'unrecognised',
      },
    );
    final info = await const AppRequestDevice().load();
    expect(info.model, 'android');
    expect(info.network, isEmpty);
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'unavailable'),
    );
    expect((await const AppRequestDevice().load()).network, isEmpty);
  });
}
