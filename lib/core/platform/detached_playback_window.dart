// The application pins Flutter 3.47.6. Keep its experimental windowing API
// behind this adapter so an SDK update has one explicit compatibility boundary.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/src/foundation/_features.dart' as flutter_features;
import 'package:flutter/src/widgets/_window.dart' as flutter_window;
import 'package:flutter/src/widgets/_window_macos.dart' as flutter_macos;
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import '../presentation/window_input_focus.dart';
import 'window_service.dart';

typedef DetachedPlaybackWindowFactory = DetachedPlaybackWindow Function({
  required String title,
  required VoidCallback onCloseRequested,
});

abstract class DetachedPlaybackWindow extends ChangeNotifier {
  static bool _windowingReady = false;
  static bool _macOSWindowingReady = false;

  static Future<void> prepareMacOSWindowing() async {
    _macOSWindowingReady = false;
    final ready = await const MethodChannel('bilisail/application_window')
        .invokeMethod<bool>('prepareWindowing')
        .timeout(const Duration(seconds: 5));
    if (ready != true) {
      throw UnsupportedError(
        'macOS engine already has an implicit controller.',
      );
    }
    _macOSWindowingReady = true;
  }

  // Flutter 3.47.6's macOS create-window entry point calls enableMultiView,
  // which NSAsserts if an implicit view controller is already attached. That
  // Objective-C exception aborts the process across FFI; Dart cannot catch it.
  // The engine can expose a dummy Dart view 0 even without a native controller,
  // so only the native bootstrap can confirm that this transition is safe.
  static bool get isSupported => switch (defaultTargetPlatform) {
    TargetPlatform.windows => true,
    TargetPlatform.macOS => _macOSWindowingReady,
    _ => false,
  };

  static DetachedPlaybackWindow create({
    required String title,
    required VoidCallback onCloseRequested,
    Size size = const Size(1120, 760),
    BoxConstraints constraints = const BoxConstraints(
      minWidth: 420,
      minHeight: 360,
    ),
  }) {
    if (!Platform.isWindows && !Platform.isMacOS) {
      throw UnsupportedError('Detached playback requires Windows or macOS.');
    }
    if (!isSupported) {
      throw UnsupportedError(
        'Detached playback is incompatible with the current engine views.',
      );
    }
    // The pinned stable SDK includes the complete implementation but its tool
    // only exposes the flag on main, and rejects the reserved dart-define.
    // Do not change the user's SDK channel or global Flutter configuration.
    if (!_windowingReady) {
      flutter_features.isWindowingEnabled = true;
      // Binding initialization predates opening playback and cached an
      // unsupported owner while the experimental feature was still disabled.
      WidgetsBinding.instance.windowingOwner = flutter_window
          .createDefaultWindowingOwner();
      _windowingReady = true;
    }
    return _FlutterDetachedPlaybackWindow(
      title: title,
      onCloseRequested: onCloseRequested,
      size: size,
      constraints: constraints,
    );
  }

  int get viewId;
  bool get isOpen;
  WindowService get windowService;
  Widget buildView(Widget child);
  void activate();
  void setTitle(String title);
  Future<void> prepare() async {}
  Future<void> saveGeometry() async {}
}

/// Drains secondary views before the shared engine is allowed to terminate.
final class DesktopPlaybackWindowController {
  final _hosts = <_DesktopPlaybackWindowState>{};
  bool _closed = false;
  Future<void>? _closing;

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    await Future.wait([for (final host in _hosts.toList()) host._shutdown()]);
  }
}

class DesktopPlaybackWindow extends StatefulWidget {
  const DesktopPlaybackWindow({
    super.key,
    required this.child,
    required this.playback,
    required this.onCloseRequested,
    required this.onError,
    this.activationToken,
    this.title = 'BiliSail 播放',
    this.windowFactory,
    this.controller,
    this.keepPlaybackMounted = false,
  });

  final Widget child;
  final Widget? playback;
  final VoidCallback onCloseRequested;
  final void Function(Object error) onError;
  final Object? activationToken;
  final String title;
  final DetachedPlaybackWindowFactory? windowFactory;
  final DesktopPlaybackWindowController? controller;

  /// Keep an existing page alive when changing navigation modes. A new page
  /// can mount directly in its prepared view instead of building and laying
  /// out once under the browser and again after its inherited view changes.
  final bool keepPlaybackMounted;

  @override
  State<DesktopPlaybackWindow> createState() => _DesktopPlaybackWindowState();
}

