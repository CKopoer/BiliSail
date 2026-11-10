import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitType;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../presentation/window_input_focus.dart';
import 'detached_playback_window.dart';
import 'window_service.dart';

// macOS starts its engine without an implicit native controller. Its first window
// enables native multiview before any view controller is attached; later
// playback windows can then use that same engine, isolate and dependencies.
class MacOSApplicationWindow {
  MacOSApplicationWindow(this.window);

  static const _channel = MethodChannel('bilisail/application_window');
  final DetachedPlaybackWindow window;

  // Native code replays activation without a window only in explicit smoke.
  // Confirm the real engine disabled frames before testing main-window recovery.
  static Future<void> prepareHeadlessStartupProbe() async {
    final binding = WidgetsBinding.instance;
    final hidden = Completer<void>();
    final listener = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.hidden && !hidden.isCompleted) {
          hidden.complete();
        }
      },
    );
    try {
      await _channel
          .invokeMethod<void>('prepareHeadlessStartup')
          .timeout(const Duration(seconds: 5));
      if (binding.lifecycleState != AppLifecycleState.hidden) {
        await hidden.future.timeout(const Duration(seconds: 5));
      }
      if (binding.lifecycleState != AppLifecycleState.hidden ||
          binding.framesEnabled) {
        throw StateError('Headless startup probe did not disable frames');
      }
    } finally {
      listener.dispose();
    }
  }

  static Future<MacOSApplicationWindow?> create() async {
    if (!Platform.isMacOS) return null;
    await DetachedPlaybackWindow.prepareMacOSWindowing();
    var requestingExit = false;
    return MacOSApplicationWindow(
      DetachedPlaybackWindow.create(
        title: 'BiliSail',
        size: const Size(1120, 800),
        constraints: const BoxConstraints(minWidth: 420, minHeight: 560),
        onCloseRequested: () {
          if (requestingExit) return;
          requestingExit = true;
          // Cocoa calls this through the SDK's isolate-local FFI callback.
          // Leave windowShouldClose (including native tab closing) before an
          // exit request can reenter Cocoa and shut down the shared engine.
          Timer.run(() {
            unawaited(
              ServicesBinding.instance
                  .exitApplication(AppExitType.cancelable)
                  .whenComplete(() => requestingExit = false),
            );
          });
        },
      ),
    );
  }

  WindowService get service => window.windowService;

  Future<void> prepare() async {
    await _channel
        .invokeMethod<void>('attachMainWindow', {
          'viewId': window.viewId,
          'windowHandle': service.nativeWindowHandle,
        })
        .timeout(const Duration(seconds: 5));
    await WindowInputFocus.instance.synchronizeNativeFocusIfSupported();
  }

  Widget wrap(Widget app, {Widget? additionalView}) => window.buildView(
    WindowServiceScope(
      service: service,
      child: ViewAnchor(view: additionalView, child: app),
    ),
  );

  void present(Widget app, {Widget? additionalView}) {
    runWidget(wrap(app, additionalView: additionalView));
    WidgetsBinding.instance.platformDispatcher.scheduleFrame();
  }
}
