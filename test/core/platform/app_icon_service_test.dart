import 'package:bilisail/core/platform/app_icon_service.dart';
import 'package:bilisail/domain/app_icon.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const service = NativeAppIconService();
  final calls = <MethodCall>[];
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeAppIconService.channel, (call) async {
          calls.add(call);
          return call.method == 'getIcon' ? 'bilibili' : null;
        });
  });
  tearDown(() {
    calls.clear();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeAppIconService.channel, null);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      '$platform restores OS icon without triggering an icon change',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        expect(
          await service.restore(AppIconPreference.bilisail),
          AppIconPreference.bilibili,
        );
        expect(calls.map((call) => call.method), ['getIcon']);
        await service.apply(AppIconPreference.bilisail);
        expect(calls.last.arguments, {'icon': 'bilisail'});
      },
    );
  }
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  ]) {
    test('$platform reapplies saved desktop icon', () async {
      debugDefaultTargetPlatformOverride = platform;
      expect(
        await service.restore(AppIconPreference.bilibili),
        AppIconPreference.bilibili,
      );
      expect(calls.single.method, 'setIcon');
      expect((calls.single.arguments as Map)['icon'], 'bilibili');
      if (platform != TargetPlatform.windows) {
        expect((calls.single.arguments as Map)['image'], isA<Uint8List>());
      }
    });
  }
}