class _DesktopPlaybackWindowState extends State<DesktopPlaybackWindow> {
  final _playbackKey = GlobalKey();
  DetachedPlaybackWindow? _window;
  bool _closeRequested = false;
  Object? _pendingWindowUpdate;
  Timer? _windowUpdateTimer;
  bool _createRequested = false;
  bool _activateRequested = false;
  bool _titleRequested = false;
  Object? _opening;
  final _openingTasks = <Future<void>>{};
  Future<void> _retiring = Future.value();
  bool _shuttingDown = false;

  @override
  void initState() {
    super.initState();
    widget.controller?._hosts.add(this);
    _shuttingDown = widget.controller?._closed ?? false;
    if (!_shuttingDown && widget.playback != null) {
      _scheduleWindowUpdate(create: true);
    }
  }

  void _scheduleWindowUpdate({
    bool create = false,
    bool activate = false,
    bool title = false,
  }) {
    if (_shuttingDown) return;
    _createRequested |= create;
    _activateRequested |= activate;
    _titleRequested |= title;
    if (_pendingWindowUpdate != null) return;
    final request = Object();
    _pendingWindowUpdate = request;
    // Native window operations can pump messages and reenter Flutter frame
    // callbacks. Leave the entire frame stack before entering the embedder.
    _windowUpdateTimer = Timer(Duration.zero, () {
      _windowUpdateTimer = null;
      if (!mounted || !identical(_pendingWindowUpdate, request)) return;
      _pendingWindowUpdate = null;
      final create = _createRequested;
      final activate = _activateRequested;
      final title = _titleRequested;
      _createRequested = false;
      _activateRequested = false;
      _titleRequested = false;
      if (widget.playback == null || _closeRequested) return;
      if (_window == null && create) {
        final opening = _open();
        _openingTasks.add(opening);
        unawaited(opening.whenComplete(() => _openingTasks.remove(opening)));
        return;
      }
      final window = _window;
      if (window == null || !window.isOpen) return;
      if (title) window.setTitle(widget.title);
      if (activate) window.activate();
    });
  }

