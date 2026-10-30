import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitType;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'window_size_policy.dart';

enum FullScreenOrientation { portrait, landscape }

class WindowService {
  bool get supportsBackgroundAudio => Platform.isAndroid;

  static const _orientationChannel = EventChannel(
    'bilisail/device_orientation',
  );
  static const _mobileWindowChannel = MethodChannel('bilisail/mobile_window');
  static final _deviceOrientations = _orientationChannel
      .receiveBroadcastStream()
      .where((event) => event == 'portrait' || event == 'landscape')
      .map(
        (event) => event == 'landscape'
            ? FullScreenOrientation.landscape
            : FullScreenOrientation.portrait,
      );

  /// Physical rotation remains observable while fullscreen locks the interface.
  Stream<FullScreenOrientation> get deviceOrientations =>
      Platform.isAndroid || Platform.isIOS
      ? _deviceOrientations
      : const Stream.empty();

  WindowService()
    : viewId = null,
      nativeWindowHandle = null,
      _setViewFullScreen = null,
      _activateView = null,
      _isViewAvailable = null;

  WindowService.forView({
    required this.viewId,
    this.nativeWindowHandle,
    required Future<void> Function(bool value) setFullScreen,
    required Future<void> Function() activate,
    bool Function()? isAvailable,
  }) : _setViewFullScreen = setFullScreen,
       _activateView = activate,
       _isViewAvailable = isAvailable;

  static const _textInputChannel = MethodChannel('bilisail/text_input');
  static const _desktopChannel = MethodChannel('bilisail/desktop_window');
  static const _applicationExitChannel = MethodChannel(
    'bilisail/application_exit',
  );
  static final _backServices = <int, WindowService>{};
  static int _nextGeometryOwner = 0;
  static const _geometryTimeout = Duration(seconds: 2);
  late final _geometryOwner = ++_nextGeometryOwner;
  bool _geometryAttached = false;
  bool? _normalWindowMaximized;
  Object? _backOwner;
  VoidCallback? _onBack;
  VoidCallback? _onHome;
  bool _backEnabled = false;
  bool _handlesMainWindowClose = false;
  bool _requestingExit = false;

  final _maximized = ValueNotifier(false);
  ValueListenable<bool> get maximized => _maximized;

  bool get hasCustomPlaybackTitleBar => Platform.isWindows && viewId != null;

  Future<void> configurePlaybackTitleBar({
    Brightness? brightness,
    Color? backgroundColor,
  }) => _playbackCaptionCall('setPlaybackTitleBar', {
    'dark':
        (brightness ??
            WidgetsBinding.instance.platformDispatcher.platformBrightness) ==
        Brightness.dark,
    if (backgroundColor != null)
      'backgroundColor': backgroundColor.toARGB32() & 0x00ffffff,
  });

  Future<void> startDraggingPlaybackWindow() =>
      _playbackCaptionCall('startDragging');

  Future<void> togglePlaybackWindowMaximized() =>
      _playbackCaptionCall('toggleMaximized');

  Future<void> minimizePlaybackWindow() => _playbackCaptionCall('minimize');

  Future<void> _playbackCaptionCall(
    String method, [
    Map<String, Object> arguments = const {},
  ]) async {
    if (!hasCustomPlaybackTitleBar || _isViewAvailable?.call() == false) return;
    try {
      await _desktopChannel
          .invokeMethod<void>(method, {'viewId': viewId, ...arguments})
          .timeout(_geometryTimeout);
    } on PlatformException catch (error) {
      if (error.code == 'window_unavailable' &&
          _isViewAvailable?.call() == false) {
        return;
      }
      rethrow;
    }
  }

  bool get hasNativePlaybackTitleBar =>
      viewId != null && (Platform.isWindows || Platform.isMacOS);

  static Future<void> activateDesktopView(int viewId, {int? windowHandle}) =>
      _desktopChannel.invokeMethod<void>('activate', {
        'viewId': viewId,
        'windowHandle': ?windowHandle,
      });

  /// Sample native presentation synchronously before a minimize/fullscreen
  /// transition hides the previous zoom state. The session remains native-owned.
  void updateWindowPresentation({
    required bool maximized,
    required bool minimized,
    required bool fullScreen,
  }) {
    if (!minimized && !fullScreen) _normalWindowMaximized = maximized;
    _maximized.value = maximized;
  }

  /// Restore this app session's normal rectangle and zoom before its first view.
  Future<void> restorePlaybackGeometry() async {
    if (viewId == null || _isViewAvailable?.call() == false) return;
    _geometryAttached = true;
    await _geometryCall('restoreGeometry');
  }

  Future<void> capturePlaybackGeometry() async {
    if (!_geometryAttached || _isViewAvailable?.call() == false) return;
    try {
      await _geometryCall('captureGeometry');
    } on PlatformException catch (error) {
      if (error.code == 'window_unavailable' &&
          _isViewAvailable?.call() == false) {
        return;
      }
      rethrow;
    }
  }

