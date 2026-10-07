import 'package:bilisail/core/platform/window_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final orientation in FullScreenOrientation.values) {
    test(
      'mobile fullscreen applies $orientation and restores system policy',
      () async {
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              calls.add(call);
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });
        final window = _MobileWindowService();
        await window.setFullScreen(true, orientation: orientation);
        expect(window.isFullScreen, isTrue);
        expect(calls[0].method, 'SystemChrome.setPreferredOrientations');
        expect(
          calls[0].arguments,
          orientation == FullScreenOrientation.landscape
              ? [
                  'DeviceOrientation.landscapeLeft',
                  'DeviceOrientation.landscapeRight',
                ]
              : ['DeviceOrientation.portraitUp'],
        );
        expect(calls[1].method, 'SystemChrome.setEnabledSystemUIMode');
        expect(calls[1].arguments, 'SystemUiMode.immersiveSticky');
        await window.setFullScreen(false);
        expect(window.isFullScreen, isFalse);
        expect(calls[2].method, 'SystemChrome.setPreferredOrientations');
        expect(calls[2].arguments, isEmpty);
        expect(calls[3].arguments, 'SystemUiMode.edgeToEdge');
      },
    );
  }
}

class _MobileWindowService extends WindowService {
  @override
  bool get hasDesktopWindow => false;
}
