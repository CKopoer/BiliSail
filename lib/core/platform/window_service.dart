import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show AppExitType;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../domain/app_orientation.dart';
import 'window_size_policy.dart';

enum FullScreenOrientation { portrait, landscape }

class WindowService {
  bool get supportsBackgroundAudio => Platform.isAndroid || Platform.isIOS;

  static const _orientationChannel = EventChannel(
    'bilisail/device_orientation',
  );
  static const _mobileWindowChannel = MethodChannel('bilisail/mobile_window');
  static final _deviceOrientations = _orientationChannel
      .receiveBroadcastStream()
      .where(
        (event) =>
            event == 'portrait' || event == 'landscape' || event == 'reset',
      )
      .map(
        (event) => event == 'reset'
            ? null
            : event == 'landscape'
            ? FullScreenOrientation.landscape
            : FullScreenOrientation.portrait,
      );

  /// Null invalidates the physical rotation baseline and queued actions.
  Stream<FullScreenOrientation?> get deviceOrientations =>
      Platform.isAndroid ? _deviceOrientations : const Stream.empty();

  // iOS has no public API for reading the user's rotation-lock setting.
  bool get supportsPhoneRotationActions => !Platform.isIOS;

  WindowService()
    : viewId = null,
      nativeWindowHandle = null,
      _setViewFullScreen = null,
      _resizeView = null,
      _prepareViewToClose = null,
      _activateView = null,
      _isViewAvailable = null;

  WindowService.forView({
    required this.viewId,
    this.nativeWindowHandle,
    required Future<void> Function(bool value) setFullScreen,
    Future<bool> Function(Size size)? resize,
    required Future<void> Function() activate,
    Future<void> Function()? prepareToClose,
    bool Function()? isAvailable,
  }) : _setViewFullScreen = setFullScreen,
       _resizeView = resize,
       _prepareViewToClose = prepareToClose,
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
  Future<void>? _preparingToClose;
  bool _closing = false;

  final _maximized = ValueNotifier(false);
  ValueListenable<bool> get maximized => _maximized;

  final miniPlayer = ValueNotifier(false);
  final alwaysOnTop = ValueNotifier(false);
  VoidCallback? onMiniPlayerRequested;
  VoidCallback? onMiniPlayerClose;
  bool _beforeMiniPlayerTopmost = false;
  Future<void> Function(bool mini)? configureMiniPlayerConstraints;
  Future<void> _presentationCommands = Future.value();

  bool get supportsMiniPlayer => hasDesktopWindow;
  bool get hasMiniPlayerResizeHandle => Platform.isLinux;

  Future<void> startResizingMiniPlayer() async {
    if (!hasMiniPlayerResizeHandle) return;
    await windowManager
        .startResizing(ResizeEdge.bottomRight)
        .timeout(_geometryTimeout);
  }

  Future<void> setAlwaysOnTop(bool enabled) async {
    if (_closing || !hasDesktopWindow || _isViewAvailable?.call() == false) {
      return;
    }
    if (Platform.isWindows || (Platform.isMacOS && viewId != null)) {
      await _desktopChannel
          .invokeMethod<void>('setAlwaysOnTop', {
            'viewId': viewId ?? 0,
            'windowHandle': ?nativeWindowHandle,
            'enabled': enabled,
          })
          .timeout(_geometryTimeout);
    } else {
      await windowManager.setAlwaysOnTop(enabled).timeout(_geometryTimeout);
    }
    alwaysOnTop.value = enabled;
  }