  Future<void> retirePlaybackGeometry() async {
    if (!_geometryAttached) return;
    _geometryAttached = false;
    await _geometryCall('retireGeometry');
  }

  Future<void> savePlaybackGeometry() async {
    if (Platform.isWindows &&
        _geometryAttached &&
        _isViewAvailable?.call() != false) {
      _geometryAttached = false;
      // Capture and hide in one native turn. Destruction still waits until the
      // Flutter subtree has unmounted, but that wait is no longer visible.
      await _geometryCall('saveGeometry');
      return;
    }
    try {
      await capturePlaybackGeometry();
    } finally {
      await retirePlaybackGeometry();
    }
  }

  Future<void> _geometryCall(String method) => _desktopChannel
      .invokeMethod<void>(method, {
        'viewId': viewId,
        'windowHandle': ?nativeWindowHandle,
        'owner': _geometryOwner,
        if (method == 'captureGeometry' || method == 'saveGeometry')
          'maximized': ?_normalWindowMaximized,
      })
      .timeout(_geometryTimeout);

  Future<void> bindTitleBarBack({
    required Object owner,
    required VoidCallback onBack,
    VoidCallback? onHome,
    bool enabled = true,
  }) async {
    if (!hasNativePlaybackTitleBar || _isViewAvailable?.call() == false) return;
    _desktopChannel.setMethodCallHandler((call) async {
      if (call.method != 'back' && call.method != 'home') return;
      final arguments = call.arguments;
      if (arguments is! Map<Object?, Object?> || arguments['viewId'] is! int) {
        return;
      }
      final service = _backServices[arguments['viewId']];
      if (service?._backEnabled == true &&
          service?._isViewAvailable?.call() != false) {
        if (call.method == 'home') {
          service?._onHome?.call();
        } else {
          service?._onBack?.call();
        }
      }
    });
    _backOwner = owner;
    _onBack = onBack;
    _onHome = onHome;
    _backEnabled = enabled;
    _backServices[viewId!] = this;
    try {
      await _desktopChannel.invokeMethod<void>('setBackButton', {
        'viewId': viewId,
        'windowHandle': ?nativeWindowHandle,
        'enabled': enabled,
        'showHome': onHome != null,
      });
    } catch (error) {
      if (identical(_backOwner, owner)) {
        _backOwner = null;
        _onBack = null;
        _onHome = null;
        _backEnabled = false;
        if (identical(_backServices[viewId], this)) {
          _backServices.remove(viewId);
        }
      }
      if (error is PlatformException &&
          error.code == 'window_unavailable' &&
          _isViewAvailable?.call() == false) {
        return;
      }
      rethrow;
    }
  }

  Future<void> unbindTitleBarBack(Object owner) async {
    if (!identical(_backOwner, owner)) return;
    _backOwner = null;
    _onBack = null;
    _onHome = null;
    _backEnabled = false;
    final id = viewId;
    if (id == null || !identical(_backServices[id], this)) return;
    _backServices.remove(id);
    try {
      await _desktopChannel.invokeMethod<void>('removeBackButton', {
        'viewId': id,
      });
    } on PlatformException catch (error) {
      if (error.code == 'window_unavailable' &&
          _isViewAvailable?.call() == false) {
        return;
      }
      rethrow;
    }
  }

  final int? viewId;
  final int? nativeWindowHandle;
  final Future<void> Function(bool value)? _setViewFullScreen;
  final Future<void> Function()? _activateView;
  final bool Function()? _isViewAvailable;

  /// Keep IME composition attached only while a Flutter editor needs it.
  /// Otherwise Windows can consume punctuation before Flutter sees a key event.
  /// Reapplying the policy reconciles associations changed by Windows/TSF.
  Future<void> setTextInputActive(bool active, {int? viewId}) async {
    if (!Platform.isWindows) return;
    if (_isViewAvailable?.call() == false) return;
    final targetView = viewId ?? this.viewId;
    try {
      await _textInputChannel.invokeMethod<void>(
        'setActive',
        targetView == null ? active : {'active': active, 'viewId': targetView},
      );
    } on PlatformException catch (error) {
      // Unmount restores IME asynchronously, while the native view may retire
      // before the platform channel drains. Only that closed view is cancelled.
      if (targetView != null &&
          error.code == 'window_unavailable' &&
          _isViewAvailable?.call() == false) {
        return;
      }
      rethrow;
    }
  }

  bool get hasDesktopWindow =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// Other desktop platforms retain their native caption until validated.
  bool get hasCustomTitleBar => Platform.isWindows && viewId == null;
  bool _fullScreen = false;
  bool? _browsePortrait;
  bool _mobileFullScreenRequested = false;
  FullScreenOrientation? _mobileFullScreenOrientation;
  FullScreenOrientation? _appliedMobileOrientation;
  Future<void> _orientationCommands = Future<void>.value();
  bool get isFullScreen => _fullScreen;
  bool get keepsBrowsePortrait => _browsePortrait == true;

