import 'dart:async';

import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:bili_player/bili_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/window_service.dart';
import '../../../core/platform/window_size_policy.dart';
import '../../../core/presentation/workspace_activity.dart';
import '../../../core/presentation/android_system_ui.dart';
import '../../../shared/ui/playback_page_commands.dart';
import '../../../shared/ui/playback_navigation.dart';
import '../../../shared/ui/width_layout_builder.dart';
import '../../../domain/video.dart';
import '../../../domain/playback_rates.dart';
import '../../settings/domain/app_settings.dart';
import '../../../core/input/shortcut_dispatcher.dart';
import '../../../core/presentation/input_scope.dart';
import '../application/playback_shortcut_controller.dart';
import '../application/playback_session.dart';
import '../application/playback_viewers_controller.dart';
import '../domain/playback_repository.dart';
import '../domain/content_playback.dart';
import 'player_settings_dialog.dart';
import 'player_swipe_controls.dart';
import 'player_seek_controls.dart';
import 'audio_playback_view.dart';
import 'playback_timeline_bar.dart';
import 'playback_snapshot_builder.dart';
import 'live_stream_menu.dart';
import 'live_stream_picker.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../shared/ui/bili_icons.dart';
import '../../../shared/ui/shortcut_hint.dart';
import '../../settings/domain/shortcut_settings.dart';

class PlaybackPanel extends ConsumerStatefulWidget {
  const PlaybackPanel({
    super.key,
    this.detail,
    this.part,
    this.target,
    this.title,
    required this.settings,
    required this.onToggleComments,
    required this.window,
    this.danmakuComposerBuilder,
    this.danmakuOverlayBuilder,
  });
  final VideoDetail? detail;
  final VideoPart? part;
  final ContentPlaybackTarget? target;
  final String? title;
  final AppSettings settings;
  final VoidCallback onToggleComments;
  final WindowService window;
  final WidgetBuilder? danmakuComposerBuilder;
  final WidgetBuilder? danmakuOverlayBuilder;

  @override
  ConsumerState<PlaybackPanel> createState() => _PlaybackPanelState();
}

