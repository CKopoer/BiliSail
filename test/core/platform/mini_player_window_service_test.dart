import 'dart:async';

import 'package:bilisail/core/platform/window_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'borderless desktop handle requests bottom-right native resizing',
    () async {
      const manager = MethodChannel('window_manager');
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(manager, (call) async {
            received = call;
            return false;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(manager, null),
      );
      await _ResizeWindow().startResizingMiniPlayer();
      expect(received?.method, 'startResizing');
      expect(
        (received?.arguments as Map<Object?, Object?>)['resizeEdge'],
        'bottomRight',
      );
    },
  );
  const channel = MethodChannel('bilisail/desktop_window');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test(
    'restore waits for pending enter and returns original pin state',
    () async {
      final entering = Completer<void>();
      final calls = <bool>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'setMiniPlayer') {
              final enabled =
                  (call.arguments as Map<Object?, Object?>)['enabled'] as bool;
              calls.add(enabled);
              if (enabled) await entering.future;
            }
            return null;
          });
      final window = _Window();
      final first = window.setMiniPlayer(true);
      await Future<void>.delayed(Duration.zero);
      final restore = window.setMiniPlayer(false);
      expect(calls, [true]);
      expect(window.miniPlayer.value, isFalse);
      entering.complete();
      await Future.wait([first, restore]);
      expect(calls, [true, false]);
      expect(window.miniPlayer.value, isFalse);
      expect(window.alwaysOnTop.value, isFalse);
    },
  );

  test(
    'failed native transition rolls constraints back and leaves mode unchanged',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'window_unavailable');
          });
      final window = _Window();
      final constraints = <bool>[];
      window.configureMiniPlayerConstraints = (enabled) async =>
          constraints.add(enabled);
      await expectLater(
        window.setMiniPlayer(true),
        throwsA(isA<PlatformException>()),
      );
      expect(constraints, [true, false]);
      expect(window.miniPlayer.value, isFalse);
      expect(window.alwaysOnTop.value, isFalse);
    },
  );
}

class _Window extends WindowService {
  @override
  bool get hasDesktopWindow => true;
}

class _ResizeWindow extends _Window {
  @override
  bool get hasMiniPlayerResizeHandle => true;
}