  Future<void> updateDisplaySize(Size logicalDisplaySize) {
    if (hasDesktopWindow || viewId != null) return Future<void>.value();
    _browsePortrait = WindowSizePolicy.compactDisplay(logicalDisplaySize);
    return _applyMobileOrientation();
  }

  Future<void> clearDisplayOrientationPolicy() {
    if (_browsePortrait == null) return Future<void>.value();
    _browsePortrait = null;
    return _applyMobileOrientation();
  }

  Future<void> _applyMobileOrientation() {
    final operation = _orientationCommands.then((_) async {
      // Read the latest display and owner intent when the command runs, so a
      // late phone request cannot re-lock an unfolded display.
      final orientation = _browsePortrait == false
          ? null
          : _mobileFullScreenRequested
          ? _mobileFullScreenOrientation
          : _browsePortrait == true
          ? FullScreenOrientation.portrait
          : null;
      if (orientation == _appliedMobileOrientation) return;
      await SystemChrome.setPreferredOrientations(switch (orientation) {
        FullScreenOrientation.landscape => const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        FullScreenOrientation.portrait => const [DeviceOrientation.portraitUp],
        null => const [],
      }).timeout(const Duration(seconds: 2));
      _appliedMobileOrientation = orientation;
    });
    _orientationCommands = operation.then(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> initialize() async {
    // SDK-managed windows already have their title and constraints. In
    // particular, window_manager's macOS initialization would look up a
    // nonexistent implicit view and replace the SDK's NSWindow delegate.
    if (viewId != null) return;
    if (!hasDesktopWindow) return;
    await windowManager.ensureInitialized();
    if (Platform.isWindows && !_handlesMainWindowClose) {
      // The runner intercepts only its engine-owning implicit main HWND. Global
      // plugin listeners also receive SDK-managed playback window messages.
      _applicationExitChannel.setMethodCallHandler((call) async {
        if (call.method == 'closeRequested') _requestApplicationExit();
      });
      _handlesMainWindowClose = true;
      await _applicationExitChannel.invokeMethod<void>('setCloseHandler', true);
    }
    await windowManager.setTitle('BiliSail');
    await windowManager.setMinimumSize(const Size(420, 560));
    if (hasCustomTitleBar) {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    }
  }

  void _requestApplicationExit() {
    if (!_handlesMainWindowClose || _requestingExit) return;
    _requestingExit = true;
    unawaited(
      ServicesBinding.instance
          .exitApplication(AppExitType.cancelable)
          .whenComplete(() => _requestingExit = false),
    );
  }

  Future<void> dispose() async {
    if (_handlesMainWindowClose) {
      _applicationExitChannel.setMethodCallHandler(null);
      _handlesMainWindowClose = false;
      await _applicationExitChannel.invokeMethod<void>(
        'setCloseHandler',
        false,
      );
    }
  }

  Future<void> activate() async {
    if (_isViewAvailable?.call() == false) return;
    final activateView = _activateView;
    if (activateView != null) {
      await activateView();
    } else if (hasDesktopWindow) {
      await windowManager.show();
      await windowManager.focus();
    }
  }

  Future<void> setFullScreen(
    bool value, {
    FullScreenOrientation? orientation,
  }) async {
    final setViewFullScreen = _setViewFullScreen;
    if (setViewFullScreen != null) {
      if (_isViewAvailable?.call() == false) return;
      // The native fullscreen transition may replace the normal placement.
      // Capture before entering; fullscreen frames never become restore bounds.
      if (value && !_fullScreen) await capturePlaybackGeometry();
      if (_isViewAvailable?.call() == false) return;
      await setViewFullScreen(value);
      if (_isViewAvailable?.call() == false) return;
    } else if (hasDesktopWindow) {
      await windowManager.setFullScreen(value);
    } else {
      _mobileFullScreenRequested = value;
      _mobileFullScreenOrientation = value ? orientation : null;
      await _applyMobileOrientation();
      await SystemChrome.setEnabledSystemUIMode(
        value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
      if (Platform.isAndroid) {
        // With target SDK 36 Flutter's SystemUiMode stays edge-to-edge. Hide
        // system bars explicitly through WindowInsetsController instead.
        await _mobileWindowChannel
            .invokeMethod<void>('setFullScreen', value)
            .timeout(const Duration(seconds: 2));
      }
    }
    _fullScreen = value;
  }
}

class WindowServiceScope extends InheritedWidget {
  const WindowServiceScope({
    super.key,
    required this.service,
    required super.child,
  });

  final WindowService service;

  static WindowService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WindowServiceScope>()?.service;

  @override
  bool updateShouldNotify(WindowServiceScope oldWidget) =>
      !identical(service, oldWidget.service);
}
