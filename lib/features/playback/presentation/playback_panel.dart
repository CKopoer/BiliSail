import 'dart:async';

import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:bili_player/bili_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/window_service.dart';
import '../../../core/presentation/workspace_activity.dart';
import '../../../shared/ui/playback_page_commands.dart';
import '../../../domain/video.dart';
import '../../../domain/playback_rates.dart';
import '../../settings/domain/app_settings.dart';
import '../../../core/input/shortcut_dispatcher.dart';
import '../../../core/presentation/input_scope.dart';
import '../application/playback_shortcut_controller.dart';
import '../application/playback_session.dart';
import '../domain/content_playback.dart';
import 'player_settings_dialog.dart';
import 'playback_timeline_bar.dart';
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
  late final PlaybackShortcutController _shortcuts;
  late final ValueNotifier<AppSettings> _settings;
  // Inline and fullscreen views are recreated, but share the page's intent.
  final _controlsVisible = ValueNotifier(true);
  bool _fullScreen = false;
  bool _active = false;
  bool _surfaceReady = false;
  Object? _activityRequest;
  Route<void>? _fullScreenRoute;
  NavigatorState? _fullScreenNavigator;
  Object? _fullScreenRequest;
  FullScreenOrientation? _fullScreenOrientation;
  static final _windowStates = Expando<_WindowFullScreenState>();
  _WindowFullScreenState get _windowState =>
      _windowStates[widget.window] ??= _WindowFullScreenState();

  @override
  void initState() {
    super.initState();
    _settings = ValueNotifier(widget.settings);
    _session = ref.read(playbackSessionProvider)..attach(this);
    _session.snapshots.addListener(_updateFullScreenOrientation);
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
    final active = WorkspaceActivity.isActive(context);
    if (_active == active) return;
    _active = active;
    _surfaceReady = false;
    final activityRequest = Object();
    _activityRequest = activityRequest;
    if (!active) {
      _shortcuts.cancel();
      _dismissFullScreen();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !identical(_activityRequest, activityRequest)) return;
      if (active) {
        _configure();
        unawaited(
          _session.activate(
            this,
            widget.detail,
            widget.part,
            target: widget.target,
            title: widget.title,
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
          ),
        );
      }
      _configure();
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
    if (state != AppLifecycleState.resumed) _shortcuts.cancel();
    // A video can keep playing behind another workspace tab. System lifecycle
    // still applies to its owner even when the page has no visible surface.
    if (_session.ownsPlayback(this) &&
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
    _dismissFullScreen();
    _shortcuts.dispose();
    _session.detach(this);
    _settings.dispose();
    _controlsVisible.dispose();
    super.dispose();
  }

  void _dismissFullScreen() {
    _shortcuts.cancel();
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

  void _updateFullScreenOrientation() {
    final request = _fullScreenRequest;
    if (request == null ||
        !_fullScreen ||
        !_active ||
        widget.window.hasDesktopWindow) {
      return;
    }
    final orientation = _videoOrientation;
    if (orientation == null || orientation == _fullScreenOrientation) return;
    _fullScreenOrientation = orientation;
    // The same owner/command queue also orders delayed dimensions against exit.
    unawaited(_setWindowFullScreen(request, true));
  }

  Future<void> _enterFullScreen() async {
    if (_fullScreen || !_active) return;
    _shortcuts.cancel();
    final request = Object();
    final providerContainer = ProviderScope.containerOf(context);
    _fullScreenOrientation = widget.window.hasDesktopWindow
        ? null
        : _videoOrientation ??
              (MediaQuery.orientationOf(context) == Orientation.landscape
                  ? FullScreenOrientation.landscape
                  : FullScreenOrientation.portrait);
    _fullScreenRequest = request;
    setState(() => _fullScreen = true);
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
      final navigator = Navigator.of(context, rootNavigator: true);
      final route = RawDialogRoute<void>(
        requestFocus: false,
        barrierDismissible: false,
        barrierLabel: '全屏播放器',
        transitionDuration: Duration.zero,
        pageBuilder: (dialogContext, _, _) => UncontrolledProviderScope(
          container: providerContainer,
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
              pageCommands: PlaybackPageCommands.maybeOf(context),
              fullScreen: true,
              onFullScreen: () {
                if (identical(_fullScreenRoute, ModalRoute.of(dialogContext))) {
                  navigator.pop();
                }
              },
            ),
          ),
        ),
      );
      InputScope.of<Object>(context)?.routes.presentation(route);
      _fullScreenRoute = route;
      _fullScreenNavigator = navigator;
      await navigator.push(route);
    } finally {
      if (identical(_fullScreenRequest, request)) _fullScreenRequest = null;
      _fullScreenRoute = null;
      _fullScreenNavigator = null;
      await WidgetsBinding.instance.endOfFrame;
      await _setWindowFullScreen(request, false);
      _fullScreenOrientation = null;
      if (mounted) setState(() => _fullScreen = false);
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
            pageCommands: PlaybackPageCommands.maybeOf(context),
            fullScreen: false,
            active: _active && _surfaceReady,
          ),
  );
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
    this.pageCommands,
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
  final PlaybackPageCommands? pageCommands;
  final bool active;
  final WidgetBuilder? danmakuComposerBuilder;
  final WidgetBuilder? danmakuOverlayBuilder;
  @override
  State<_PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<_PlayerView> with WidgetsBindingObserver {
  final FocusNode _focusNode = FocusNode(debugLabel: 'video player');
  final GlobalKey _playerBoundsKey = GlobalKey();
  bool _exitingFullScreen = false;
  bool _composeExpanded = false;
  final GlobalKey _composerKey = GlobalKey();
  Timer? _controlsHideTimer;
  final Set<int> _pressedPointers = {};
  bool _mouseInside = false;
  bool _appActive = true;
  bool _controlEditorFocused = false;
  int _openControlsMenus = 0;
  late int _sourceGeneration;
  late bool _hasError;
  late PlayerControlsMode _controlsMode;

  bool get _dynamicControls => _controlsMode == PlayerControlsMode.dynamic;

  @override
  void initState() {
    super.initState();
    _controlsMode = widget.settings.value.playerControlsMode;
    _sourceGeneration = widget.session.sourceGeneration;
    _hasError = widget.session.error != null;
    widget.settings.addListener(_onSettingsChanged);
    widget.session.addListener(_onSessionChanged);
    FocusManager.instance.addListener(_onControlsFocusChanged);
    WidgetsBinding.instance.addObserver(this);
    _scheduleControlsHide();
  }

  void _onSessionChanged() {
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
    if (!_dynamicControls) _scheduleControlsHide();
  }

  void _onControlsMenuChanged(bool open) {
    if (!mounted) return;
    _openControlsMenus += open ? 1 : -1;
    if (!_dynamicControls) _scheduleControlsHide();
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
      _mouseInside = false;
      _pressedPointers.clear();
      _scheduleControlsHide();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
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
    FocusManager.instance.removeListener(_onControlsFocusChanged);
    widget.shortcuts.endTouchHold();
    _focusNode.dispose();
    super.dispose();
  }

  void _scheduleControlsHide() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = null;
    if (!mounted ||
        !widget.active ||
        !_appActive ||
        !widget.controlsVisible.value ||
        _pressedPointers.isNotEmpty ||
        (!_dynamicControls &&
            (_controlEditorFocused || _openControlsMenus > 0 || _hasError))) {
      return;
    }
    _controlsHideTimer = Timer(Duration(seconds: _dynamicControls ? 1 : 5), () {
      _controlsHideTimer = null;
      if (mounted && widget.active && _appActive) {
        widget.controlsVisible.value = false;
      }
    });
  }

  void _showDynamicControls() {
    if (!_dynamicControls || !widget.active || !_appActive) return;
    widget.controlsVisible.value = true;
    _scheduleControlsHide();
  }

  void _onMouseEnter(PointerEnterEvent event) {
    _mouseInside = true;
    _showDynamicControls();
  }

  void _onMouseExit(PointerExitEvent event) {
    _mouseInside = false;
    if (!_dynamicControls || !widget.active) return;
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
    required Widget child,
    bool retainDynamicPress = false,
  }) => _FadingPlayerControls(
    visible: visible,
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
      onHover: (_) => _showDynamicControls(),
      onExit: _onMouseExit,
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: (event) {
          if (event.kind == PointerDeviceKind.mouse && _mouseInside) {
            _showDynamicControls();
          }
        },
        onPointerUp: _onPointerEnd,
        onPointerCancel: _onPointerEnd,
        child: _buildPlayer(context),
      ),
    );
  }

  Widget _buildPlayer(BuildContext context) {
    final session = widget.session;
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
              ]),
              builder: (context, _) => ValueListenableBuilder<PlaybackSnapshot>(
                valueListenable: session.snapshots,
                builder: (context, snapshot, _) {
                  final settings = widget.settings.value;
                  final durationMs = snapshot.duration.inMilliseconds
                      .toDouble();
                  final positionMs = snapshot.position.inMilliseconds
                      .toDouble();
                  final cue = session.subtitleCues
                      .where(
                        (cue) =>
                            snapshot.position >= cue.start &&
                            snapshot.position < cue.end,
                      )
                      .firstOrNull;
                  final controls =
                      widget.controlsVisible.value || session.error != null;
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final layout = _ControlsLayout(
                        context,
                        session,
                        snapshot,
                        constraints.maxWidth - 20,
                        hasComposer: widget.danmakuComposerBuilder != null,
                      );
                      return ColoredBox(
                        key: _playerBoundsKey,
                        color: Colors.black,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
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
                              child: RawGestureDetector(
                                // The recognizer's deadline is fixed at creation.
                                key: ValueKey(settings.shortcuts.holdDelayMs),
                                behavior: HitTestBehavior.translucent,
                                excludeFromSemantics: true,
                                gestures: {
                                  if (!session.isLive)
                                    LongPressGestureRecognizer:
                                        GestureRecognizerFactoryWithHandlers<
                                          LongPressGestureRecognizer
                                        >(
                                          () => LongPressGestureRecognizer(
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
                                            recognizer.onLongPressDown = (_) =>
                                                widget.shortcuts
                                                    .prepareTouchHold();
                                            recognizer.onLongPressStart = (_) =>
                                                widget.shortcuts
                                                    .beginTouchHold();
                                            recognizer.onLongPressEnd = (_) =>
                                                widget.shortcuts.endTouchHold();
                                            recognizer.onLongPressCancel =
                                                widget.shortcuts.endTouchHold;
                                          },
                                        ),
                                },
                                child: GestureDetector(
                                  key: const ValueKey(
                                    'player-surface-tap-target',
                                  ),
                                  behavior: HitTestBehavior.translucent,
                                  onTap: _onSurfaceTap,
                                  onDoubleTap: () {
                                    if (!widget.active) return;
                                    _focusNode.requestFocus();
                                    _toggleFullScreen();
                                  },
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
                                      child: Text(
                                        widget.shortcuts.isHoldingRate
                                            ? '长按倍速 ${snapshot.rate}x'
                                            : '播放速度 ${snapshot.rate}x',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (layout.compact &&
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
                                  child: Row(
                                    key: const ValueKey(
                                      'compact-playback-actions',
                                    ),
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (widget.pageCommands != null &&
                                          (session.detail?.parts.length ?? 0) >
                                              1)
                                        IconButton(
                                          tooltip: '上一分 P',
                                          onPressed:
                                              widget.pageCommands?.previousPart,
                                          icon: const Icon(
                                            Icons.skip_previous,
                                            color: Colors.white,
                                          ),
                                        ),
                                      _PlayButton(
                                        session: session,
                                        snapshot: snapshot,
                                        onFocus: _focusNode.requestFocus,
                                        prominent: true,
                                        shortcuts:
                                            widget.settings.value.shortcuts,
                                      ),
                                      if (widget.pageCommands != null &&
                                          (session.detail?.parts.length ?? 0) >
                                              1)
                                        IconButton(
                                          tooltip: '下一分 P',
                                          onPressed:
                                              widget.pageCommands?.nextPart,
                                          icon: const Icon(
                                            Icons.skip_next,
                                            color: Colors.white,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            if (cue != null)
                              Positioned(
                                left: 20,
                                right: 20,
                                bottom:
                                    (controls ? 104 : 0) +
                                    settings.subtitleBottomPadding,
                                child: IgnorePointer(
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      color: Colors.black.withValues(
                                        alpha:
                                            settings.subtitleBackgroundOpacity,
                                      ),
                                      child: Text(
                                        cue.text,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize:
                                              22 * settings.subtitleFontScale,
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
                              ),
                            if (session.error == null)
                              Positioned(
                                key: const ValueKey(
                                  'player-control-title-layer',
                                ),
                                left: 0,
                                right: 0,
                                top: 0,
                                child: _controlsVisibility(
                                  visible: controls,
                                  child: Container(
                                    color: Colors.black54,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.play_circle_outline,
                                          color: Colors.white70,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            session.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        if (settings.sponsorBlockMode !=
                                                SponsorBlockMode.disabled &&
                                            (session.sponsorLoading ||
                                                session.sponsorMessage != null))
                                          Flexible(
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                left: 10,
                                              ),
                                              child: Text(
                                                session.sponsorLoading
                                                    ? '正在查询空降片段…'
                                                    : (session.sponsorMessage ??
                                                          ''),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ),
                                          ),
                                        if ((session.detail?.parts.length ??
                                                0) >
                                            1)
                                          Text(
                                            'P${session.part?.page ?? 1}',
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            if (session.currentSponsor case final segment?)
                              Positioned(
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
                              ),
                            if (session.error == null &&
                                (session.isResolving ||
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
                                durationMs > 0)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    foregroundPainter: ChapterBoundaryPainter(
                                      chapters: session.chapters,
                                      duration: snapshot.duration,
                                      textDirection: Directionality.of(context),
                                    ),
                                    child: LinearProgressIndicator(
                                      key: const ValueKey(
                                        'player-collapsed-progress',
                                      ),
                                      minHeight: 2,
                                      borderRadius: BorderRadius.zero,
                                      value: (positionMs / durationMs).clamp(
                                        0,
                                        1,
                                      ),
                                      color: const Color(0xffdf6589),
                                      backgroundColor: Colors.white24,
                                    ),
                                  ),
                                ),
                              ),
                            if (widget.active)
                              Positioned(
                                key: const ValueKey('player-control-bar-layer'),
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: _controlsVisibility(
                                  visible: controls,
                                  retainDynamicPress: true,
                                  child: Theme(
                                    data: ThemeData.dark(useMaterial3: true)
                                        .copyWith(
                                          colorScheme: ColorScheme.fromSeed(
                                            seedColor: const Color(0xffdf6589),
                                            brightness: Brightness.dark,
                                          ),
                                        ),
                                    child: Container(
                                      key: const ValueKey('player-controls'),
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
                                          if (session.auxiliaryMessage != null)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                  ),
                                              child: Text(
                                                session.auxiliaryMessage!,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ),
                                          if (!session.isLive)
                                            PlaybackTimelineBar(
                                              key: ValueKey(
                                                session.sourceGeneration,
                                              ),
                                              playerBoundsKey: _playerBoundsKey,
                                              position: snapshot.position,
                                              duration: snapshot.duration,
                                              buffered: snapshot.buffered,
                                              chapters: session.chapters,
                                              storyboard: session.storyboard,
                                              storyboardLoading:
                                                  session.storyboardLoading,
                                              storyboardMessage:
                                                  session.storyboardMessage,
                                              sourceGeneration:
                                                  session.sourceGeneration,
                                              onPreviewRequest: () => unawaited(
                                                session.ensureStoryboard(),
                                              ),
                                              onSeek: (position) => unawaited(
                                                session.seek(position),
                                              ),
                                            ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                            ),
                                            child: _ControlBar(
                                              layout: layout,
                                              composerKey: _composerKey,
                                              composeExpanded: _composeExpanded,
                                              onToggleComposer: () => setState(
                                                () => _composeExpanded =
                                                    !_composeExpanded,
                                              ),
                                              session: session,
                                              settings: settings,
                                              snapshot: snapshot,
                                              onToggleComments:
                                                  widget.onToggleComments,
                                              danmakuComposerBuilder:
                                                  widget.danmakuComposerBuilder,
                                              onFullScreen: _toggleFullScreen,
                                              fullScreen: widget.fullScreen,
                                              onFocus: _focusNode.requestFocus,
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

// Keep the subtree alive until fade-out finishes, while immediately releasing
// input and semantics. Reversing a fade reuses the same controls and composer.
class _FadingPlayerControls extends StatefulWidget {
  const _FadingPlayerControls({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  State<_FadingPlayerControls> createState() => _FadingPlayerControlsState();
}

class _FadingPlayerControlsState extends State<_FadingPlayerControls>
    with SingleTickerProviderStateMixin {
  late bool _renderChild = widget.visible;
  late final _opacity = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: widget.visible ? 1 : 0,
  )..addStatusListener(_onOpacityStatus);
  late final _curve = CurvedAnimation(
    parent: _opacity,
    curve: Curves.easeInOut,
  );

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
      _opacity.reverse();
      // A reveal can be cancelled before its first animation frame.
      if (_opacity.isDismissed) _renderChild = false;
    }
  }

  @override
  void dispose() {
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
          child: _renderChild ? widget.child : const SizedBox.shrink(),
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
  });

  final PlaybackSession session;
  final AppSettings settings;
  final PlaybackSnapshot snapshot;
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
    final time = Text(
      session.isLive
          ? '直播中'
          : '${_time(snapshot.position)} / ${_time(snapshot.duration)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Colors.white70, fontSize: 11),
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
        size: 20,
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
    final secondary = <Widget>[
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
      if (session.contentTarget == null)
        slot(
          IconButton(
            tooltip: session.sponsorLoading
                ? '正在查询空降片段'
                : (session.sponsorMessage ?? '空降助手'),
            icon: Icon(
              Icons.airplanemode_active,
              size: 20,
              color: settings.sponsorBlockMode == SponsorBlockMode.disabled
                  ? Colors.white54
                  : const Color(0xffff9ab8),
            ),
            onPressed: () => onSettings(3),
          ),
        ),
      slot(danmakuButton),
      if (media != null && media.qualities.length > 1)
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
      if (session.subtitleTracks.isNotEmpty)
        slot(
          PopupMenuButton<int>(
            tooltip: '字幕',
            onOpened: () => onMenuChanged(true),
            onCanceled: () => onMenuChanged(false),
            onSelected: (track) {
              onMenuChanged(false);
              unawaited(session.selectSubtitle(track));
            },
            icon: const Icon(Icons.closed_caption_outlined, size: 20),
            itemBuilder: (_) => [
              const PopupMenuItem(value: -1, child: Text('关闭字幕')),
              for (var i = 0; i < session.subtitleTracks.length; i++)
                PopupMenuItem(
                  value: i,
                  child: Text(session.subtitleTracks[i].label),
                ),
            ],
          ),
        ),
      slot(volumeButton),
    ];
    final composerBuilder = danmakuComposerBuilder;
    final composer = composerBuilder == null
        ? null
        : KeyedSubtree(
            key: composerKey,
            child: Builder(builder: composerBuilder),
          );
    final row = Row(
      key: ValueKey(
        layout.compact ? 'compact-control-row' : 'standard-control-row',
      ),
      children: layout.compact
          ? [
              if (session.error != null) slot(play),
              Expanded(child: time),
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
              slot(_moreOptions()),
              slot(volumeButton),
              slot(fullscreenButton),
            ]
          : [
              slot(play),
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
        row,
      ],
    );
  }

  Widget _moreOptions() => PopupMenuButton<VoidCallback>(
    tooltip: '更多播放选项',
    icon: const Icon(Icons.more_horiz, size: 20),
    onOpened: () => onMenuChanged(true),
    onCanceled: () => onMenuChanged(false),
    onSelected: (action) {
      onMenuChanged(false);
      action();
    },
    itemBuilder: (_) => [
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
        if (media.qualities.length > 1) const PopupMenuDivider(),
        if (media.qualities.length > 1)
          for (final quality in media.qualities)
            CheckedPopupMenuItem(
              checked: quality == media.quality,
              value: () => unawaited(session.changeQuality(quality)),
              child: Text(
                '清晰度 ${media.qualityLabels[quality] ?? _quality(quality)}',
              ),
            ),
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
        PopupMenuItem(
          value: () => unawaited(session.selectSubtitle(-1)),
          child: const Text('关闭字幕'),
        ),
        for (var i = 0; i < session.subtitleTracks.length; i++)
          PopupMenuItem(
            value: () => unawaited(session.selectSubtitle(i)),
            child: Text(session.subtitleTracks[i].label),
          ),
      ],
    ],
  );
}

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
  Widget build(BuildContext context) =>
      ValueListenableBuilder<PlaybackSnapshot>(
        valueListenable: widget.session.snapshots,
        builder: (context, snapshot, _) {
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

// Match the actual labels and text scale so the editor shrinks before switching
// layouts, including long videos and optional quality/subtitle controls.
class _ControlsLayout {
  _ControlsLayout(
    BuildContext context,
    PlaybackSession session,
    PlaybackSnapshot snapshot,
    double width, {
    required bool hasComposer,
  }) {
    double textWidth(String text, double size) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: DefaultTextStyle.of(context).style.copyWith(fontSize: size),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final result = painter.width.ceilToDouble() + 2;
      painter.dispose();
      return result;
    }

    timeWidth = textWidth(
      session.isLive
          ? '直播中'
          : '${_time(snapshot.duration)} / ${_time(snapshot.duration)}',
      11,
    );
    rateWidth = session.isLive ? 0 : textWidth('${snapshot.rate}x', 12) + 16;
    final media = session.media;
    qualityWidth = media != null && media.qualities.length > 1
        ? textWidth(
                media.qualityLabels[media.quality] ?? _quality(media.quality),
                12,
              ) +
              16
        : 0;
    composerMinWidth = 200 * MediaQuery.textScalerOf(context).scale(12) / 12;
    compact =
        width <
        buttonWidth * (8 + (session.subtitleTracks.isNotEmpty ? 1 : 0)) +
            timeWidth +
            rateWidth +
            qualityWidth +
            12 +
            (hasComposer ? composerMinWidth : 0);
  }
  static const buttonWidth = 40.0;
  late final double timeWidth, rateWidth, qualityWidth, composerMinWidth;
  late final bool compact;
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