  /// Serializes native presentation so a late enter cannot overtake restore.
  Future<void> setMiniPlayer(bool enabled) {
    final operation = _presentationCommands.then((_) async {
      if (!supportsMiniPlayer ||
          _closing ||
          _isViewAvailable?.call() == false ||
          miniPlayer.value == enabled) {
        return;
      }
      if (enabled) await capturePlaybackGeometry();
      if (_closing || _isViewAvailable?.call() == false) return;
      if (enabled) _beforeMiniPlayerTopmost = alwaysOnTop.value;
      if (enabled) await configureMiniPlayerConstraints?.call(true);
      if (_closing || _isViewAvailable?.call() == false) return;
      try {
        await _desktopChannel
            .invokeMethod<void>('setMiniPlayer', {
              'viewId': viewId ?? 0,
              'windowHandle': ?nativeWindowHandle,
              'enabled': enabled,
            })
            .timeout(_geometryTimeout);
        if (!_closing && !enabled) {
          await configureMiniPlayerConstraints?.call(false);
        }
        miniPlayer.value = enabled;
        alwaysOnTop.value = enabled ? true : _beforeMiniPlayerTopmost;
      } catch (_) {
        if (!_closing && enabled) {
          await configureMiniPlayerConstraints?.call(false);
        }
        rethrow;
      }
    });
    _presentationCommands = operation.then(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

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

  Future<void> startDraggingPlaybackWindow() async {
    if (_isViewAvailable?.call() == false) return;
    if (Platform.isWindows || (Platform.isMacOS && viewId != null)) {
      await _desktopChannel
          .invokeMethod<void>('startDragging', {
            'viewId': viewId ?? 0,
            'windowHandle': ?nativeWindowHandle,
          })
          .timeout(_geometryTimeout);
    } else if (hasDesktopWindow) {
      await windowManager.startDragging();
    }
  }

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
    if (!minimized && !fullScreen && !miniPlayer.value) {
      _normalWindowMaximized = maximized;
    }
    _maximized.value = maximized;
  }

  /// Restores this app session's normal rectangle and zoom before its first view.
  ///
  /// Returns the first scene's client size in physical pixels when provided by
  /// the platform, or `null` to use the view's prepared client size.
  Future<Size?> restorePlaybackGeometry() async {
    if (viewId == null || _isViewAvailable?.call() == false) return null;
    _geometryAttached = true;
    final result = await _geometryCall('restoreGeometry');
    if (result == null) return null;
    if (result is List<Object?> && result.length == 2) {
      final width = result[0], height = result[1];
      if (width is num &&
          height is num &&
          width.isFinite &&
          height.isFinite &&
          width > 0 &&
          height > 0) {
        return Size(width.toDouble(), height.toDouble());
      }
    }
    throw const FormatException('Invalid initial playback window size.');
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
    if ((Platform.isWindows || Platform.isMacOS) &&
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

  Future<Object?> _geometryCall(String method) => _desktopChannel
      .invokeMethod<Object?>(method, {
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
  final Future<bool> Function(Size size)? _resizeView;
  final Future<void> Function()? _prepareViewToClose;
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
  AppOrientationPreference _orientationPreference =
      AppOrientationPreference.automatic;
  bool _mobileFullScreenRequested = false;
  FullScreenOrientation? _mobileFullScreenOrientation;
  FullScreenOrientation? _appliedMobileOrientation;
  Future<void> _orientationCommands = Future<void>.value();
  final _fullScreenOrientation = ValueNotifier<AppOrientationPreference?>(null);
  ValueListenable<AppOrientationPreference?> get fullScreenOrientation =>
      _fullScreenOrientation;
  Size? _desktopWindowSize;
  Size? _desktopDisplaySize;
  (Size, Size, AppOrientationPreference)? _lastDesktopResize;
  bool get isFullScreen => _fullScreen;
  bool get allowsAutomaticRotation =>
      _orientationPreference == AppOrientationPreference.automatic;
  bool get keepsBrowsePortrait => switch (_orientationPreference) {
    AppOrientationPreference.automatic => _browsePortrait == true,
    AppOrientationPreference.portrait => true,
    AppOrientationPreference.landscape => false,
  };

  Future<void> updateDisplaySize(
    Size logicalDisplaySize, {
    AppOrientationPreference orientation = AppOrientationPreference.automatic,
    Size? logicalWindowSize,
  }) {
    _orientationPreference = orientation;
    if (hasDesktopWindow || viewId != null) {
      _desktopWindowSize = logicalWindowSize;
      _desktopDisplaySize = logicalDisplaySize;
      return _applyDesktopOrientation();
    }
    _browsePortrait = WindowSizePolicy.compactDisplay(logicalDisplaySize);
    return _applyMobileOrientation();
  }

  Future<void> clearDisplayOrientationPolicy() {
    _browsePortrait = null;
    _orientationPreference = AppOrientationPreference.automatic;
    _desktopWindowSize = null;
    _lastDesktopResize = null;
    if (hasDesktopWindow || viewId != null) return Future<void>.value();
    return _applyMobileOrientation();
  }

  Future<void> _applyDesktopOrientation() {
    final operation = _orientationCommands.then((_) async {
      if (_orientationPreference == AppOrientationPreference.automatic ||
          _desktopWindowSize == null ||
          _fullScreen ||
          _fullScreenOrientation.value != null) {
        _lastDesktopResize = null;
        return;
      }
      // SDK window operations can pump native messages. Leave the Flutter
      // frame before resizing, and consume the latest preference afterwards.
      await Future<void>.delayed(Duration.zero);
      final preference = _orientationPreference;
      final size = _desktopWindowSize;
      final display = _desktopDisplaySize;
      if (_closing ||
          _isViewAvailable?.call() == false ||
          preference == AppOrientationPreference.automatic ||
          size == null ||
          size.isEmpty ||
          !size.isFinite ||
          display == null ||
          display.isEmpty ||
          !display.isFinite) {
        _lastDesktopResize = null;
        return;
      }
      final portrait = preference == AppOrientationPreference.portrait;
      if (portrait ? size.width < size.height : size.width > size.height) {
        _lastDesktopResize = null;
        return;
      }
      final request = (size, display, preference);
      if (_lastDesktopResize == request ||
          miniPlayer.value ||
          _fullScreen ||
          _fullScreenOrientation.value != null) {
        return;
      }
      // Fit the swapped rectangle within the display. Fullscreen/maximized
      // windows retain their native state; the host constrains their viewport.
      final swapped = size.width == size.height
          ? (portrait
                ? Size(size.width * 9 / 16, size.height)
                : Size(size.width, size.height * 9 / 16))
          : Size(size.height, size.width);
      final scale = math.min(
        1.0,
        math.min(
          display.width * .9 / swapped.width,
          display.height * .9 / swapped.height,
        ),
      );
      final target = swapped * scale;
      final resize = _resizeView;
      if (resize != null) {
        if (await resize(target).timeout(_geometryTimeout)) {
          _lastDesktopResize = request;
        }
      } else if (viewId == null) {
        if (await windowManager.isMaximized().timeout(_geometryTimeout) ||
            await windowManager.isMinimized().timeout(_geometryTimeout) ||
            await windowManager.isFullScreen().timeout(_geometryTimeout)) {
          return;
        }
        if (_closing ||
            preference != _orientationPreference ||
            size != _desktopWindowSize ||
            display != _desktopDisplaySize) {
          return;
        }
        await windowManager.setSize(target).timeout(_geometryTimeout);
        _lastDesktopResize = request;
      }
    });
    _orientationCommands = operation.then(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _applyMobileOrientation() {
    final operation = _orientationCommands.then((_) async {
      // Read the latest display and owner intent when the command runs.
      // Fullscreen belongs to the video's dimensions on every display size.
      // The app preference only owns the browsing layout restored on exit.
      final orientation = _mobileFullScreenRequested
          ? _mobileFullScreenOrientation
          : switch (_orientationPreference) {
              AppOrientationPreference.automatic =>
                _browsePortrait == true ? FullScreenOrientation.portrait : null,
              AppOrientationPreference.portrait =>
                FullScreenOrientation.portrait,
              AppOrientationPreference.landscape =>
                FullScreenOrientation.landscape,
            };
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

  /// Stops accepting presentation changes and waits for AppKit to leave its
  /// asynchronous fullscreen transition before the SDK destroys this view.
  Future<void> prepareToClose() => _preparingToClose ??= _prepareToClose();

  /// Called before unmount so page cleanup cannot restore a retiring window.
  /// Already dispatched native mini-player changes finish before geometry is saved.
  Future<void> beginClose() {
    _closing = true;
    return _presentationCommands;
  }

  Future<void> _prepareToClose() async {
    await beginClose();
    if (_isViewAvailable?.call() == false) return;
    await _prepareViewToClose?.call();
  }

  Future<void> setFullScreen(
    bool value, {
    FullScreenOrientation? orientation,
  }) async {
    if (_closing) return;
    final setViewFullScreen = _setViewFullScreen;
    if (setViewFullScreen != null) {
      if (_isViewAvailable?.call() == false) return;
      // The native fullscreen transition may replace the normal placement.
      // Capture before entering; fullscreen frames never become restore bounds.
      if (value && !_fullScreen) await capturePlaybackGeometry();
      if (_closing || _isViewAvailable?.call() == false) {
        return;
      }
      await setViewFullScreen(value);
      if (_closing || _isViewAvailable?.call() == false) {
        return;
      }
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
    _fullScreenOrientation.value = value
        ? switch (orientation) {
            FullScreenOrientation.portrait => AppOrientationPreference.portrait,
            FullScreenOrientation.landscape =>
              AppOrientationPreference.landscape,
            null => AppOrientationPreference.automatic,
          }
        : null;
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
