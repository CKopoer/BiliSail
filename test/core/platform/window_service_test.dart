import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse, AppExitType;

import 'package:bilisail/core/platform/window_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/native_window_events.dart';
import '../../support/window_service_fake.dart';

void main() {
  final binding = _WindowExitTestBinding();

  testWidgets('main close waits for application cleanup with playback open', (
    tester,
  ) async {
    const channel = MethodChannel('window_manager');
    const exitChannel = MethodChannel('bilisail/application_exit');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      exitChannel,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        exitChannel,
        null,
      ),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final main = WindowService();
    addTearDown(main.dispose);
    await main.initialize();
    expect(
      calls.where((call) => call.method == 'setCloseHandler').single.arguments,
      true,
    );
    // SDK-managed playback views must not take over the implicit main window's
    // close listener or use window_manager, which only targets that main HWND.
    final playback = WindowService.forView(
      viewId: 71,
      setFullScreen: (_) async {},
      activate: () async {},
    );
    addTearDown(playback.dispose);
    final initializationCalls = calls.length;
    await playback.initialize();
    expect(calls, hasLength(initializationCalls));

    var cleanupCalls = 0;
    var exitCalls = 0;
    var exitCompleted = false;
    var cleanup = Completer<AppExitResponse>();
    final lifecycle = AppLifecycleListener(
      onExitRequested: () {
        cleanupCalls++;
        return cleanup.future;
      },
    );
    addTearDown(lifecycle.dispose);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method != 'System.exitApplication') return null;
        expect(call.arguments, {'type': 'cancelable', 'exitCode': 0});
        exitCalls++;
        final response = await tester.binding.handleRequestAppExit();
        exitCompleted = true;
        return {'response': response.name};
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    Future<void> closeMainWindow() async {
      const codec = StandardMethodCodec();
      final response = await tester.binding.defaultBinaryMessenger
          .handlePlatformMessage(
            'bilisail/application_exit',
            codec.encodeMethodCall(const MethodCall('closeRequested')),
            null,
          );
      if (response != null) codec.decodeEnvelope(response);
    }

    await closeMainWindow();
    await closeMainWindow();
    expect(exitCalls, 1);
    expect(cleanupCalls, 1);
    expect(exitCompleted, isFalse);
    cleanup.complete(AppExitResponse.cancel);
    await binding.lastExit;
    expect(exitCompleted, isTrue);

    // A cancelled attempt can be requested again. Keep the native guard until
    // cleanup completes, then detach it from the main window.
    cleanup = Completer<AppExitResponse>();
    exitCompleted = false;
    await closeMainWindow();
    await tester.pump();
    expect(exitCalls, 2);
    expect(cleanupCalls, 2);
    expect(exitCompleted, isFalse);
    await closeMainWindow();
    expect(exitCalls, 2);
    expect(
      calls.where((call) => call.method == 'setCloseHandler'),
      hasLength(1),
    );
    cleanup.complete(AppExitResponse.exit);
    await binding.lastExit;
    expect(exitCompleted, isTrue);
    await main.dispose();
    expect(
      calls.where((call) => call.method == 'setCloseHandler').last.arguments,
      false,
    );
    await closeMainWindow();
    expect(exitCalls, 2);
  }, skip: !Platform.isWindows);

  testWidgets(
    'managed main window never initializes the legacy window plugin',
    (tester) async {
      final pluginCalls = <MethodCall>[];
      const channel = MethodChannel('window_manager');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        pluginCalls.add(call);
        throw StateError('window_manager must not own a managed window');
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      var activations = 0;
      final fullscreen = <bool>[];
      final main = WindowService.forView(
        viewId: 41,
        setFullScreen: (value) async => fullscreen.add(value),
        activate: () async => activations++,
      );
      await main.initialize();
      await main.activate();
      await main.setFullScreen(true);
      await main.setFullScreen(false);
      expect(pluginCalls, isEmpty);
      expect(activations, 1);
      expect(fullscreen, [true, false]);
    },
  );

  testWidgets(
    'playback caption calls target one view and stop after retirement',
    (tester) async {
      const channel = MethodChannel('bilisail/desktop_window');
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      var available = true;
      final window = WindowService.forView(
        viewId: 71,
        setFullScreen: (_) async {},
        activate: () async {},
        isAvailable: () => available,
      );
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );
      await window.configurePlaybackTitleBar();
      await window.startDraggingPlaybackWindow();
      await window.togglePlaybackWindowMaximized();
      await window.minimizePlaybackWindow();
      expect(
        calls.map((call) => call.method),
        Platform.isWindows
            ? [
                'setPlaybackTitleBar',
                'startDragging',
                'toggleMaximized',
                'minimize',
              ]
            : isEmpty,
      );
      for (final call in calls) {
        expect(call.arguments, {
          'viewId': 71,
          if (call.method == 'setPlaybackTitleBar') 'dark': true,
        });
      }
      await window.configurePlaybackTitleBar(
        brightness: Brightness.light,
        backgroundColor: const Color(0xfff5f7fb),
      );
      if (Platform.isWindows) {
        expect(calls.last.arguments, {
          'viewId': 71,
          'dark': false,
          'backgroundColor': 0xf5f7fb,
        });
      }
      calls.clear();
      available = false;
      await window.configurePlaybackTitleBar();
      await window.startDraggingPlaybackWindow();
      await window.togglePlaybackWindowMaximized();
      await window.minimizePlaybackWindow();
      expect(calls, isEmpty);
      await WindowService().configurePlaybackTitleBar();
      expect(calls, isEmpty);
    },
  );

  testWidgets('geometry returns the physical size for the first scene', (
    tester,
  ) async {
    const channel = MethodChannel('bilisail/desktop_window');
    Object? reply;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'restoreGeometry' ? reply : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final window = WindowService.forView(
      viewId: 62,
      setFullScreen: (_) async {},
      activate: () async {},
    );
    expect(await window.restorePlaybackGeometry(), isNull);
    reply = [1920.0, 1032.0];
    expect(await window.restorePlaybackGeometry(), const Size(1920, 1032));
    reply = [1920.0, -1.0];
    await expectLater(window.restorePlaybackGeometry(), throwsFormatException);
    await window.retirePlaybackGeometry();
  });

  testWidgets('geometry remembers zoom through minimize and fullscreen', (
    tester,
  ) async {
    const channel = MethodChannel('bilisail/desktop_window');
    final captures = <Map<Object?, Object?>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'captureGeometry' || call.method == 'saveGeometry') {
        captures.add(call.arguments as Map<Object?, Object?>);
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final window = WindowService.forView(
      viewId: 61,
      setFullScreen: (_) async {},
      activate: () async {},
    );
    await window.restorePlaybackGeometry();
    window.updateWindowPresentation(
      maximized: true,
      minimized: false,
      fullScreen: false,
    );
    await window.capturePlaybackGeometry();
    window.updateWindowPresentation(
      maximized: false,
      minimized: true,
      fullScreen: false,
    );
    await window.capturePlaybackGeometry();
    window.updateWindowPresentation(
      maximized: false,
      minimized: false,
      fullScreen: true,
    );
    await window.savePlaybackGeometry();
    expect(captures.map((capture) => capture['maximized']), [true, true, true]);

    await window.restorePlaybackGeometry();
    window.updateWindowPresentation(
      maximized: false,
      minimized: false,
      fullScreen: false,
    );
    await window.savePlaybackGeometry();
    expect(captures.last['maximized'], isFalse);
    expect(captures.map((capture) => capture['owner']).toSet(), hasLength(1));
  });

  testWidgets(
    'geometry lifecycle carries a distinct view owner and captures before fullscreen',
    (tester) async {
      const channel = MethodChannel('bilisail/desktop_window');
      final calls = <MethodCall>[];
      final order = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        order.add(call.method);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      WindowService service() => WindowService.forView(
        viewId: 41,
        nativeWindowHandle: 99,
        setFullScreen: (value) async => order.add('fullscreen:$value'),
        activate: () async {},
      );
      final first = service();
      await first.restorePlaybackGeometry();
      await first.capturePlaybackGeometry();
      await first.setFullScreen(true);
      await first.setFullScreen(false);
      await first.savePlaybackGeometry();
      await first.capturePlaybackGeometry();
      expect(order, [
        'restoreGeometry',
        'captureGeometry',
        'captureGeometry',
        'fullscreen:true',
        'fullscreen:false',
        if (Platform.isWindows)
          'saveGeometry'
        else ...[
          'captureGeometry',
          'retireGeometry',
        ],
      ]);
      final owner = (calls.first.arguments as Map)['owner'];
      for (final call in calls) {
        expect(call.arguments, {
          'viewId': 41,
          'windowHandle': 99,
          'owner': owner,
        });
      }
      await service().restorePlaybackGeometry();
      expect((calls.last.arguments as Map)['owner'], isNot(owner));
      final count = calls.length;
      await WindowService().restorePlaybackGeometry();
      expect(calls, hasLength(count));
    },
  );

  testWidgets('save retains its original owner while a new window prepares', (
    tester,
  ) async {
    const channel = MethodChannel('bilisail/desktop_window');
    final capture = Completer<void>();
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'captureGeometry' || call.method == 'saveGeometry') {
        await capture.future;
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    WindowService service() => WindowService.forView(
      viewId: 51,
      setFullScreen: (_) async {},
      activate: () async {},
    );
    final old = service(), current = service();
    await old.restorePlaybackGeometry();
    final saving = old.savePlaybackGeometry();
    await tester.pump();
    expect(calls.map((call) => call.method), [
      'restoreGeometry',
      Platform.isWindows ? 'saveGeometry' : 'captureGeometry',
    ]);
    await current.restorePlaybackGeometry();
    final currentOwner = (calls.last.arguments as Map)['owner'];
    capture.complete();
    await saving;
    final oldOwner = (calls.first.arguments as Map)['owner'];
    if (Platform.isWindows) {
      expect(calls.map((call) => call.method), [
        'restoreGeometry',
        'saveGeometry',
        'restoreGeometry',
      ]);
      expect((calls[1].arguments as Map)['owner'], oldOwner);
      expect((calls.last.arguments as Map)['owner'], currentOwner);
    } else {
      expect(calls.last.method, 'retireGeometry');
      expect((calls.last.arguments as Map)['owner'], oldOwner);
    }
    expect(oldOwner, isNot(currentOwner));
  });

  testWidgets(
    'missing geometry reply times out before fullscreen mutates the controller',
    (tester) async {
      const channel = MethodChannel('bilisail/desktop_window');
      final capture = Completer<void>();
      var fullscreens = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'captureGeometry') await capture.future;
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final window = WindowService.forView(
        viewId: 52,
        setFullScreen: (_) async => fullscreens++,
        activate: () async {},
      );
      await window.restorePlaybackGeometry();
      final failed = expectLater(
        window.setFullScreen(true),
        throwsA(isA<TimeoutException>()),
      );
      await tester.pump(const Duration(seconds: 3));
      await failed;
      expect(fullscreens, 0);
      expect(window.isFullScreen, isFalse);
      capture.complete();
      await window.retirePlaybackGeometry();
    },
  );

  for (final unavailableReply in [false, true]) {
    testWidgets(
      'retirement cancels fullscreen after delayed capture unavailable=$unavailableReply',
      (tester) async {
        const channel = MethodChannel('bilisail/desktop_window');
        final capture = Completer<void>();
        var available = true;
        var fullscreens = 0;
        var activations = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'captureGeometry') await capture.future;
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final window = WindowService.forView(
          viewId: 42,
          isAvailable: () => available,
          setFullScreen: (_) async => fullscreens++,
          activate: () async => activations++,
        );
        await window.restorePlaybackGeometry();
        final entering = window.setFullScreen(true);
        await tester.pump();
        available = false;
        await window.retirePlaybackGeometry();
        if (unavailableReply) {
          capture.completeError(PlatformException(code: 'window_unavailable'));
        } else {
          capture.complete();
        }
        await entering;
        await window.activate();
        expect(fullscreens, 0);
        expect(activations, 0);
        expect(window.isFullScreen, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('native Back routes by view and retires with its binding owner', (
    tester,
  ) async {
    const channel = MethodChannel('bilisail/desktop_window');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    var available = true;
    WindowService service(int id) => FakePlaybackWindowService(
      viewId: id,
      setFullScreen: (_) async {},
      activate: () async {},
      isAvailable: () => available,
    );
    final first = service(21), second = service(22);
    final firstOwner = Object(), secondOwner = Object();
    var firstBacks = 0, secondBacks = 0;
    var firstHomes = 0, secondHomes = 0;
    await first.bindTitleBarBack(
      owner: firstOwner,
      onBack: () => firstBacks++,
      onHome: () => firstHomes++,
    );
    await second.bindTitleBarBack(
      owner: secondOwner,
      onBack: () => secondBacks++,
      onHome: () => secondHomes++,
    );
    expect(
      calls
          .where((call) => call.method == 'setBackButton')
          .every(
            (call) =>
                (call.arguments as Map<Object?, Object?>)['showHome'] == true,
          ),
      isTrue,
    );
    await sendNativeWindowBack(tester, 21);
    expect([firstBacks, secondBacks], [1, 0]);
    await sendNativeWindowHome(tester, 21);
    await sendNativeWindowHome(tester, 22);
    expect([firstHomes, secondHomes], [1, 1]);
    await first.unbindTitleBarBack(Object());
    await sendNativeWindowBack(tester, 21);
    expect(firstBacks, 2);
    await first.bindTitleBarBack(
      owner: firstOwner,
      onBack: () => firstBacks++,
      enabled: false,
      onHome: () => firstHomes++,
    );
    await sendNativeWindowBack(tester, 21);
    await sendNativeWindowBack(tester, 22);
    expect([firstBacks, secondBacks], [2, 1]);
    await sendNativeWindowHome(tester, 21);
    expect(firstHomes, 1);
    available = false;
    await sendNativeWindowBack(tester, 22);
    expect(secondBacks, 1);
    await sendNativeWindowHome(tester, 22);
    expect(secondHomes, 1);
    await first.unbindTitleBarBack(firstOwner);
    await second.unbindTitleBarBack(secondOwner);
    await sendNativeWindowBack(tester, 21);
    await sendNativeWindowBack(tester, 22);
    expect([firstBacks, secondBacks], [2, 1]);
    await sendNativeWindowHome(tester, 21);
    await sendNativeWindowHome(tester, 22);
    expect([firstHomes, secondHomes], [1, 1]);
    expect(
      calls.where((call) => call.method == 'removeBackButton'),
      hasLength(2),
    );
  });

  testWidgets(
    'failed native caption installation is visible and not routable',
    (tester) async {
      const channel = MethodChannel('bilisail/desktop_window');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'caption_unavailable'),
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final window = FakePlaybackWindowService(
        viewId: 31,
        setFullScreen: (_) async {},
        activate: () async {},
      );
      var backs = 0;
      await expectLater(
        window.bindTitleBarBack(owner: Object(), onBack: () => backs++),
        throwsA(isA<PlatformException>()),
      );
      await sendNativeWindowBack(tester, 31);
      expect(backs, 0);
    },
  );

  test('late IME reply is cancelled only after its own view retires', () async {
    const channel = MethodChannel('bilisail/text_input');
    var available = true;
    final reply = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          await reply.future;
          throw PlatformException(code: 'window_unavailable');
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final service = WindowService.forView(
      viewId: 2,
      setFullScreen: (_) async {},
      activate: () async {},
      isAvailable: () => available,
    );
    final pending = service.setTextInputActive(true);
    available = false;
    reply.complete();
    await pending;
    await service.setTextInputActive(false);
    available = true;
    await expectLater(
      service.setTextInputActive(true),
      throwsA(isA<PlatformException>()),
    );
  }, skip: !Platform.isWindows);

  test('Windows sends ordered IME policies to the native view', () async {
    const channel = MethodChannel('bilisail/text_input');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final window = WindowService();
    await window.setTextInputActive(false);
    await window.setTextInputActive(true);
    expect(calls.map((call) => call.method), ['setActive', 'setActive']);
    expect(calls.map((call) => call.arguments), [false, true]);
  }, skip: !Platform.isWindows);

  test(
    'detached fullscreen and activation stay on their target view',
    () async {
      final changes = <bool>[];
      var activations = 0;
      final main = WindowService();
      final playback = WindowService.forView(
        viewId: 12,
        setFullScreen: (value) async => changes.add(value),
        activate: () async => activations++,
      );
      await playback.setFullScreen(true);
      expect(playback.isFullScreen, isTrue);
      expect(main.isFullScreen, isFalse);
      await playback.activate();
      await playback.setFullScreen(false);
      expect(changes, [true, false]);
      expect(activations, 1);
      expect(playback.hasCustomTitleBar, isFalse);
    },
  );

  test('Windows routes a detached IME policy by view ID', () async {
    const channel = MethodChannel('bilisail/text_input');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final playback = WindowService.forView(
      viewId: 12,
      setFullScreen: (_) async {},
      activate: () async {},
    );
    await playback.setTextInputActive(true);
    expect(calls.single.arguments, {'active': true, 'viewId': 12});
  }, skip: !Platform.isWindows);

  testWidgets('window scope supplies only the current subtree', (tester) async {
    final window = WindowService();
    WindowService? inside;
    WindowService? outside;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          outside = WindowServiceScope.maybeOf(context);
          return WindowServiceScope(
            service: window,
            child: Builder(
              builder: (context) {
                inside = WindowServiceScope.maybeOf(context);
                return const SizedBox();
              },
            ),
          );
        },
      ),
    );
    expect(outside, isNull);
    expect(inside, same(window));
  });

  test(
    'mobile fullscreen without a lock leaves orientation policy alone',
    () async {
      final calls = <MethodCall>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final window = _MobileWindowService();
      await window.setFullScreen(true);
      await window.setFullScreen(false);
      await window.setFullScreen(false);
      expect(window.isFullScreen, isFalse);
      expect(
        calls.where(
          (call) => call.method == 'SystemChrome.setPreferredOrientations',
        ),
        isEmpty,
      );
      expect(calls.map((call) => call.arguments), [
        'SystemUiMode.immersiveSticky',
        'SystemUiMode.edgeToEdge',
        'SystemUiMode.edgeToEdge',
      ]);
    },
  );

  test(
    'mobile fullscreen can release its lock before leaving fullscreen',
    () async {
      final orientations = <Object?>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            orientations.add(call.arguments);
          }
          return null;
        },
      );
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final window = _MobileWindowService();
      await window.setFullScreen(
        true,
        orientation: FullScreenOrientation.landscape,
      );
      await window.setFullScreen(true);
      expect(window.isFullScreen, isTrue);
      await window.setFullScreen(false);
      expect(orientations, [
        ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight'],
        <String>[],
      ]);
    },
  );

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

// The standard test binding cancels exitApplication without calling the
// platform channel. Keep this suite on the real request/response contract.
class _WindowExitTestBinding extends AutomatedTestWidgetsFlutterBinding {
  Future<AppExitResponse>? lastExit;

  @override
  Future<AppExitResponse> exitApplication(
    AppExitType exitType, [
    int exitCode = 0,
  ]) => lastExit = _exitApplication(exitType, exitCode);

  Future<AppExitResponse> _exitApplication(
    AppExitType exitType,
    int exitCode,
  ) async {
    final response = await SystemChannels.platform
        .invokeMethod<Map<String, Object?>>('System.exitApplication', {
          'type': exitType.name,
          'exitCode': exitCode,
        });
    return response?['response'] == 'exit'
        ? AppExitResponse.exit
        : AppExitResponse.cancel;
  }
}

class _MobileWindowService extends WindowService {
  @override
  bool get hasDesktopWindow => false;
}