class _PlaybackPanelState extends ConsumerState<PlaybackPanel>
    with WidgetsBindingObserver {
  late final PlaybackSession _session;
  late FlutterView _view;
  late final PlaybackShortcutController _shortcuts;
  late final ValueNotifier<AppSettings> _settings;
  final _pageCommands = ValueNotifier<PlaybackPageCommands?>(null);
  final _navigation = ValueNotifier<PlaybackNavigation?>(null);
  int? _handledCompletionGeneration;
  // Inline and fullscreen views are recreated, but share the page's intent.
  late final ValueNotifier<bool> _controlsVisible;
  bool _fullScreen = false;
  bool _active = false;
  bool _surfaceReady = false;
  Object? _activityRequest;
  Route<void>? _fullScreenRoute;
  NavigatorState? _fullScreenNavigator;
  Object? _fullScreenRequest;
  FullScreenOrientation? _fullScreenOrientation;
  StreamSubscription<FullScreenOrientation?>? _deviceOrientationSubscription;
  bool? _viewLandscape;
  bool _landscapeRotationPending = false;
  bool _rotationCallbackPending = false;
  bool _physicalLandscapeSeen = false;
  Object? _portraitExitRequest;
  Object? _deviceOrientationOwner;
  FullScreenOrientation? _deviceOrientation;
  bool? _rotationCompact, _displayCompact;
  bool _deviceOrientationBaselinePending = false;
  bool _deviceRotationBlocked = false;
  bool _metricsBaselinePending = false;
  static final _windowStates = Expando<_WindowFullScreenState>();
  _WindowFullScreenState get _windowState =>
      _windowStates[widget.window] ??= _WindowFullScreenState();

  @override
  void initState() {
    super.initState();
    _controlsVisible = ValueNotifier(
      widget.settings.playerControlsMode != PlayerControlsMode.click,
    );
    _settings = ValueNotifier(widget.settings);
    _session = ref.read(playbackSessionProvider)..attach(this);
    _session.snapshots.addListener(_updateFullScreenOrientation);
    _session.snapshots.addListener(_onPlaybackCompleted);
    _shortcuts = PlaybackShortcutController(
      session: _session,
      settings: () => widget.settings.shortcuts,
      active: () => mounted && _active,
      fullscreen: () => _fullScreen,
      toggleFullscreen: () {
        if (_fullScreen) {
          unawaited(_exitFullScreen());
        } else {
          unawaited(_enterFullScreen());
        }
      },
      toggleDanmaku: () => widget.onToggleComments(),
      volumeFeedback: (volume) {
        if (mounted && _active) showAppNotice(context, '音量 ${volume.round()}%');
      },
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _view = View.of(context);
    _viewLandscape ??= _isRotationLandscape;
    _rotationCompact ??= _usesCompactRotation;
    _displayCompact ??= _isPhoneDisplay;
    final commands = PlaybackPageCommands.maybeOf(context);
    final navigation = PlaybackNavigation.maybeOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _pageCommands.value = commands;
        _navigation.value = navigation;
      }
    });
    final active = WorkspaceActivity.isActive(context);
    if (_active == active) return;
    _active = active;
    _surfaceReady = false;
    final activityRequest = Object();
    _activityRequest = activityRequest;
    if (!active) {
      _landscapeRotationPending = false;
      _shortcuts.cancel();
      _dismissFullScreen();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !identical(_activityRequest, activityRequest)) return;
      if (active) {
        _configure();
        final lifecycle = WidgetsBinding.instance.lifecycleState;
        if (widget.window.supportsBackgroundAudio) {
          unawaited(
            _session.setBackgroundAudio(
              lifecycle == AppLifecycleState.hidden ||
                  lifecycle == AppLifecycleState.paused,
            ),
          );
        }
        unawaited(
          _session.activate(
            this,
            widget.detail,
            widget.part,
            target: widget.target,
            title: widget.title,
            visible: _active,
          ),
        );
        // Give an outgoing inline or fullscreen surface a frame to unmount.
        WidgetsBinding.instance.scheduleFrame();
        await WidgetsBinding.instance.endOfFrame;
        if (mounted &&
            _active &&
            identical(_activityRequest, activityRequest)) {
          setState(() => _surfaceReady = true);
        }
      } else {
        unawaited(_session.deactivate(this));
      }
    });
  }

  void _configure() => _session.configureSettings(widget.settings);

  void _onPlaybackCompleted() {
    final snapshot = _session.snapshots.value;
    if (snapshot.phase == PlaybackPhase.playing) {
      _handledCompletionGeneration = null;
    }
    final generation = _session.sourceGeneration;
    if (snapshot.phase != PlaybackPhase.ended ||
        _handledCompletionGeneration == generation ||
        _session.isResolving ||
        _session.media == null) {
      return;
    }
    _handledCompletionGeneration = generation;
    scheduleMicrotask(() {
      final commands = _pageCommands.value;
      if (!mounted ||
          !_session.ownsPlayback(this) ||
          _session.isLive ||
          _session.contentTarget is OfflinePlaybackTarget ||
          _session.sourceGeneration != generation ||
          _session.snapshots.value.phase != PlaybackPhase.ended ||
          _session.detail?.summary.id != widget.detail?.summary.id ||
          _session.part?.cid != widget.part?.cid ||
          _session.contentTarget != widget.target) {
        return;
      }
      if (commands?.hasNext == true) {
        if (widget.settings.continuousPlayback) {
          commands?.onCompleted?.call();
        }
      } else if (widget.settings.continuousRelatedPlayback) {
        commands?.onRelatedCompleted?.call();
      }
    });
  }

  @override
  void didUpdateWidget(covariant PlaybackPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged =
        widget.detail?.summary.id != oldWidget.detail?.summary.id ||
        widget.part?.cid != oldWidget.part?.cid ||
        widget.target != oldWidget.target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || (!_active && !_session.ownsPlayback(this))) return;
      if (sourceChanged) {
        unawaited(
          _session.activate(
            this,
            widget.detail,
            widget.part,
            target: widget.target,
            title: widget.title,
            visible: _active,
          ),
        );
      }
      if (!identical(widget.settings, oldWidget.settings)) _configure();
    });
    if (sourceChanged ||
        widget.settings.shortcuts != oldWidget.settings.shortcuts) {
      _shortcuts.cancel();
    }
    if (!identical(widget.settings, oldWidget.settings)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _settings.value = widget.settings;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _shortcuts.cancel();
      _landscapeRotationPending = false;
      _portraitExitRequest = null;
      _stopDeviceOrientation();
    } else {
      _syncDeviceOrientation();
    }
    // A video can keep playing behind another workspace tab. System lifecycle
    // still applies to its owner even when the page has no visible surface.
    if (widget.window.supportsBackgroundAudio) {
      if (state == AppLifecycleState.resumed) {
        unawaited(_session.setBackgroundAudio(false));
      } else if (_session.ownsPlayback(this) &&
          (state == AppLifecycleState.paused ||
              state == AppLifecycleState.hidden)) {
        unawaited(_session.setBackgroundAudio(true));
      }
    } else if (_session.ownsPlayback(this) &&
        !widget.window.hasDesktopWindow &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden)) {
      unawaited(_session.pause());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.snapshots.removeListener(_updateFullScreenOrientation);
    _session.snapshots.removeListener(_onPlaybackCompleted);
    _dismissFullScreen();
    _shortcuts.dispose();
    _session.detach(this);
    _settings.dispose();
    _controlsVisible.dispose();
    _pageCommands.dispose();
    _navigation.dispose();
    super.dispose();
  }

  void _dismissFullScreen() {
    _shortcuts.cancel();
    _portraitExitRequest = null;
    _stopDeviceOrientation();
    final request = _fullScreenRequest;
    _fullScreenRequest = null;
    // A disposed Navigator may never complete push(). Release platform state
    // independently, still ordered behind any pending entry for this owner.
    if (request != null) unawaited(_setWindowFullScreen(request, false));
    final route = _fullScreenRoute;
    final navigator = _fullScreenNavigator;
    if (route != null && navigator != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive && navigator.mounted) navigator.removeRoute(route);
      });
    }
  }

  bool _exitingShortcutFullScreen = false;
  Future<void> _exitFullScreen() async {
    if (_exitingShortcutFullScreen) return;
    _exitingShortcutFullScreen = true;
    _shortcuts.cancel();
    final route = _fullScreenRoute;
    final navigator = _fullScreenNavigator;
    FocusManager.instance.primaryFocus?.unfocus(
      disposition: UnfocusDisposition.scope,
    );
    await WidgetsBinding.instance.endOfFrame;
    if (mounted &&
        navigator != null &&
        navigator.mounted &&
        route != null &&
        route.isCurrent) {
      navigator.pop();
    } else if (route == null) {
      _dismissFullScreen();
    }
    _exitingShortcutFullScreen = false;
  }

  Future<void> _setWindowFullScreen(Object request, bool enabled) {
    final operation = _windowState.commands.then((_) async {
      if (enabled) {
        if (!identical(_fullScreenRequest, request) || !mounted || !_active) {
          return;
        }
        _windowState.owner = request;
        await widget.window.setFullScreen(
          true,
          orientation: _fullScreenOrientation,
        );
      } else if (identical(_windowState.owner, request)) {
        await widget.window.setFullScreen(false);
        if (identical(_windowState.owner, request)) _windowState.owner = null;
      }
    });
    _windowState.commands = operation.then(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  FullScreenOrientation? get _videoOrientation {
    final dimensions = _session.snapshots.value.videoDimensions;
    if (dimensions == null || dimensions.width <= 0 || dimensions.height <= 0) {
      return null;
    }
    return dimensions.width > dimensions.height
        ? FullScreenOrientation.landscape
        : FullScreenOrientation.portrait;
  }

  FullScreenOrientation? get _preferredFullScreenOrientation {
    if (!_isPhoneDisplay) return null;
    return _videoOrientation ??
        _fullScreenOrientation ??
        (_isViewLandscape
            ? FullScreenOrientation.landscape
            : FullScreenOrientation.portrait);
  }

  bool get _isPhoneDisplay {
    if (widget.window.hasDesktopWindow) return false;
    // Orientation locks can letterbox tablets. Use the physical display rather
    // than the app viewport, which can already be narrowed by compatibility mode
    // or multi-window. The shortest side keeps phone rotation below the cutoff.
    return WindowSizePolicy.compactDisplay(WindowSizePolicy.displaySize(_view));
  }

  bool get _usesCompactRotation {
    if (widget.window.hasDesktopWindow) return false;
    final view = _view;
    return WindowSizePolicy.compactLayout(
      mobile: true,
      displaySize: WindowSizePolicy.displaySize(view),
      availableWidth: WindowSizePolicy.availableWidth(view),
    );
  }

  bool get _isViewLandscape {
    final size = _view.physicalSize;
    return size.width > size.height;
  }

  bool get _isRotationLandscape {
    if (_isPhoneDisplay) return _isViewLandscape;
    final size = WindowSizePolicy.displaySize(_view);
    // A narrow tablet split can remain portrait-shaped after the device turns.
    // Its unrestricted display rotation, rather than a window resize, is input.
    return size.width > size.height;
  }

  bool get _appResumed =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  @override
  void didChangeMetrics() {
    final landscape = _isRotationLandscape;
    final compact = _usesCompactRotation;
    final phone = _isPhoneDisplay;
    final sizeClassChanged =
        compact != _rotationCompact || phone != _displayCompact;
    _rotationCompact = compact;
    _displayCompact = phone;
    if (sizeClassChanged) {
      // Folding, unfolding and split-window boundaries change layout, not the
      // user's fullscreen intent. The next sensor sample is a new baseline.
      _viewLandscape = landscape;
      _landscapeRotationPending = false;
      _portraitExitRequest = null;
      _physicalLandscapeSeen = false;
      _deviceOrientationBaselinePending = true;
      _metricsBaselinePending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Display metadata and the view rectangle can arrive separately during
        // the same fold. Consume the final rectangle as the new baseline.
        _metricsBaselinePending = false;
        _viewLandscape = _isRotationLandscape;
      });
    } else if (landscape != _viewLandscape) {
      _viewLandscape = landscape;
      _landscapeRotationPending =
          !_fullScreen &&
          _active &&
          _appResumed &&
          compact &&
          (!phone ||
              (widget.window.supportsPhoneRotationActions &&
                  !_deviceRotationBlocked)) &&
          !_metricsBaselinePending &&
          !widget.window.keepsBrowsePortrait &&
          landscape;
      if (landscape) _portraitExitRequest = null;
      if (!landscape &&
          _fullScreen &&
          compact &&
          (!phone ||
              (widget.window.supportsPhoneRotationActions &&
                  !_deviceRotationBlocked)) &&
          !_metricsBaselinePending &&
          !widget.window.keepsBrowsePortrait &&
          _videoOrientation == FullScreenOrientation.landscape) {
        _schedulePortraitExit(_fullScreenRequest);
      }
    }
    _updateFullScreenOrientation();
  }

  void _scheduleAutoFullScreen() {
    if (_rotationCallbackPending ||
        !_landscapeRotationPending ||
        !_active ||
        !_appResumed ||
        !_usesCompactRotation ||
        _fullScreen ||
        !_session.ownsPlayback(this) ||
        !_session.snapshots.value.desiredPlaying ||
        _videoOrientation != FullScreenOrientation.landscape) {
      return;
    }
    _rotationCallbackPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rotationCallbackPending = false;
      if (!mounted ||
          !_active ||
          !_appResumed ||
          !_usesCompactRotation ||
          !_landscapeRotationPending ||
          (!_isRotationLandscape &&
              _deviceOrientation != FullScreenOrientation.landscape) ||
          !_session.ownsPlayback(this) ||
          !_session.snapshots.value.desiredPlaying ||
          _videoOrientation != FullScreenOrientation.landscape ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      unawaited(_enterFullScreen());
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _schedulePortraitExit(Object? request) {
    if (request == null) return;
    final exitRequest = Object();
    _portraitExitRequest = exitRequest;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _active &&
          _appResumed &&
          _usesCompactRotation &&
          identical(exitRequest, _portraitExitRequest) &&
          identical(request, _fullScreenRequest)) {
        unawaited(_exitFullScreen());
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _syncDeviceOrientation() {
    final watch =
        mounted &&
        _active &&
        _appResumed &&
        _isPhoneDisplay &&
        widget.window.supportsPhoneRotationActions &&
        (_fullScreen
            ? _fullScreenRequest != null
            : _session.ownsPlayback(this) &&
                  _session.snapshots.value.desiredPlaying &&
                  _videoOrientation == FullScreenOrientation.landscape);
    if (!watch) {
      _stopDeviceOrientation();
      return;
    }
    if (_deviceOrientationSubscription != null) return;
    final owner = Object();
    _deviceOrientationOwner = owner;
    _deviceOrientationSubscription = widget.window.deviceOrientations.listen((
      orientation,
    ) {
      if (!mounted ||
          !_active ||
          !_appResumed ||
          !_isPhoneDisplay ||
          !identical(owner, _deviceOrientationOwner)) {
        return;
      }
      if (orientation == null) {
        _deviceRotationBlocked = true;
        _deviceOrientation = null;
        _deviceOrientationBaselinePending = true;
        _physicalLandscapeSeen = false;
        _landscapeRotationPending = false;
        _portraitExitRequest = null;
        return;
      }
      _deviceRotationBlocked = false;
      if (_deviceOrientationBaselinePending) {
        _deviceOrientationBaselinePending = false;
        _deviceOrientation = orientation;
        _physicalLandscapeSeen = orientation == FullScreenOrientation.landscape;
        return;
      }
      if (_deviceOrientation == orientation) return;
      _deviceOrientation = orientation;
      if (orientation == FullScreenOrientation.landscape) {
        _physicalLandscapeSeen = true;
        _portraitExitRequest = null;
        if (!_fullScreen) {
          _landscapeRotationPending = true;
          _scheduleAutoFullScreen();
        }
      } else {
        _landscapeRotationPending = false;
        if (_physicalLandscapeSeen &&
            _videoOrientation == FullScreenOrientation.landscape) {
          _schedulePortraitExit(_fullScreenRequest);
        }
      }
    });
  }

  void _stopDeviceOrientation() {
    _deviceOrientationOwner = null;
    unawaited(_deviceOrientationSubscription?.cancel());
    _deviceOrientationSubscription = null;
  }

  void _updateFullScreenOrientation() {
    _syncDeviceOrientation();
    _scheduleAutoFullScreen();
    final request = _fullScreenRequest;
    if (request == null ||
        !_fullScreen ||
        !_active ||
        widget.window.hasDesktopWindow) {
      return;
    }
    final orientation = _preferredFullScreenOrientation;
    if (orientation == _fullScreenOrientation) return;
    _fullScreenOrientation = orientation;
    // The same owner/command queue also orders delayed dimensions against exit.
    unawaited(_setWindowFullScreen(request, true));
  }

  Future<void> _enterFullScreen() async {
    if (_fullScreen || !_active) return;
    _shortcuts.cancel();
    final request = Object();
    final providerContainer = ProviderScope.containerOf(context);
    _fullScreenOrientation = _preferredFullScreenOrientation;
    _fullScreenRequest = request;
    _landscapeRotationPending = false;
    // While portrait browsing is locked, only physical posture can confirm a
    // landscape hold; the interface may be rotating because of the button.
    _physicalLandscapeSeen =
        _deviceOrientation == FullScreenOrientation.landscape ||
        (!widget.window.keepsBrowsePortrait && _isViewLandscape);
    setState(() => _fullScreen = true);
    _syncDeviceOrientation();
    try {
      // Unmount the inline surface before the route surface is created.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_active || !identical(_fullScreenRequest, request)) {
        return;
      }
      await _setWindowFullScreen(request, true);
      if (!mounted || !_active || !identical(_fullScreenRequest, request)) {
        return;
      }
      // The detached view remains below the browser's Navigator in the widget
      // tree. Use this window's Navigator so its route fills the playback view.
      final navigator = Navigator.of(context);
      final route = RawDialogRoute<void>(
        requestFocus: false,
        barrierDismissible: false,
        barrierLabel: '全屏播放器',
        transitionDuration: Duration.zero,
        pageBuilder: (dialogContext, _, _) => UncontrolledProviderScope(
          container: providerContainer,
          child: AndroidSystemUi(
            backgroundColor: Colors.black,
            brightness: Brightness.dark,
            child: Dialog.fullscreen(
              backgroundColor: Colors.black,
              child: _PlayerView(
                session: _session,
                settings: _settings,
                controlsVisible: _controlsVisible,
                shortcuts: _shortcuts,
                onToggleComments: () => widget.onToggleComments(),
                danmakuComposerBuilder: widget.danmakuComposerBuilder == null
                    ? null
                    : (context) =>
                          widget.danmakuComposerBuilder?.call(context) ??
                          const SizedBox.shrink(),
                danmakuOverlayBuilder: widget.danmakuOverlayBuilder == null
                    ? null
                    : (context) =>
                          widget.danmakuOverlayBuilder?.call(context) ??
                          const SizedBox.shrink(),
                pageCommands: _pageCommands,
                navigation: _navigation,
                onNavigate: _navigateFromPlayer,
                fullScreen: true,
                onFullScreen: () {
                  if (identical(
                    _fullScreenRoute,
                    ModalRoute.of(dialogContext),
                  )) {
                    navigator.pop();
                  }
                },
              ),
            ),
          ),
        ),
      );
      InputScope.of<Object>(context)?.routes.presentation(route);
      _fullScreenRoute = route;
      _fullScreenNavigator = navigator;
      await navigator.push(route);
    } finally {
      _stopDeviceOrientation();
      if (identical(_fullScreenRequest, request)) _fullScreenRequest = null;
      _fullScreenRoute = null;
      _fullScreenNavigator = null;
      await WidgetsBinding.instance.endOfFrame;
      await _setWindowFullScreen(request, false);
      _fullScreenOrientation = null;
      if (mounted) {
        setState(() => _fullScreen = false);
        _syncDeviceOrientation();
      }
    }
  }

  @override
  Widget build(BuildContext context) => CommandTargetScope<Object>(
    scope: CommandScope.playback,
    active: _active,
    onCancel: _shortcuts.cancel,
    revision: () => _session.sourceGeneration,
    onNavigate: _dismissFullScreen,
    commands: {
      for (final action in _shortcuts.capabilities)
        action: (stroke) => _shortcuts.execute(action, stroke),
    },
    child: _fullScreen
        ? const ColoredBox(color: Colors.black)
        : _PlayerView(
            session: _session,
            settings: _settings,
            controlsVisible: _controlsVisible,
            shortcuts: _shortcuts,
            onToggleComments: widget.onToggleComments,
            danmakuComposerBuilder: widget.danmakuComposerBuilder,
            danmakuOverlayBuilder: widget.danmakuOverlayBuilder,
            onFullScreen: _enterFullScreen,
            pageCommands: _pageCommands,
            navigation: _navigation,
            onNavigate: _navigateFromPlayer,
            fullScreen: false,
            active: _active && _surfaceReady,
          ),
  );

  void _navigateFromPlayer(VoidCallback action) {
    _shortcuts.cancel();
    _dismissFullScreen();
    action();
  }
}

class _PlayerView extends StatefulWidget {
  const _PlayerView({
    required this.session,
    required this.settings,
    required this.controlsVisible,
    required this.shortcuts,
    required this.onToggleComments,
    required this.onFullScreen,
    required this.fullScreen,
    required this.pageCommands,
    required this.navigation,
    required this.onNavigate,
    this.active = true,
    this.danmakuComposerBuilder,
    this.danmakuOverlayBuilder,
  });
  final PlaybackSession session;
  final ValueListenable<AppSettings> settings;
  final ValueNotifier<bool> controlsVisible;
  final PlaybackShortcutController shortcuts;
  final VoidCallback onToggleComments;
  final VoidCallback onFullScreen;
  final bool fullScreen;
  final ValueListenable<PlaybackPageCommands?> pageCommands;
  final ValueListenable<PlaybackNavigation?> navigation;
  final ValueChanged<VoidCallback> onNavigate;
  final bool active;
  final WidgetBuilder? danmakuComposerBuilder;
  final WidgetBuilder? danmakuOverlayBuilder;
  @override
  State<_PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<_PlayerView> with WidgetsBindingObserver {
  _ControlsLayout? _cachedControlsLayout;
  final _swipeSeekPreview = ValueNotifier<Duration?>(null);
  final FocusNode _focusNode = FocusNode(debugLabel: 'video player');
  final GlobalKey _playerBoundsKey = GlobalKey();
  bool _exitingFullScreen = false;
  bool _composeExpanded = false;
  final GlobalKey _composerKey = GlobalKey();
  Timer? _controlsHideTimer;
  final Set<int> _pressedPointers = {};
  final Set<String> _hoveredControlRegions = {};
  bool _mouseInside = false;
  PointerDeviceKind? _doubleTapKind;
  late AppLifecycleState? _appLifecycleState;
  bool _controlEditorFocused = false;
  int _openControlsMenus = 0;
  late int _sourceGeneration;
  late bool _hasError;
  late PlayerControlsMode _controlsMode;

  bool get _dynamicControls => _controlsMode == PlayerControlsMode.dynamic;
  bool get _appActive =>
      _appLifecycleState == null ||
      _appLifecycleState == AppLifecycleState.resumed;
  // An inactive desktop window is still visible and receives mouse hover.
  bool get _appVisible =>
      _appActive || _appLifecycleState == AppLifecycleState.inactive;
  bool get _canAutoHideControls => _dynamicControls ? _appVisible : _appActive;

  @override
  void initState() {
    super.initState();
    _appLifecycleState = WidgetsBinding.instance.lifecycleState;
    _controlsMode = widget.settings.value.playerControlsMode;
    _sourceGeneration = widget.session.sourceGeneration;
    _hasError = widget.session.error != null;
    widget.settings.addListener(_onSettingsChanged);
    widget.session.addListener(_onSessionChanged);
    widget.controlsVisible.addListener(_syncHighEnergyVisibility);
    FocusManager.instance.addListener(_onControlsFocusChanged);
    WidgetsBinding.instance.addObserver(this);
    _scheduleControlsHide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncHighEnergyVisibility();
    });
  }

  void _syncHighEnergyVisibility() =>
      widget.session.setHighEnergySurfaceVisible(
        this,
        mounted && widget.active && _appVisible && widget.controlsVisible.value,
      );

  void _onSessionChanged() {
    _syncHighEnergyVisibility();
    final generation = widget.session.sourceGeneration;
    final hasError = widget.session.error != null;
    if (_sourceGeneration == generation && _hasError == hasError) return;
    _sourceGeneration = generation;
    _hasError = hasError;
    if (!_dynamicControls) _scheduleControlsHide();
  }

  void _onControlsFocusChanged() {
    final context = FocusManager.instance.primaryFocus?.context;
    final editing =
        context?.findAncestorWidgetOfExactType<EditableText>() != null &&
        context?.findAncestorStateOfType<_PlayerViewState>() == this;
    if (_controlEditorFocused == editing) return;
    _controlEditorFocused = editing;
    _scheduleControlsHide();
  }

  void _onControlsMenuChanged(bool open) {
    if (!mounted) return;
    if (open) {
      _openControlsMenus++;
    } else if (_openControlsMenus > 0) {
      _openControlsMenus--;
    }
    if (open) widget.controlsVisible.value = true;
    _scheduleControlsHide();
  }

  void _onSettingsChanged() {
    final mode = widget.settings.value.playerControlsMode;
    if (_controlsMode != mode) {
      _controlsMode = mode;
      _pressedPointers.clear();
      if (_dynamicControls && _mouseInside) {
        _showDynamicControls();
      } else {
        _scheduleControlsHide();
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant _PlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _swipeSeekPreview.value = null;
      _syncHighEnergyVisibility();
      _mouseInside = false;
      _pressedPointers.clear();
      _hoveredControlRegions.clear();
      _scheduleControlsHide();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    if (mounted) setState(() {});
    _syncHighEnergyVisibility();
    _pressedPointers.clear();
    _scheduleControlsHide();
  }

  @override
  void dispose() {
    _controlsHideTimer?.cancel();
    _pressedPointers.clear();
    WidgetsBinding.instance.removeObserver(this);
    widget.settings.removeListener(_onSettingsChanged);
    widget.session.removeListener(_onSessionChanged);
    widget.controlsVisible.removeListener(_syncHighEnergyVisibility);
    widget.session.setHighEnergySurfaceVisible(this, false);
    FocusManager.instance.removeListener(_onControlsFocusChanged);
    widget.shortcuts.endTouchHold();
    _swipeSeekPreview.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scheduleControlsHide() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = null;
    if (!mounted ||
        !widget.active ||
        !_canAutoHideControls ||
        !widget.controlsVisible.value ||
        _pressedPointers.isNotEmpty ||
        _hoveredControlRegions.isNotEmpty ||
        // PopupMenuButton must stay mounted until its route returns a selection.
        _openControlsMenus > 0 ||
        _controlEditorFocused ||
        (!_dynamicControls && _hasError)) {
      return;
    }
    _controlsHideTimer = Timer(
      Duration(milliseconds: _dynamicControls ? 2500 : 5000),
      () {
        _controlsHideTimer = null;
        if (mounted && widget.active && _canAutoHideControls) {
          widget.controlsVisible.value = false;
        }
      },
    );
  }

  void _showDynamicControls() {
    if (!_dynamicControls || !widget.active || !_appVisible) return;
    widget.controlsVisible.value = true;
    _scheduleControlsHide();
  }

  void _onMouseActivity() {
    if (_dynamicControls) {
      _showDynamicControls();
    } else {
      _scheduleControlsHide();
    }
  }

  void _onMouseEnter(PointerEnterEvent event) {
    _mouseInside = true;
    _onMouseActivity();
  }

  void _onMouseExit(PointerExitEvent event) {
    _mouseInside = false;
    // IME candidate UI can take the pointer outside the player while the
    // composer is still editing. Hiding controls would revoke its focus.
    if (!_dynamicControls ||
        !widget.active ||
        _openControlsMenus > 0 ||
        _controlEditorFocused) {
      return;
    }
    _controlsHideTimer?.cancel();
    _controlsHideTimer = null;
    widget.controlsVisible.value = false;
  }

  void _onPointerDown(PointerDownEvent event) {
    final touchHold =
        !widget.session.isLive && event.kind == PointerDeviceKind.touch;
    if (!touchHold) return;
    _onControlPointerDown(event);
  }

  void _onControlPointerDown(PointerDownEvent event) {
    _pressedPointers.add(event.pointer);
    _scheduleControlsHide();
  }

  void _onPointerEnd(PointerEvent event) {
    if (_pressedPointers.remove(event.pointer)) _scheduleControlsHide();
  }

  void _onSurfaceTap() {
    if (!widget.active) return;
    _focusNode.requestFocus();
    if (_dynamicControls) {
      if (!widget.session.isLive) {
        _showDynamicControls();
        unawaited(widget.session.togglePlaying());
      }
    } else {
      widget.controlsVisible.value = !widget.controlsVisible.value;
      _scheduleControlsHide();
    }
  }

  void _onSurfaceDoubleTap() {
    final kind = _doubleTapKind;
    _doubleTapKind = null;
    if (!widget.active || !_appActive || kind == null) return;
    final input = InputScope.of<Object>(context);
    if (input?.routes.modal == true || (input?.dispatcher.barriers ?? 0) != 0) {
      return;
    }
    _focusNode.requestFocus();
    if (kind == PointerDeviceKind.touch) {
      unawaited(widget.session.togglePlaying());
    } else {
      _toggleFullScreen();
    }
  }

  void _onSurfacePointerSignal(PointerSignalEvent event) {
    if (!widget.active ||
        !_appActive ||
        event is! PointerScrollEvent ||
        event.kind != PointerDeviceKind.mouse ||
        !event.scrollDelta.dy.isFinite ||
        event.scrollDelta.dy == 0) {
      return;
    }
    final input = InputScope.of<Object>(context);
    if (input?.routes.modal == true || (input?.dispatcher.barriers ?? 0) != 0) {
      return;
    }
    // Claim only the picture's wheel event so enclosing pages do not scroll.
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!mounted || !widget.active || !_appActive) return;
      unawaited(
        widget.shortcuts.adjustVolume(event.scrollDelta.dy < 0 ? 5 : -5),
      );
    });
  }

  Future<void> _openSettings(int tab) async {
    widget.shortcuts.cancel();
    _onControlsMenuChanged(true);
    try {
      await showPlayerSettings(context, tab: tab);
    } finally {
      widget.shortcuts.cancel();
      _onControlsMenuChanged(false);
    }
  }

  Widget _controlsVisibility({
    required bool visible,
    required String hoverRegion,
    required Widget child,
    bool retainDynamicPress = false,
  }) => _FadingPlayerControls(
    visible: visible,
    onHoverChanged: (hovered) {
      if (hovered) {
        _hoveredControlRegions.add(hoverRegion);
      } else {
        _hoveredControlRegions.remove(hoverRegion);
      }
      _scheduleControlsHide();
    },
    child: Listener(
      onPointerDown: !_dynamicControls || retainDynamicPress
          ? _onControlPointerDown
          : null,
      child: child,
    ),
  );

  void _toggleFullScreen() {
    if (!widget.fullScreen) {
      widget.onFullScreen();
      return;
    }
    if (_exitingFullScreen) return;
    _exitingFullScreen = true;
    _focusNode.unfocus(disposition: UnfocusDisposition.scope);
    FocusScope.of(context).unfocus(disposition: UnfocusDisposition.scope);
    unawaited(_finishFullScreenExit());
  }

  Future<void> _finishFullScreenExit() async {
    // Let focus and semantics updates reach the engine before removing the
    // fullscreen route's focused subtree.
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) widget.onFullScreen();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const ColoredBox(color: Colors.black);
    return MouseRegion(
      onEnter: _onMouseEnter,
      onHover: (_) => _onMouseActivity(),
      onExit: _onMouseExit,
      child: Listener(
        onPointerSignal: _onSurfacePointerSignal,
        onPointerDown: _onPointerDown,
        onPointerMove: (event) {
          if (event.kind == PointerDeviceKind.mouse && _mouseInside) {
            _onMouseActivity();
          }
        },
        onPointerUp: _onPointerEnd,
        onPointerCancel: _onPointerEnd,
        child: _buildPlayer(context),
      ),
    );
  }

  _ControlsLayout _controlsLayout(
    BuildContext context,
    PlaybackSnapshot snapshot,
    double width,
  ) {
    final session = widget.session;
    final media = session.media;
    final inputs = (
      width: width,
      timeLabel: session.isLive
          ? '直播中'
          : '${_time(snapshot.duration)} / ${_time(snapshot.duration)}',
      rateLabel: session.isLive ? null : '${snapshot.rate}x',
      qualityLabel:
          media != null && (session.isLive || media.qualities.length > 1)
          ? session.isLive
                ? liveQualityLabel(session, media)
                : media.qualityLabels[media.quality] ?? _quality(media.quality)
          : null,
      hasComposer: widget.danmakuComposerBuilder != null,
      hasSubtitles: session.subtitleTracks.isNotEmpty,
      hasVoices: session.voiceTracks.isNotEmpty,
      hasListen: session.canListen,
      hasNextButton:
          !session.isLive && session.contentTarget is! OfflinePlaybackTarget,
      isLive: session.isLive,
      textStyle: DefaultTextStyle.of(context).style,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    );
    // Position ticks and keyboard height changes do not change label widths.
    // Retain only the most recent measurement, including its typography.
    final cached = _cachedControlsLayout;
    if (cached != null && cached.inputs == inputs) return cached;
    return _cachedControlsLayout = _ControlsLayout(inputs);
  }

  Widget _buildPlayer(BuildContext context) {
    final session = widget.session;
    final appTextStyle = Theme.of(context).textTheme.bodyMedium;
    return InputProtection(
      playerSurface: true,
      activationFocus: _focusNode,
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        includeSemantics: false,
        child: ListenableBuilder(
          listenable: _focusNode,
          builder: (context, _) => Semantics(
            container: true,
            explicitChildNodes: true,
            label: '视频播放器',
            focusable: _focusNode.canRequestFocus,
            onTap: _onSurfaceTap,
            focused: _focusNode.hasPrimaryFocus,
            onFocus: _focusNode.requestFocus,
            child: ListenableBuilder(
              listenable: Listenable.merge([
                session,
                widget.controlsVisible,
                widget.shortcuts,
                widget.pageCommands,
              ]),
              builder: (context, _) => PlaybackSnapshotBuilder(
                snapshots: session.snapshots,
                select: (snapshot) => (
                  session.isLive,
                  snapshot.phase,
                  snapshot.duration,
                  snapshot.desiredPlaying,
                  snapshot.isBuffering,
                  snapshot.isSeeking,
                  snapshot.rate,
                  snapshot.volume,
                ),
                builder: (context, snapshot) {
                  final sourceGeneration = session.sourceGeneration;
                  final settings = widget.settings.value;
                  if (session.audioOnly) {
                    return AudioPlaybackView(
                      key: _playerBoundsKey,
                      session: session,
                      snapshot: snapshot,
                      fullScreen: widget.fullScreen,
                      onFullScreen: _toggleFullScreen,
                      commands: widget.pageCommands.value,
                      navigation: ValueListenableBuilder<PlaybackNavigation?>(
                        valueListenable: widget.navigation,
                        builder: (context, actions, _) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (actions?.showInPlayer ?? false)
                              IconButton(
                                key: const ValueKey('player-back'),
                                tooltip: '返回',
                                onPressed: widget.fullScreen
                                    ? _toggleFullScreen
                                    : actions == null
                                    ? null
                                    : () => widget.onNavigate(actions.onBack),
                                icon: const Icon(Icons.arrow_back_rounded),
                              ),
                            if (actions?.showInPlayer ?? false)
                              IconButton(
                                key: const ValueKey('player-home'),
                                tooltip: '回到主页',
                                onPressed: actions == null
                                    ? null
                                    : () => widget.onNavigate(actions.onHome),
                                icon: const Icon(Icons.home_outlined),
                              ),
                          ],
                        ),
                      ),
                    );
                  }
                  final controls =
                      widget.controlsVisible.value || session.error != null;
                  return WidthLayoutBuilder(
                    builder: (context, width) {
                      final layout = _controlsLayout(
                        context,
                        snapshot,
                        width - 20,
                      );
                      final smallWindow = layout.compact && !widget.fullScreen;
                      return ColoredBox(
                        key: _playerBoundsKey,
                        color: Colors.black,
                        child: VideoCompositionScope.of(context).compose(
                          context,
                          layers: [
                            if (widget.active)
                              VideoSurface(engine: session.engine),
                            if (widget.active && settings.danmakuEnabled)
                              Opacity(
                                opacity: settings.danmakuOpacity,
                                child: switch (widget.danmakuOverlayBuilder) {
                                  final builder? => Builder(builder: builder),
                                  null when session.isLive =>
                                    const SizedBox.shrink(),
                                  null => DanmakuOverlay(
                                    controller: session.danmaku,
                                    bottomInset: controls ? 100 : 48,
                                  ),
                                },
                              ),
                            Positioned.fill(
                              child: RepaintBoundary(
                                child: PlayerSeekControls(
                                  enabled:
                                      widget.active &&
                                      !session.isLive &&
                                      !session.isResolving &&
                                      session.media != null &&
                                      session.error == null &&
                                      snapshot.phase != PlaybackPhase.opening &&
                                      snapshot.phase != PlaybackPhase.idle,
                                  sourceGeneration: sourceGeneration,
                                  position: () =>
                                      session.snapshots.value.position,
                                  duration: snapshot.duration,
                                  preview: _swipeSeekPreview,
                                  storyboard: session.storyboard,
                                  storyboardLoading: session.storyboardLoading,
                                  onPreviewRequest: () {
                                    if (session.sourceGeneration ==
                                        sourceGeneration) {
                                      unawaited(session.ensureStoryboard());
                                    }
                                  },
                                  onSeek: (position) async {
                                    // A source may change before the next UI frame.
                                    if (widget.active &&
                                        _appActive &&
                                        session.sourceGeneration ==
                                            sourceGeneration &&
                                        !session.isResolving &&
                                        !session.isLive &&
                                        session.media != null &&
                                        session.error == null) {
                                      await session.seek(position);
                                    }
                                  },
                                  child: PlayerSwipeControls(
                                    enabled:
                                        settings.fullscreenSwipeControls &&
                                        widget.active,
                                    sourceGeneration: sourceGeneration,
                                    volume: snapshot.volume,
                                    setVolume: session.setVolume,
                                    child: RawGestureDetector(
                                      // The recognizer's deadline is fixed at creation.
                                      key: ValueKey(
                                        settings.shortcuts.holdDelayMs,
                                      ),
                                      behavior: HitTestBehavior.translucent,
                                      excludeFromSemantics: true,
                                      gestures: {
                                        if (!session.isLive)
                                          LongPressGestureRecognizer:
                                              GestureRecognizerFactoryWithHandlers<
                                                LongPressGestureRecognizer
                                              >(
                                                () =>
                                                    LongPressGestureRecognizer(
                                                      duration: Duration(
                                                        milliseconds: settings
                                                            .shortcuts
                                                            .holdDelayMs,
                                                      ),
                                                      supportedDevices: {
                                                        PointerDeviceKind.touch,
                                                      },
                                                    ),
                                                (recognizer) {
                                                  recognizer.onLongPressDown =
                                                      (_) => widget.shortcuts
                                                          .prepareTouchHold();
                                                  recognizer.onLongPressStart =
                                                      (_) => widget.shortcuts
                                                          .beginTouchHold();
                                                  recognizer
                                                          .onLongPressMoveUpdate =
                                                      (details) => widget
                                                          .shortcuts
                                                          .moveTouchHold(
                                                            dx: details
                                                                .offsetFromOrigin
                                                                .dx,
                                                            dy: details
                                                                .offsetFromOrigin
                                                                .dy,
                                                          );
                                                  recognizer.onLongPressEnd =
                                                      (_) => widget.shortcuts
                                                          .endTouchHold();
                                                  recognizer.onLongPressCancel =
                                                      widget
                                                          .shortcuts
                                                          .endTouchHold;
                                                },
                                              ),
                                      },
                                      child: GestureDetector(
                                        key: const ValueKey(
                                          'player-surface-tap-target',
                                        ),
                                        behavior: HitTestBehavior.translucent,
                                        onTap: _onSurfaceTap,
                                        onDoubleTapDown: (details) =>
                                            _doubleTapKind = details.kind,
                                        onDoubleTapCancel: () =>
                                            _doubleTapKind = null,
                                        onDoubleTap: _onSurfaceDoubleTap,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (widget.shortcuts.rateFeedback ||
                                widget.shortcuts.isHoldingRate)
                              Positioned(
                                key: const ValueKey('player-rate-hud'),
                                left: 16,
                                top: controls ? 52 : 16,
                                child: IgnorePointer(
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Container(
                                      key: const ValueKey(
                                        'player-rate-feedback',
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 7,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: .7,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: DefaultTextStyle(
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              widget.shortcuts.isHoldingRate
                                                  ? '长按倍速 ${snapshot.rate}x'
                                                  : widget.shortcuts.isRateFixed
                                                  ? '固定倍速 ${snapshot.rate}x'
                                                  : '播放速度 ${snapshot.rate}x',
                                            ),
                                            if (widget.shortcuts.touchHoldHint
                                                case final hint?)
                                              Text(hint),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (!smallWindow &&
                                layout.compact &&
                                session.isLive &&
                                !_composeExpanded &&
                                session.error == null &&
                                !session.isResolving &&
                                snapshot.phase != PlaybackPhase.opening)
                              Center(
                                key: const ValueKey(
                                  'player-control-actions-layer',
                                ),
                                child: _controlsVisibility(
                                  visible: controls,
                                  hoverRegion: 'actions',
                                  child: Row(
                                    key: const ValueKey(
                                      'compact-playback-actions',
                                    ),
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _PlayButton(
                                        session: session,
                                        snapshot: snapshot,
                                        onFocus: _focusNode.requestFocus,
                                        prominent: true,
                                        shortcuts:
                                            widget.settings.value.shortcuts,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (!smallWindow)
                              Positioned(
                                key: const ValueKey(
                                  'player-control-title-layer',
                                ),
                                left: 0,
                                right: 0,
                                top: 0,
                                child: _PlaybackViewers(
                                  request: _appVisible
                                      ? _viewerRequest(session)
                                      : null,
                                  builder: (viewers) => _controlsVisibility(
                                    visible: controls,
                                    hoverRegion: 'title',
                                    child: _PlayerTopBar(
                                      navigation: widget.navigation,
                                      fullScreen: widget.fullScreen,
                                      onExitFullScreen: _toggleFullScreen,
                                      onNavigate: widget.onNavigate,
                                      viewers: viewers,
                                    ),
                                  ),
                                ),
                              ),
                            PlaybackSnapshotBuilder(
                              snapshots: session.snapshots,
                              select: (_) => session.currentSponsor,
                              builder: (context, _) {
                                final segment = session.currentSponsor;
                                if (segment == null || smallWindow) {
                                  return const SizedBox.shrink();
                                }
                                return Positioned(
                                  right: 16,
                                  bottom: controls ? 120 : 40,
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      minimumSize: const Size(0, 32),
                                    ),
                                    onPressed: () =>
                                        unawaited(session.skipSponsor(segment)),
                                    icon: const Icon(
                                      Icons.fast_forward,
                                      size: 18,
                                    ),
                                    label: Text(
                                      '跳过${sponsorCategoryLabel(segment.category)}',
                                    ),
                                  ),
                                );
                              },
                            ),
                            if (session.error == null &&
                                (session.isResolving ||
                                    session.isRecovering ||
                                    snapshot.phase != PlaybackPhase.ended &&
                                        snapshot.isBuffering ||
                                    snapshot.phase == PlaybackPhase.opening))
                              const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(
                                      color: Colors.white,
                                    ),
                                    SizedBox(height: 14),
                                    Text(
                                      '正在准备音视频…',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (session.error case final String error)
                              Positioned(
                                left: 0,
                                right: 0,
                                top: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  color: Colors.black87,
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.error_outline,
                                        color: Colors.white70,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          error,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        tooltip: '播放错误选项',
                                        icon: const Icon(
                                          Icons.more_vert,
                                          color: Colors.white,
                                        ),
                                        onSelected: (action) {
                                          if (action == 'reload') {
                                            unawaited(session.retry());
                                          } else {
                                            widget.onFullScreen();
                                          }
                                        },
                                        itemBuilder: (_) => [
                                          const PopupMenuItem(
                                            value: 'reload',
                                            child: Text('重新加载'),
                                          ),
                                          if (widget.fullScreen)
                                            const PopupMenuItem(
                                              value: 'exitFullScreen',
                                              child: Text('退出全屏'),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (!controls &&
                                settings.showCollapsedProgress &&
                                !session.isLive &&
                                snapshot.duration.inMilliseconds > 0)
                              PlaybackSnapshotBuilder(
                                snapshots: session.snapshots,
                                select: (snapshot) => (
                                  snapshot.position,
                                  snapshot.duration,
                                  snapshot.buffered,
                                ),
                                builder: (context, snapshot) => Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: RepaintBoundary(
                                    child: IgnorePointer(
                                      child: CustomPaint(
                                        foregroundPainter:
                                            ChapterBoundaryPainter(
                                              chapters: session.chapters,
                                              duration: snapshot.duration,
                                              textDirection: Directionality.of(
                                                context,
                                              ),
                                            ),
                                        child: SizedBox(
                                          height: 2,
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              LinearProgressIndicator(
                                                key: const ValueKey(
                                                  'player-collapsed-buffer',
                                                ),
                                                minHeight: 2,
                                                borderRadius: BorderRadius.zero,
                                                value:
                                                    (snapshot
                                                                .buffered
                                                                .inMilliseconds /
                                                            snapshot
                                                                .duration
                                                                .inMilliseconds)
                                                        .clamp(0, 1),
                                                color: Colors.white38,
                                                backgroundColor: Colors.white24,
                                              ),
                                              ValueListenableBuilder<Duration?>(
                                                valueListenable:
                                                    _swipeSeekPreview,
                                                builder: (context, preview, _) =>
                                                    LinearProgressIndicator(
                                                      key: const ValueKey(
                                                        'player-collapsed-progress',
                                                      ),
                                                      minHeight: 2,
                                                      borderRadius:
                                                          BorderRadius.zero,
                                                      value:
                                                          ((preview ??
                                                                          snapshot
                                                                              .position)
                                                                      .inMilliseconds /
                                                                  snapshot
                                                                      .duration
                                                                      .inMilliseconds)
                                                              .clamp(0, 1),
                                                      color: const Color(
                                                        0xffdf6589,
                                                      ),
                                                      backgroundColor:
                                                          Colors.transparent,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Positioned.fill(
                              child: _BottomPlayerLayers(
                                controlsVisible: controls && widget.active,
                                subtitleBottomPadding:
                                    settings.subtitleBottomPadding,
                                children: [
                                  PlaybackSnapshotBuilder(
                                    snapshots: session.snapshots,
                                    select: (snapshot) =>
                                        session.subtitleAt(snapshot.position),
                                    builder: (context, snapshot) {
                                      final cue = session.subtitleAt(
                                        snapshot.position,
                                      );
                                      if (cue == null) {
                                        return LayoutId(
                                          id: _BottomPlayerSlot.subtitle,
                                          child: const SizedBox.shrink(),
                                        );
                                      }
                                      return LayoutId(
                                        id: _BottomPlayerSlot.subtitle,
                                        child: IgnorePointer(
                                          child: Center(
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 4,
                                                  ),
                                              color: Colors.black.withValues(
                                                alpha: settings
                                                    .subtitleBackgroundOpacity,
                                              ),
                                              child: Text(
                                                cue.text,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize:
                                                      22 *
                                                      settings
                                                          .subtitleFontScale,
                                                  shadows: [
                                                    const Shadow(
                                                      color: Colors.black,
                                                      blurRadius: 4,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  if (session.subtitleLoading ||
                                      session.subtitleMessage != null)
                                    LayoutId(
                                      id: _BottomPlayerSlot.subtitleMessage,
                                      child: IgnorePointer(
                                        child: Center(
                                          child: Text(
                                            session.subtitleLoading
                                                ? '字幕加载中…'
                                                : session.subtitleMessage!,
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                              shadows: [
                                                Shadow(
                                                  color: Colors.black,
                                                  blurRadius: 4,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (widget.active)
                                    LayoutId(
                                      key: const ValueKey(
                                        'player-control-bar-layer',
                                      ),
                                      id: _BottomPlayerSlot.controls,
                                      child: _controlsVisibility(
                                        visible: controls,
                                        hoverRegion: 'bar',
                                        retainDynamicPress: true,
                                        child: Theme(
                                          data:
                                              ThemeData(
                                                brightness: Brightness.dark,
                                                useMaterial3: true,
                                                fontFamily:
                                                    appTextStyle?.fontFamily,
                                                fontFamilyFallback: appTextStyle
                                                    ?.fontFamilyFallback,
                                              ).copyWith(
                                                colorScheme:
                                                    ColorScheme.fromSeed(
                                                      seedColor: const Color(
                                                        0xffdf6589,
                                                      ),
                                                      brightness:
                                                          Brightness.dark,
                                                    ),
                                              ),
                                          child: Container(
                                            key: const ValueKey(
                                              'player-controls',
                                            ),
                                            padding: const EdgeInsets.only(
                                              top: 12,
                                              bottom: 6,
                                            ),
                                            decoration: const BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                  Colors.transparent,
                                                  Color(0xe6000000),
                                                ],
                                              ),
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (!smallWindow &&
                                                    session.auxiliaryMessage !=
                                                        null)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                        ),
                                                    child: Text(
                                                      session.auxiliaryMessage!,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ),
                                                if (!session.isLive)
                                                  PlaybackSnapshotBuilder(
                                                    snapshots:
                                                        session.snapshots,
                                                    select: (snapshot) => (
                                                      snapshot.position,
                                                      snapshot.duration,
                                                      snapshot.buffered,
                                                    ),
                                                    builder: (context, snapshot) => ValueListenableBuilder<Duration?>(
                                                      valueListenable:
                                                          _swipeSeekPreview,
                                                      builder: (context, preview, _) => PlaybackTimelineBar(
                                                        key: ValueKey(
                                                          session
                                                              .sourceGeneration,
                                                        ),
                                                        playerBoundsKey:
                                                            _playerBoundsKey,
                                                        position:
                                                            preview ??
                                                            snapshot.position,
                                                        duration:
                                                            snapshot.duration,
                                                        buffered:
                                                            snapshot.buffered,
                                                        chapters:
                                                            session.chapters,
                                                        highEnergy:
                                                            session.highEnergy,
                                                        storyboard:
                                                            session.storyboard,
                                                        storyboardLoading: session
                                                            .storyboardLoading,
                                                        storyboardMessage: session
                                                            .storyboardMessage,
                                                        sourceGeneration: session
                                                            .sourceGeneration,
                                                        onPreviewRequest: () =>
                                                            unawaited(
                                                              session
                                                                  .ensureStoryboard(),
                                                            ),
                                                        onSeek: (position) async {
                                                          if (widget.active &&
                                                              _appActive &&
                                                              session.sourceGeneration ==
                                                                  sourceGeneration &&
                                                              !session
                                                                  .isResolving &&
                                                              session.media !=
                                                                  null &&
                                                              session.error ==
                                                                  null) {
                                                            await session.seek(
                                                              position,
                                                            );
                                                          }
                                                        },
                                                        onMenuChanged:
                                                            _onControlsMenuChanged,
                                                      ),
                                                    ),
                                                  ),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                      ),
                                                  child: _ControlBar(
                                                    layout: layout,
                                                    composerKey: _composerKey,
                                                    composeExpanded:
                                                        _composeExpanded,
                                                    onToggleComposer: () =>
                                                        setState(
                                                          () => _composeExpanded =
                                                              !_composeExpanded,
                                                        ),
                                                    session: session,
                                                    settings: settings,
                                                    snapshot: snapshot,
                                                    pageCommands: widget
                                                        .pageCommands
                                                        .value,
                                                    onToggleComments:
                                                        widget.onToggleComments,
                                                    danmakuComposerBuilder: widget
                                                        .danmakuComposerBuilder,
                                                    onFullScreen:
                                                        _toggleFullScreen,
                                                    fullScreen:
                                                        widget.fullScreen,
                                                    onFocus:
                                                        _focusNode.requestFocus,
                                                    onSettings: _openSettings,
                                                    onMenuChanged:
                                                        _onControlsMenuChanged,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _BottomPlayerSlot { controls, subtitle, subtitleMessage }

// Progress, subtitle layout and control fades change independently of video.
// Keep their paint invalidations inside this layer even when a cue changes size.
class _BottomPlayerLayers extends StatelessWidget {
  const _BottomPlayerLayers({
    required this.controlsVisible,
    required this.subtitleBottomPadding,
    required this.children,
  });

  final bool controlsVisible;
  final double subtitleBottomPadding;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomMultiChildLayout(
      delegate: _BottomPlayerLayout(
        controlsVisible: controlsVisible,
        subtitleBottomPadding: subtitleBottomPadding,
      ),
      children: children,
    ),
  );
}

class _BottomPlayerLayout extends MultiChildLayoutDelegate {
  _BottomPlayerLayout({
    required this.controlsVisible,
    required this.subtitleBottomPadding,
  });

  final bool controlsVisible;
  final double subtitleBottomPadding;

  @override
  void performLayout(Size size) {
    var controlsHeight = 0.0;
    if (hasChild(_BottomPlayerSlot.controls)) {
      controlsHeight = layoutChild(
        _BottomPlayerSlot.controls,
        BoxConstraints.tightFor(width: size.width),
      ).height;
      positionChild(
        _BottomPlayerSlot.controls,
        Offset(0, size.height - controlsHeight),
      );
    }
    // The setting measures from the player edge. Lift only when needed to
    // clear the actual bar, including wrapped time and the expanded editor.
    final bottom = controlsVisible && controlsHeight + 8 > subtitleBottomPadding
        ? controlsHeight + 8
        : subtitleBottomPadding;
    for (final slot in [
      _BottomPlayerSlot.subtitle,
      _BottomPlayerSlot.subtitleMessage,
    ]) {
      if (!hasChild(slot)) continue;
      final childSize = layoutChild(
        slot,
        BoxConstraints.tightFor(width: (size.width - 40).clamp(0, size.width)),
      );
      positionChild(
        slot,
        Offset(
          20,
          (size.height - bottom - childSize.height).clamp(0, size.height),
        ),
      );
    }
  }

  @override
  bool shouldRelayout(_BottomPlayerLayout oldDelegate) =>
      controlsVisible != oldDelegate.controlsVisible ||
      subtitleBottomPadding != oldDelegate.subtitleBottomPadding;
}

// Keep the subtree alive until fade-out finishes, while immediately releasing
// input and semantics. Reversing a fade reuses the same controls and composer.
class _FadingPlayerControls extends StatefulWidget {
  const _FadingPlayerControls({
    required this.visible,
    required this.onHoverChanged,
    required this.child,
  });

  final bool visible;
  final ValueChanged<bool> onHoverChanged;
  final Widget child;

  @override
  State<_FadingPlayerControls> createState() => _FadingPlayerControlsState();
}

class _FadingPlayerControlsState extends State<_FadingPlayerControls>
    with SingleTickerProviderStateMixin {
  late bool _renderChild = widget.visible;
  bool _hovered = false;
  late final _opacity = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: widget.visible ? 1 : 0,
  )..addStatusListener(_onOpacityStatus);
  late final _curve = CurvedAnimation(
    parent: _opacity,
    curve: Curves.easeInOut,
  );

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    _hovered = hovered;
    widget.onHoverChanged(hovered);
  }

  void _onOpacityStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed &&
        mounted &&
        !widget.visible &&
        _renderChild) {
      setState(() => _renderChild = false);
    }
  }

  @override
  void didUpdateWidget(covariant _FadingPlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible) return;
    if (widget.visible) {
      _renderChild = true;
      _opacity.forward();
    } else {
      _setHovered(false);
      _opacity.reverse();
      // A reveal can be cancelled before its first animation frame.
      if (_opacity.isDismissed) _renderChild = false;
    }
  }

  @override
  void dispose() {
    // MouseRegion does not send an exit when a hovered control is removed.
    _setHovered(false);
    _curve.dispose();
    _opacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !widget.visible,
    child: ExcludeFocus(
      excluding: !widget.visible,
      child: ExcludeSemantics(
        excluding: !widget.visible,
        child: FadeTransition(
          opacity: _curve,
          child: _renderChild
              ? MouseRegion(
                  onEnter: (_) => _setHovered(true),
                  onExit: (_) => _setHovered(false),
                  child: widget.child,
                )
              : const SizedBox.shrink(),
        ),
      ),
    ),
  );
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.layout,
    required this.composerKey,
    required this.composeExpanded,
    required this.onToggleComposer,
    required this.session,
    required this.settings,
    required this.snapshot,
    required this.onToggleComments,
    required this.onFullScreen,
    required this.fullScreen,
    required this.onFocus,
    required this.onSettings,
    required this.onMenuChanged,
    this.danmakuComposerBuilder,
    this.pageCommands,
  });

  final PlaybackSession session;
  final AppSettings settings;
  final PlaybackSnapshot snapshot;
  final PlaybackPageCommands? pageCommands;
  final VoidCallback onToggleComments;
  final VoidCallback onFullScreen;
  final bool fullScreen;
  final VoidCallback onFocus;
  final Future<void> Function(int) onSettings;
  final ValueChanged<bool> onMenuChanged;
  final WidgetBuilder? danmakuComposerBuilder;
  final _ControlsLayout layout;
  final GlobalKey composerKey;
  final bool composeExpanded;
  final VoidCallback onToggleComposer;

  @override
  Widget build(BuildContext context) {
    final play = _PlayButton(
      session: session,
      snapshot: snapshot,
      onFocus: onFocus,
      shortcuts: settings.shortcuts,
    );
    final time = PlaybackSnapshotBuilder(
      snapshots: session.snapshots,
      select: (snapshot) =>
          (snapshot.position.inSeconds, snapshot.duration.inSeconds),
      builder: (context, snapshot) => Text(
        session.isLive
            ? '直播中'
            : '${_time(snapshot.position)} / ${_time(snapshot.duration)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white70, fontSize: 11),
      ),
    );
    final fullscreenButton = IconButton(
      tooltip: shortcutHint(
        settings.shortcuts,
        fullScreen ? ShortcutAction.exitFullscreen : ShortcutAction.fullscreen,
        fullScreen ? '退出全屏' : '全屏',
      ),
      onPressed: onFullScreen,
      icon: Icon(
        fullScreen ? Icons.fullscreen_exit : BiliIcons.fullscreen,
        size: 18,
      ),
    );
    final media = session.media;
    final danmakuButton = IconButton(
      tooltip: settings.danmakuEnabled ? '关闭弹幕' : '开启弹幕',
      onPressed: onToggleComments,
      icon: Icon(
        BiliIcons.danmaku,
        size: 20,
        color: settings.danmakuEnabled
            ? const Color(0xffff9ab8)
            : Colors.white54,
      ),
    );
    final listenButton = IconButton(
      tooltip: '听视频',
      onPressed: () => unawaited(session.setAudioOnly(true)),
      icon: const Icon(Icons.headphones_rounded, size: 20),
    );
    final subtitleButton = PopupMenuButton<int>(
      tooltip: '字幕',
      initialValue: session.selectedSubtitle,
      onOpened: () => onMenuChanged(true),
      onCanceled: () => onMenuChanged(false),
      onSelected: (track) {
        onMenuChanged(false);
        unawaited(session.selectSubtitle(track));
      },
      icon: const Icon(Icons.closed_caption_outlined, size: 20),
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: -1,
          checked: session.selectedSubtitle == -1,
          child: const Text('关闭字幕'),
        ),
        for (var i = 0; i < session.subtitleTracks.length; i++)
          CheckedPopupMenuItem(
            value: i,
            checked: session.selectedSubtitle == i,
            child: Text(_subtitleLabel(session.subtitleTracks[i])),
          ),
      ],
    );
    final volumeButton = PopupMenuButton<void>(
      tooltip: '音量',
      icon: Icon(
        snapshot.volume <= 0
            ? Icons.volume_off_outlined
            : Icons.volume_up_outlined,
        size: 20,
      ),
      itemBuilder: (_) => [_VolumeSliderEntry(session: session)],
      onOpened: () => onMenuChanged(true),
      onCanceled: () => onMenuChanged(false),
      onSelected: (_) => onMenuChanged(false),
    );
    Widget slot(Widget child, [double width = _ControlsLayout.buttonWidth]) =>
        SizedBox(width: width, height: 40, child: child);
    final composerBuilder = danmakuComposerBuilder;
    final composer = composerBuilder == null
        ? null
        : KeyedSubtree(
            key: composerKey,
            child: Builder(builder: composerBuilder),
          );
    if (layout.compact && !fullScreen) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Keep an existing draft across width changes without editor focus.
          if (composer != null) ExcludeFocus(child: Offstage(child: composer)),
          Row(
            key: const ValueKey('small-window-control-row'),
            children: [
              slot(play),
              const Spacer(),
              if (session.subtitleTracks.isNotEmpty) slot(subtitleButton),
              if (session.canListen) slot(listenButton),
              slot(danmakuButton),
              slot(_moreOptions(context)),
              slot(fullscreenButton),
            ],
          ),
        ],
      );
    }
    final secondary = <Widget>[
      if (session.canListen) slot(listenButton),
      slot(
        IconButton(
          tooltip: '弹幕配置',
          icon: const Icon(Icons.tune, size: 20),
          onPressed: () => onSettings(1),
        ),
      ),
      slot(
        IconButton(
          tooltip: '播放配置',
          icon: const Icon(BiliIcons.settings, size: 20),
          onPressed: () => onSettings(0),
        ),
      ),
      if (!session.isLive)
        slot(
          IconButton(
            tooltip: '字幕样式',
            icon: const Icon(Icons.text_fields, size: 20),
            onPressed: () => onSettings(2),
          ),
        ),
      slot(danmakuButton),
      if (media != null && session.isLive)
        slot(
          LiveStreamMenuButton(
            session: session,
            media: media,
            onMenuChanged: onMenuChanged,
          ),
          layout.qualityWidth,
        ),
      if (media != null && !session.isLive && media.qualities.length > 1)
        slot(
          PopupMenuButton<int>(
            tooltip: '清晰度',
            initialValue: media.quality,
            onOpened: () => onMenuChanged(true),
            onCanceled: () => onMenuChanged(false),
            onSelected: (quality) {
              onMenuChanged(false);
              unawaited(session.changeQuality(quality));
            },
            itemBuilder: (_) => [
              for (final quality in media.qualities)
                PopupMenuItem(
                  value: quality,
                  child: Text(
                    media.qualityLabels[quality] ?? _quality(quality),
                  ),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(
                  media.qualityLabels[media.quality] ?? _quality(media.quality),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
              ),
            ),
          ),
          layout.qualityWidth,
        ),
      if (!session.isLive)
        slot(
          PopupMenuButton<double>(
            tooltip: '播放速度',
            initialValue: snapshot.rate,
            onOpened: () => onMenuChanged(true),
            onCanceled: () => onMenuChanged(false),
            onSelected: (rate) {
              onMenuChanged(false);
              unawaited(session.setRate(rate));
            },
            itemBuilder: (_) => [
              for (final rate in PlaybackRates.values)
                PopupMenuItem(value: rate, child: Text('${rate}x')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(
                  '${snapshot.rate}x',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
              ),
            ),
          ),
          layout.rateWidth,
        ),
      if (session.subtitleTracks.isNotEmpty) slot(subtitleButton),
      if (session.voiceTracks.isNotEmpty)
        slot(
          PopupMenuButton<String>(
            tooltip: '语音翻译',
            initialValue: session.selectedVoice.key,
            onOpened: () => onMenuChanged(true),
            onCanceled: () => onMenuChanged(false),
            onSelected: (key) {
              onMenuChanged(false);
              final voice = _voices
                  .where((voice) => voice.key == key)
                  .firstOrNull;
              if (voice != null) unawaited(session.changeVoice(voice));
            },
            icon: const Icon(Icons.record_voice_over_outlined, size: 20),
            itemBuilder: (_) => [
              for (final voice in _voices)
                CheckedPopupMenuItem(
                  value: voice.key,
                  checked: voice.key == session.selectedVoice.key,
                  child: Text(_voiceLabel(voice)),
                ),
            ],
          ),
        ),
      slot(volumeButton),
    ];
    final showPlayInBar = !session.isLive || session.error != null;
    final showNext = layout.inputs.hasNextButton;
    // Keep transport controls at the bottom left even when the editor is open.
    // On the narrowest layouts, give the time its own line instead of clipping
    // it or shrinking the buttons' hit targets.
    final compactButtonCount =
        4 +
        (composer != null ? 1 : 0) +
        (showPlayInBar ? 1 : 0) +
        (showNext ? 1 : 0);
    final timeAboveRow =
        layout.compact &&
        layout.inputs.width <
            compactButtonCount * _ControlsLayout.buttonWidth + layout.timeWidth;
    final row = Row(
      key: ValueKey(
        layout.compact ? 'compact-control-row' : 'standard-control-row',
      ),
      children: layout.compact
          ? [
              if (showPlayInBar) slot(play),
              if (showNext)
                slot(_NextButton(session: session, commands: pageCommands)),
              if (timeAboveRow) const Spacer() else Expanded(child: time),
              slot(danmakuButton),
              if (composer != null)
                slot(
                  IconButton(
                    tooltip: composeExpanded ? '收起弹幕输入' : '发送弹幕',
                    onPressed: onToggleComposer,
                    icon: Icon(
                      composeExpanded
                          ? Icons.keyboard_hide
                          : Icons.edit_outlined,
                      size: 20,
                    ),
                  ),
                ),
              slot(_moreOptions(context)),
              slot(volumeButton),
              slot(fullscreenButton),
            ]
          : [
              slot(play),
              if (showNext)
                slot(_NextButton(session: session, commands: pageCommands)),
              SizedBox(width: layout.timeWidth, child: time),
              const SizedBox(width: 12),
              if (composer != null)
                Expanded(
                  child: Align(
                    alignment: Alignment.center,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: layout.composerMinWidth,
                        maxWidth: 420 < layout.composerMinWidth
                            ? layout.composerMinWidth
                            : 420,
                      ),
                      child: composer,
                    ),
                  ),
                )
              else
                const Spacer(),
              ...secondary,
              slot(fullscreenButton),
            ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (layout.compact && composer != null)
          ExcludeFocus(
            excluding: !composeExpanded,
            child: Offstage(
              offstage: !composeExpanded,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: composer,
              ),
            ),
          ),
        if (timeAboveRow) Align(alignment: Alignment.centerLeft, child: time),
        row,
      ],
    );
  }

  Widget _moreOptions(BuildContext context) => PopupMenuButton<VoidCallback>(
    tooltip: '更多播放选项',
    icon: const Icon(Icons.more_horiz, size: 20),
    onOpened: () => onMenuChanged(true),
    onCanceled: () => onMenuChanged(false),
    onSelected: (action) {
      onMenuChanged(false);
      action();
    },
    itemBuilder: (_) => [
      if (session.canListen)
        PopupMenuItem(
          value: () => unawaited(session.setAudioOnly(true)),
          child: const Row(
            children: [
              Icon(Icons.headphones_rounded, size: 20),
              SizedBox(width: 12),
              Text('听视频'),
            ],
          ),
        ),
      if ((session.detail?.parts.length ?? 0) > 1)
        if (pageCommands case final commands?)
          PopupMenuItem(
            value: commands.previousPart,
            child: const Text('上一分 P'),
          ),
      for (final (tab, title) in const [
        (0, '播放配置'),
        (1, '弹幕配置'),
        (2, '字幕样式'),
        (3, '空降助手'),
      ])
        if (!(session.isLive && (tab == 1 || tab == 2 || tab == 3)) &&
            !(session.contentTarget != null && tab == 3))
          PopupMenuItem(
            value: () => unawaited(onSettings(tab)),
            child: Text(title),
          ),
      if (session.media case final media?) ...[
        if (session.isLive)
          PopupMenuItem(
            value: () => unawaited(
              showLiveStreamPicker(
                context,
                session: session,
                media: media,
                onMenuChanged: onMenuChanged,
              ),
            ),
            child: const Text('直播流与线路'),
          ),
        if (session.isLive || media.qualities.length > 1)
          const PopupMenuDivider(),
        if (session.isLive || media.qualities.length > 1)
          for (final quality in media.qualities)
            CheckedPopupMenuItem(
              checked:
                  quality == media.quality &&
                  (!session.isLive || session.requestedQuality != 0),
              value: () {
                if (session.media == media) {
                  unawaited(session.changeQuality(quality));
                }
              },
              child: Text(
                '清晰度 ${media.qualityLabels[quality] ?? _quality(quality)}',
              ),
            ),
        if (session.isLive) ...[
          CheckedPopupMenuItem(
            checked: session.requestedQuality == 0,
            value: () {
              if (session.media == media) unawaited(session.changeQuality(0));
            },
            child: const Text('清晰度 自动'),
          ),
          const PopupMenuDivider(),
          for (var line = 0; line < media.video.urls.length; line++)
            CheckedPopupMenuItem(
              checked: line == session.liveLine,
              value: () {
                if (session.media == media) {
                  unawaited(session.changeLiveLine(line));
                }
              },
              child: Text('直播线路 ${liveLineLabel(line)}'),
            ),
        ],
      ],
      if (!session.isLive) const PopupMenuDivider(),
      for (final rate in session.isLive ? <double>[] : PlaybackRates.values)
        CheckedPopupMenuItem(
          checked: rate == snapshot.rate,
          value: () => unawaited(session.setRate(rate)),
          child: Text('播放速度 ${rate}x'),
        ),
      if (session.subtitleTracks.isNotEmpty) ...[
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
          value: () => unawaited(session.selectSubtitle(-1)),
          checked: session.selectedSubtitle == -1,
          child: const Text('关闭字幕'),
        ),
        for (var i = 0; i < session.subtitleTracks.length; i++)
          CheckedPopupMenuItem(
            value: () => unawaited(session.selectSubtitle(i)),
            checked: session.selectedSubtitle == i,
            child: Text(_subtitleLabel(session.subtitleTracks[i])),
          ),
      ],
      if (session.voiceTracks.isNotEmpty) ...[
        const PopupMenuDivider(),
        for (final voice in _voices)
          CheckedPopupMenuItem(
            value: () => unawaited(session.changeVoice(voice)),
            checked: voice.key == session.selectedVoice.key,
            child: Text('语音 ${_voiceLabel(voice)}'),
          ),
      ],
    ],
  );

  List<PlaybackVoice> get _voices => [
    const PlaybackVoice.original(),
    ...session.voiceTracks,
  ];
}

String _subtitleLabel(SubtitleTrack track) {
  final label = track.label.isNotEmpty ? track.label : track.languageCode;
  return track.type == 1
      ? '$label · ${track.aiType == 1 ? 'AI 翻译' : 'AI'}'
      : label;
}

String _voiceLabel(PlaybackVoice voice) =>
    voice.productionType == 2 ? '${voice.label} · AI 翻译' : voice.label;

class _VolumeSliderEntry extends PopupMenuEntry<void> {
  const _VolumeSliderEntry({required this.session});

  final PlaybackSession session;

  @override
  double get height => 88;

  @override
  bool represents(void value) => false;

  @override
  State<_VolumeSliderEntry> createState() => _VolumeSliderEntryState();
}

class _VolumeSliderEntryState extends State<_VolumeSliderEntry> {
  double? _draft;
  int _dragRevision = 0;

  @override
  Widget build(BuildContext context) => PlaybackSnapshotBuilder(
    snapshots: widget.session.snapshots,
    select: (snapshot) => snapshot.volume,
    builder: (context, snapshot) {
      final volume = (_draft ?? snapshot.volume).clamp(0.0, 100.0);
      return SizedBox(
        width: 216,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('音量 ${volume.round()}%'),
            ),
            Semantics(
              label: '音量',
              child: Slider(
                key: const ValueKey('player-volume-slider'),
                value: volume,
                max: 100,
                semanticFormatterCallback: (value) => '${value.round()}%',
                onChangeStart: (_) => _dragRevision++,
                onChanged: (value) {
                  setState(() => _draft = value);
                  unawaited(widget.session.setVolume(value));
                },
                onChangeEnd: (value) async {
                  final revision = _dragRevision;
                  await widget.session.setVolume(value);
                  if (mounted && revision == _dragRevision) {
                    setState(() => _draft = null);
                  }
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

typedef _ControlsLayoutInputs = ({
  double width,
  String timeLabel,
  String? rateLabel,
  String? qualityLabel,
  bool hasComposer,
  bool hasSubtitles,
  bool hasVoices,
  bool hasListen,
  bool hasNextButton,
  bool isLive,
  TextStyle textStyle,
  TextDirection textDirection,
  TextScaler textScaler,
});

// Match the actual labels and text scale so the editor shrinks before switching
// layouts, including long videos and optional quality/subtitle controls.
class _ControlsLayout {
  _ControlsLayout(this.inputs) {
    double textWidth(String text, double size) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: inputs.textStyle.copyWith(fontSize: size),
        ),
        textDirection: inputs.textDirection,
        textScaler: inputs.textScaler,
      )..layout();
      final result = painter.width.ceilToDouble() + 2;
      painter.dispose();
      return result;
    }

    timeWidth = textWidth(inputs.timeLabel, 11);
    rateWidth = switch (inputs.rateLabel) {
      final label? => textWidth(label, 12) + 16,
      null => 0,
    };
    qualityWidth = switch (inputs.qualityLabel) {
      final label? => textWidth(label, 12) + 16,
      null => 0,
    };
    composerMinWidth = 200 * inputs.textScaler.scale(12) / 12;
    // Count only rendered buttons; subtitle style is absent from live playback.
    compact =
        inputs.width <
        buttonWidth *
                (6 +
                    (inputs.isLive ? 0 : 1) +
                    (inputs.hasNextButton ? 1 : 0) +
                    (inputs.hasSubtitles ? 1 : 0) +
                    (inputs.hasVoices ? 1 : 0) +
                    (inputs.hasListen ? 1 : 0)) +
            timeWidth +
            rateWidth +
            qualityWidth +
            12 +
            (inputs.hasComposer ? composerMinWidth : 0);
  }
  final _ControlsLayoutInputs inputs;
  static const buttonWidth = 40.0;
  late final double timeWidth, rateWidth, qualityWidth, composerMinWidth;
  late final bool compact;
}

class _NextButton extends StatelessWidget {
  const _NextButton({required this.session, required this.commands});
  final PlaybackSession session;
  final PlaybackPageCommands? commands;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('player-next-episode'),
    tooltip: '下一集',
    style: IconButton.styleFrom(
      foregroundColor: Colors.white,
      disabledForegroundColor: Colors.white38,
    ),
    onPressed: commands?.hasNext == true && !session.isResolving
        ? commands?.nextPart
        : null,
    icon: const Icon(Icons.skip_next, size: 20),
  );
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.session,
    required this.snapshot,
    required this.onFocus,
    required this.shortcuts,
    this.prominent = false,
  });
  final PlaybackSession session;
  final PlaybackSnapshot snapshot;
  final VoidCallback onFocus;
  final bool prominent;
  final ShortcutSettings shortcuts;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: session.error != null
        ? '重新加载'
        : snapshot.desiredPlaying
        ? shortcutHint(shortcuts, ShortcutAction.playPause, '暂停')
        : shortcutHint(shortcuts, ShortcutAction.playPause, '播放'),
    style: prominent
        ? IconButton.styleFrom(
            backgroundColor: Colors.black38,
            minimumSize: const Size(56, 56),
          )
        : null,
    onPressed: () {
      onFocus();
      unawaited(
        session.error != null ? session.retry() : session.togglePlaying(),
      );
    },
    icon: Icon(
      session.error != null
          ? Icons.refresh
          : snapshot.desiredPlaying
          ? BiliIcons.pause
          : BiliIcons.play,
      color: Colors.white,
      size: prominent ? 32 : 20,
    ),
  );
}

String _time(Duration value) {
  final seconds = value.inSeconds.clamp(0, 999999);
  final minutes = seconds ~/ 60;
  return '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

String _quality(int? quality) => switch (quality) {
  120 => '4K',
  116 => '1080P60',
  112 => '1080P+',
  80 => '1080P',
  74 => '720P60',
  64 => '720P',
  32 => '480P',
  16 => '360P',
  null => '画质',
  _ => '$quality',
};

class _WindowFullScreenState {
  Object? owner;
  Future<void> commands = Future.value();
}

class _PlaybackViewers extends ConsumerWidget {
  const _PlaybackViewers({required this.request, required this.builder});
  final PlaybackViewerRequest? request;
  final Widget Function(String?) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = request;
    return builder(
      identity == null
          ? null
          : ref.watch(playbackViewersProvider(identity)).asData?.value,
    );
  }
}

PlaybackViewerRequest? _viewerRequest(PlaybackSession session) {
  final detail = session.detail;
  final part = session.part;
  if (session.contentTarget != null || detail == null || part == null) {
    return null;
  }
  return (
    video: detail.summary.id,
    cid: part.cid,
    epoch: session.sessionEpoch(),
  );
}

class _PlayerTopBar extends StatelessWidget {
  const _PlayerTopBar({
    required this.navigation,
    required this.fullScreen,
    required this.onExitFullScreen,
    required this.onNavigate,
    required this.viewers,
  });
  final ValueListenable<PlaybackNavigation?> navigation;
  final bool fullScreen;
  final VoidCallback onExitFullScreen;
  final ValueChanged<VoidCallback> onNavigate;
  final String? viewers;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.black54, Colors.transparent],
      ),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    constraints: const BoxConstraints(minHeight: 52),
    child: ValueListenableBuilder<PlaybackNavigation?>(
      valueListenable: navigation,
      builder: (context, actions, _) => Row(
        children: [
          if (actions?.showInPlayer ?? false) ...[
            IconButton(
              key: const ValueKey('player-back'),
              tooltip: '返回',
              color: Colors.white,
              onPressed: fullScreen
                  ? onExitFullScreen
                  : actions == null
                  ? null
                  : () => onNavigate(actions.onBack),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            IconButton(
              key: const ValueKey('player-home'),
              tooltip: '回到主页',
              color: Colors.white,
              onPressed: actions == null
                  ? null
                  : () => onNavigate(actions.onHome),
              icon: const Icon(Icons.home_outlined),
            ),
          ],
          if (viewers != null)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '$viewers 人正在看',
                  key: const ValueKey('player-online-viewers'),
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            )
          else
            const Spacer(),
        ],
      ),
    ),
  );
}