  void _afterFrame(VoidCallback callback) {
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      Timer.run(callback);
      // Keep settling callers moving until the queued event gets its turn.
      binding.ensureVisualUpdate();
    });
    binding.ensureVisualUpdate();
  }

  void _cancelWindowUpdate() {
    _windowUpdateTimer?.cancel();
    _windowUpdateTimer = null;
    _pendingWindowUpdate = null;
    _createRequested = false;
    _activateRequested = false;
    _titleRequested = false;
    _opening = null;
  }

  Future<void> _open() async {
    final request = Object();
    _opening = request;
    DetachedPlaybackWindow? created;
    final initialTitle = widget.title;
    final initialActivation = widget.activationToken;
    try {
      final factory = widget.windowFactory ?? DetachedPlaybackWindow.create;
      final window = factory(
        title: widget.title,
        onCloseRequested: () {
          if (identical(_opening, request) ||
              (created != null && identical(_window, created))) {
            _requestClose();
          }
        },
      );
      created = window;
      if (!mounted ||
          !identical(_opening, request) ||
          widget.playback == null ||
          _closeRequested) {
        _disposeAfterFrame(window);
        return;
      }
      await window.prepare().timeout(const Duration(seconds: 2));
      // Channel completion may run among frame microtasks. Native title/focus
      // operations must leave that frame's stack just like initial creation.
      await Future<void>.delayed(Duration.zero);
      // Window creation can synchronously pump a close/navigation message.
      if (!mounted ||
          !identical(_opening, request) ||
          widget.playback == null ||
          _closeRequested) {
        _disposeAfterFrame(window);
        return;
      }
      if (!window.isOpen) {
        throw StateError('Playback window closed before it was ready.');
      }
      if (widget.title != initialTitle) window.setTitle(widget.title);
      if (!mounted ||
          !identical(_opening, request) ||
          widget.playback == null ||
          _closeRequested) {
        _disposeAfterFrame(window);
        return;
      }
      if (!window.isOpen) {
        throw StateError('Playback window closed while updating its title.');
      }
      if (widget.activationToken != initialActivation) window.activate();
      if (!mounted ||
          !identical(_opening, request) ||
          widget.playback == null ||
          _closeRequested) {
        _disposeAfterFrame(window);
        return;
      }
      if (!window.isOpen) {
        throw StateError('Playback window closed while activating.');
      }
      window.addListener(_windowChanged);
      setState(() {
        _window = window;
        _closeRequested = false;
      });
      _opening = null;
      // Adding a native view can consume the old view's pending engine frame.
      // The scheduler still considers that frame scheduled, so scheduleFrame
      // and scheduleForcedFrame would both return without waking the new view.
      WidgetsBinding.instance.platformDispatcher.scheduleFrame();
    } catch (error) {
      if (created != null) _disposeAfterFrame(created);
      if (mounted && identical(_opening, request)) {
        _opening = null;
        widget.onError(error);
      }
    }
  }

  void _disposeAfterFrame(DetachedPlaybackWindow window) {
    final disposed = Completer<void>();
    // Start the capture now, before a rapid new open queues its restore. Native
    // geometry is owner checked, so late capture/retire cannot change that view.
    final saved = window
        .saveGeometry()
        .timeout(const Duration(seconds: 2))
        .catchError((Object error, StackTrace stack) {
          if (error is PlatformException &&
              error.code == 'window_unavailable') {
            return;
          }
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'BiliSail playback window geometry',
            ),
          );
        });
    _afterFrame(() {
      unawaited(
        saved.whenComplete(
          () => Timer.run(() {
            try {
              window.dispose();
              disposed.complete();
            } catch (error, stack) {
              disposed.completeError(error, stack);
            }
          }),
        ),
      );
    });
    _retiring = Future.wait([_retiring, disposed.future]).then((_) {});
    unawaited(
      _retiring.catchError((Object error, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'BiliSail playback window retirement',
          ),
        );
      }),
    );
  }

  Future<void> _drain() async {
    // An in-flight prepare can retire its cancelled view after it completes.
    await Future.wait(_openingTasks.toList());
    await _retiring;
  }

  Future<void> _shutdown() {
    if (!_shuttingDown) {
      _shuttingDown = true;
      _cancelWindowUpdate();
      if (mounted) setState(_retireWindow);
    }
    return _drain();
  }

  void _requestClose() {
    if (!mounted || _closeRequested) return;
    _closeRequested = true;
    widget.onCloseRequested();
  }

  void _windowChanged() {
    final window = _window;
    if (!mounted || window == null || window.isOpen) return;
    setState(_retireWindow);
    _requestClose();
  }

  void _retireWindow() {
    final window = _window;
    if (window == null) return;
    _window = null;
    window.removeListener(_windowChanged);
    // A Flutter view must leave the widget tree before its native view dies.
    // The native destroy path can reenter frame callbacks too.
    // Even an externally destroyed view may be notifying listeners right now.
    // Delay notifier disposal until that stack, and the render frame, unwind.
    _disposeAfterFrame(window);
  }

  @override
  void didUpdateWidget(DesktopPlaybackWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._hosts.remove(this);
      widget.controller?._hosts.add(this);
      if (widget.controller?._closed == true) unawaited(_shutdown());
    }
    if (_shuttingDown) return;
    if (widget.playback == null) {
      _closeRequested = false;
      _cancelWindowUpdate();
      _retireWindow();
      return;
    }
    // Coalesce media/title changes into the native window already preparing.
    // _open applies the latest widget values after checking its request lease.
    if (_window == null && _opening != null) return;
    if (oldWidget.playback == null ||
        (_window == null &&
            oldWidget.activationToken != widget.activationToken)) {
      _scheduleWindowUpdate(create: true);
    }
    final window = _window;
    if (window == null || !window.isOpen) return;
    if (oldWidget.title != widget.title ||
        oldWidget.activationToken != widget.activationToken) {
      _scheduleWindowUpdate(
        title: oldWidget.title != widget.title,
        activate: oldWidget.activationToken != widget.activationToken,
      );
    }
  }

  @override
  void dispose() {
    _shuttingDown = true;
    _cancelWindowUpdate();
    _retireWindow();
    final controller = widget.controller;
    unawaited(_drain().then((_) => controller?._hosts.remove(this)));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final window = _window;
    final playback = _shuttingDown ? null : widget.playback;
    final content = playback == null
        ? null
        : KeyedSubtree(key: _playbackKey, child: playback);
    final windowReady = window != null && window.isOpen;
    return ViewAnchor(
      view: windowReady && content != null
          ? window.buildView(
              WindowServiceScope(service: window.windowService, child: content),
            )
          : null,
      child: Stack(
        alignment: Alignment.topLeft,
        fit: StackFit.passthrough,
        children: [
          widget.child,
          // Only mode changes need this temporary home for retained pages.
          // New pages wait for their actual view before starting page work.
          if (!windowReady && content != null && widget.keepPlaybackMounted)
            Offstage(child: ExcludeFocus(child: content)),
        ],
      ),
    );
  }
}

class _FlutterDetachedPlaybackWindow extends DetachedPlaybackWindow {
  _FlutterDetachedPlaybackWindow({
    required String title,
    required VoidCallback onCloseRequested,
    required Size size,
    required BoxConstraints constraints,
  }) {
    final delegate = _PlaybackWindowDelegate(
      onCloseRequested: onCloseRequested,
      onDestroyed: _destroyed,
    );
    // Fixed-size Windows views synchronously wait up to 100 ms for a frame on
    // each initial native resize, before this view has any Flutter content.
    // The SDK's resizable content-sized mode avoids that wait and switches to
    // normal user sizing automatically after its first frame. Native geometry
    // preparation keeps our custom caption from altering the saved outer size.
    if (Platform.isWindows) {
      _controller = flutter_window.RegularWindowController.sizedToContent(
        resizable: true,
        constraints: constraints,
        title: title,
        delegate: delegate,
      )..setSize(size);
    } else {
      _controller = flutter_window.RegularWindowController(
        size: size,
        constraints: constraints,
        title: title,
        delegate: delegate,
      );
    }
    windowService = WindowService.forView(
      viewId: viewId,
      nativeWindowHandle: _nativeWindowHandle,
      isAvailable: () => _open,
      setFullScreen: (value) async => _controller.setFullscreen(value),
      activate: () => WindowService.activateDesktopView(
        viewId,
        windowHandle: _nativeWindowHandle,
      ),
    );
    _controller.addListener(_rememberPresentation);
    _rememberPresentation();
  }

  void _rememberPresentation() {
    if (!_open) return;
    windowService.updateWindowPresentation(
      maximized: _controller.isMaximized,
      minimized: _controller.isMinimized,
      fullScreen: _controller.isFullscreen,
    );
  }

  late final flutter_window.RegularWindowController _controller;
  bool _open = true;
  bool _disposed = false;
  Size? _initialContentSize;

  @override
  late final WindowService windowService;

  @override
  int get viewId => _controller.rootView.viewId;

  int? get _nativeWindowHandle => Platform.isMacOS
      ? flutter_macos.WindowingOwnerMacOS.getWindowHandle(_controller.rootView)
            .address
      : null;

  @override
  bool get isOpen => _open;

  @override
  Future<void> prepare() async {
    await windowService.configurePlaybackTitleBar();
    _initialContentSize = await windowService.restorePlaybackGeometry();
    await WindowInputFocus.instance.synchronizeNativeFocusIfSupported();
  }

  @override
  Future<void> saveGeometry() => windowService.savePlaybackGeometry();

  @override
  Widget buildView(Widget child) {
    final view = _controller.rootView;
    return flutter_window.RegularWindow(
      controller: _controller,
      // A maximized first show needs a maximized scene already rasterized;
      // otherwise Windows briefly presents/clips the normal-size caption.
      // Later fixed view constraints override this initial preferred size.
      child: Platform.isWindows
          ? SizedBox.fromSize(
              size:
                  (_initialContentSize ?? view.physicalSize) /
                  view.devicePixelRatio,
              child: child,
            )
          : child,
    );
  }

  @override
  void activate() {
    if (!_open) return;
    // The pinned Win32 controller uses SW_RESTORE unconditionally. Native
    // activation restores only minimized windows and preserves zoom/geometry.
    unawaited(
      windowService.activate().catchError((Object error, StackTrace stack) {
        if (!_open) return;
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'BiliSail desktop window',
          ),
        );
      }),
    );
  }

  @override
  void setTitle(String title) {
    if (_open) _controller.setTitle(title);
  }

  void _destroyed() {
    if (!_open) return;
    _open = false;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _controller.removeListener(_rememberPresentation);
    if (_open) {
      _open = false;
      _controller.destroy();
    }
    _controller.dispose();
    super.dispose();
  }
}

class _PlaybackWindowDelegate
    with flutter_window.RegularWindowControllerDelegate {
  _PlaybackWindowDelegate({
    required this.onCloseRequested,
    required this.onDestroyed,
  });

  final VoidCallback onCloseRequested;
  final VoidCallback onDestroyed;

  @override
  void onWindowCloseRequested(
    flutter_window.RegularWindowController controller,
  ) => onCloseRequested();

  @override
  void onWindowDestroyed() => onDestroyed();
}
