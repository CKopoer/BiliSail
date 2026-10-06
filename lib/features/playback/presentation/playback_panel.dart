import 'dart:async';

import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:bili_player/bili_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/window_service.dart';
import '../../../core/presentation/workspace_activity.dart';
import '../../../core/presentation/playback_page_commands.dart';
import '../../../domain/video.dart';
import '../../../domain/playback_rates.dart';
import '../../settings/domain/app_settings.dart';
import '../../settings/domain/shortcut_settings.dart';
import '../../../core/presentation/keyboard_shortcuts.dart';
import '../application/playback_session.dart';
import '../domain/content_playback.dart';
import 'player_settings_dialog.dart';
import 'playback_timeline_bar.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../shared/ui/bili_icons.dart';

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
  static final _windowStates = Expando<_WindowFullScreenState>();
  _WindowFullScreenState get _windowState =>
      _windowStates[widget.window] ??= _WindowFullScreenState();

  @override
  void initState() {
    super.initState();
    _settings = ValueNotifier(widget.settings);
    _session = ref.read(playbackSessionProvider)..attach(this);
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
    if (!active) _dismissFullScreen();
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
      if (!mounted || !_active) return;
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
    if (!identical(widget.settings, oldWidget.settings)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _settings.value = widget.settings;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
    _dismissFullScreen();
    _session.detach(this);
    _settings.dispose();
    _controlsVisible.dispose();
    super.dispose();
  }

  void _dismissFullScreen() {
    _fullScreenRequest = null;
    final route = _fullScreenRoute;
    final navigator = _fullScreenNavigator;
    if (route != null && navigator != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive && navigator.mounted) navigator.removeRoute(route);
      });
    }
  }

  Future<void> _setWindowFullScreen(Object request, bool enabled) {
    final operation = _windowState.commands.then((_) async {
      if (enabled) {
        if (!identical(_fullScreenRequest, request) || !mounted || !_active) {
          return;
        }
        _windowState.owner = request;
        await widget.window.setFullScreen(true);
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

  Future<void> _enterFullScreen() async {
    if (_fullScreen || !_active) return;
    final request = Object();
    final providerContainer = ProviderScope.containerOf(context);
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
      _fullScreenRoute = route;
      _fullScreenNavigator = navigator;
      await navigator.push(route);
    } finally {
      _fullScreenRoute = null;
      _fullScreenNavigator = null;
      await WidgetsBinding.instance.endOfFrame;
      await _setWindowFullScreen(request, false);
      if (mounted) setState(() => _fullScreen = false);
      if (identical(_fullScreenRequest, request)) _fullScreenRequest = null;
    }
  }

  @override
  Widget build(BuildContext context) => _fullScreen
      ? const ColoredBox(color: Colors.black)
      : _PlayerView(
          session: _session,
          settings: _settings,
          controlsVisible: _controlsVisible,
          onToggleComments: widget.onToggleComments,
          danmakuComposerBuilder: widget.danmakuComposerBuilder,
          danmakuOverlayBuilder: widget.danmakuOverlayBuilder,
          onFullScreen: _enterFullScreen,
          pageCommands: PlaybackPageCommands.maybeOf(context),
          fullScreen: false,
          active: _active && _surfaceReady,
        );
}

class _PlayerView extends StatefulWidget {
  const _PlayerView({
    required this.session,
    required this.settings,
    required this.controlsVisible,
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
  bool _settingsOpen = false;
  bool _composeExpanded = false;
  final GlobalKey _composerKey = GlobalKey();
  Timer? _holdTimer;
  Timer? _rateFeedbackTimer;
  bool _showRateFeedback = false;
  int _volumeNoticeRequest = 0;
  int? _pendingVolumeGeneration;
  double? _pendingShortcutVolume;
  double? _savedRate;
  double _savedVolume = 100;
  LogicalKeyboardKey? _heldKey;
  FocusNode? _heldFocus;
  String? _heldCid;
  int? _heldGeneration;

  void _releaseHold({bool restore = true}) {
    _holdTimer?.cancel();
    _holdTimer = null;
    final rate = _savedRate;
    _savedRate = null;
    _heldKey = null;
    _heldFocus = null;
    if (restore &&
        rate != null &&
        widget.session.part?.cid == _heldCid &&
        widget.session.snapshots.value.generation == _heldGeneration) {
      unawaited(
        widget.session.endTemporaryRate(expectedGeneration: _heldGeneration),
      );
    }
    _heldCid = null;
    _heldGeneration = null;
  }

  void _focusChanged() {
    if (_heldKey != null &&
        !identical(FocusManager.instance.primaryFocus, _heldFocus)) {
      _releaseHold();
    }
  }

  void _focusWhenActive() {
    // Workspace pages keep their State when hidden. Reclaim keyboard focus
    // when their surface returns, without taking it from an editor or dialog.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active && !shortcutsBlocked(context)) {
        _focusNode.requestFocus();
      }
    });
  }

  void _sourceChanged() {
    if (_heldKey != null &&
        (widget.session.part?.cid != _heldCid ||
            widget.session.snapshots.value.generation != _heldGeneration)) {
      _releaseHold(restore: false);
    }
  }

  Future<void> _setShortcutRate(double rate) async {
    final generation = widget.session.snapshots.value.generation;
    await widget.session.setRate(rate);
    if (!mounted ||
        !widget.active ||
        widget.session.error != null ||
        widget.session.snapshots.value.generation != generation) {
      return;
    }
    _rateFeedbackTimer?.cancel();
    setState(() => _showRateFeedback = true);
    _rateFeedbackTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showRateFeedback = false);
    });
  }

  Future<void> _setShortcutVolume(double volume) async {
    final request = ++_volumeNoticeRequest;
    final generation = widget.session.snapshots.value.generation;
    _pendingVolumeGeneration = generation;
    _pendingShortcutVolume = volume;
    try {
      await widget.session.setVolume(volume);
    } finally {
      if (request == _volumeNoticeRequest) {
        _pendingShortcutVolume = null;
      }
    }
    if (!mounted ||
        !widget.active ||
        request != _volumeNoticeRequest ||
        widget.session.error != null ||
        widget.session.snapshots.value.generation != generation) {
      return;
    }
    showAppNotice(
      context,
      '音量 ${widget.session.snapshots.value.volume.round()}%',
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _releaseHold();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Playback keys belong to the active page, including its sidebar. Handle
    // them before focused lists/sliders consume arrow keys for navigation.
    FocusManager.instance.addEarlyKeyEventHandler(_key);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_mouseShortcut);
    FocusManager.instance.addListener(_focusChanged);
    widget.session.addListener(_sourceChanged);
    widget.settings.addListener(_onSettingsChanged);
    if (widget.active) _focusWhenActive();
  }

  @override
  void didUpdateWidget(covariant _PlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) {
      _releaseHold();
      _volumeNoticeRequest++;
      _pendingShortcutVolume = null;
      _rateFeedbackTimer?.cancel();
      _showRateFeedback = false;
    }
    if (widget.active && !oldWidget.active) _focusWhenActive();
    if (oldWidget.settings != widget.settings) {
      oldWidget.settings.removeListener(_onSettingsChanged);
      widget.settings.addListener(_onSettingsChanged);
    }
  }

  void _onSettingsChanged() {
    _releaseHold();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _releaseHold();
    _volumeNoticeRequest++;
    _pendingShortcutVolume = null;
    _rateFeedbackTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_sourceChanged);
    FocusManager.instance.removeEarlyKeyEventHandler(_key);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_mouseShortcut);
    FocusManager.instance.removeListener(_focusChanged);
    widget.settings.removeListener(_onSettingsChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleControls() {
    if (!widget.active) return;
    _focusNode.requestFocus();
    widget.controlsVisible.value = !widget.controlsVisible.value;
  }

  Future<void> _openSettings(int tab) async {
    _releaseHold();
    _settingsOpen = true;
    try {
      await showPlayerSettings(context, tab: tab);
    } finally {
      _settingsOpen = false;
    }
  }

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

  KeyEventResult _key(KeyEvent event) {
    if (event is KeyUpEvent && event.logicalKey == _heldKey) {
      final shortPress = _savedRate == null;
      _releaseHold();
      if (shortPress && widget.active && !shortcutsBlocked(context)) {
        unawaited(
          widget.session.seek(
            widget.session.snapshots.value.position +
                Duration(seconds: widget.settings.value.shortcuts.seekSeconds),
          ),
        );
      }
      return KeyEventResult.handled;
    }
    if (!widget.active || _settingsOpen || shortcutsBlocked(context)) {
      _releaseHold();
      return KeyEventResult.ignored;
    }
    // Focused controls keep their own Enter/Space activation behavior.
    if (!_focusNode.hasPrimaryFocus &&
        [
          LogicalKeyboardKey.space,
          LogicalKeyboardKey.enter,
        ].contains(event.logicalKey)) {
      return KeyEventResult.ignored;
    }
    final action = widget.settings.value.shortcuts.actionFor(
      shortcutKey(event),
    );
    if (action == null ||
        action == ShortcutAction.newTab ||
        action == ShortcutAction.closeTab) {
      return KeyEventResult.ignored;
    }
    if (event is KeyUpEvent) return KeyEventResult.handled;
    if (event is KeyRepeatEvent &&
        action != ShortcutAction.volumeUp &&
        action != ShortcutAction.volumeDown &&
        action != ShortcutAction.seekBack) {
      // Do not let repeats fall through to focus traversal or retrigger toggles.
      return KeyEventResult.handled;
    }
    return _performShortcut(action, heldKey: event.logicalKey)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  void _mouseShortcut(PointerEvent event) =>
      dispatchMouseShortcut(event, (key) {
        if (!widget.active || _settingsOpen || shortcutsBlocked(context)) {
          return false;
        }
        final action = widget.settings.value.shortcuts.actionFor(key);
        return action != null && _performShortcut(action);
      });

  bool _performShortcut(ShortcutAction action, {LogicalKeyboardKey? heldKey}) {
    final session = widget.session;
    final snapshot = session.snapshots.value;
    // Native volume commands are serialized; repeats can arrive before the
    // snapshot reflects an earlier 5% step.
    final shortcutVolume = _pendingVolumeGeneration == snapshot.generation
        ? _pendingShortcutVolume ?? snapshot.volume
        : snapshot.volume;
    if (session.isLive &&
        const {
          ShortcutAction.seekBack,
          ShortcutAction.seekForward,
          ShortcutAction.seekLarge,
          ShortcutAction.slower,
          ShortcutAction.faster,
          ShortcutAction.toggleRate,
          ShortcutAction.subtitles,
          ShortcutAction.danmaku,
        }.contains(action)) {
      return false;
    }
    switch (action) {
      case ShortcutAction.playPause:
        unawaited(
          session.error != null ? session.retry() : session.togglePlaying(),
        );
      case ShortcutAction.fullscreen:
        _toggleFullScreen();
      case ShortcutAction.exitFullscreen:
        if (!widget.fullScreen) return false;
        _toggleFullScreen();
      case ShortcutAction.seekBack:
        unawaited(
          session.seek(
            snapshot.position -
                Duration(seconds: widget.settings.value.shortcuts.seekSeconds),
          ),
        );
      case ShortcutAction.seekForward:
        if (heldKey == null) {
          unawaited(
            session.seek(
              snapshot.position +
                  Duration(
                    seconds: widget.settings.value.shortcuts.seekSeconds,
                  ),
            ),
          );
          return true;
        }
        _heldKey = heldKey;
        _heldFocus = FocusManager.instance.primaryFocus;
        _heldCid = session.part?.cid;
        _heldGeneration = session.snapshots.value.generation;
        _holdTimer?.cancel();
        _holdTimer = Timer(
          Duration(milliseconds: widget.settings.value.shortcuts.holdDelayMs),
          () {
            if (!mounted ||
                !widget.active ||
                shortcutsBlocked(context) ||
                !identical(FocusManager.instance.primaryFocus, _heldFocus) ||
                session.part?.cid != _heldCid ||
                session.snapshots.value.generation != _heldGeneration) {
              _releaseHold();
              return;
            }
            _savedRate = session.snapshots.value.rate;
            unawaited(
              session.beginTemporaryRate(
                widget.settings.value.shortcuts.holdRate,
              ),
            );
          },
        );
      case ShortcutAction.seekLarge:
        unawaited(
          session.seek(snapshot.position + const Duration(seconds: 90)),
        );
      case ShortcutAction.volumeUp:
        unawaited(_setShortcutVolume((shortcutVolume + 5).clamp(0, 100)));
      case ShortcutAction.volumeDown:
        unawaited(_setShortcutVolume((shortcutVolume - 5).clamp(0, 100)));
      case ShortcutAction.mute:
        if (shortcutVolume > 0) _savedVolume = shortcutVolume;
        unawaited(_setShortcutVolume(shortcutVolume > 0 ? 0 : _savedVolume));
      case ShortcutAction.danmaku:
        widget.onToggleComments();
      case ShortcutAction.subtitles:
        unawaited(
          session.selectSubtitle(
            session.selectedSubtitle < 0 && session.subtitleTracks.isNotEmpty
                ? 0
                : -1,
          ),
        );
      case ShortcutAction.slower:
        unawaited(_setShortcutRate(PlaybackRates.slower(snapshot.rate)));
      case ShortcutAction.faster:
        unawaited(_setShortcutRate(PlaybackRates.faster(snapshot.rate)));
      case ShortcutAction.toggleRate:
        unawaited(_setShortcutRate(snapshot.rate == 1 ? 2 : 1));
      case ShortcutAction.previousPart:
        if (widget.pageCommands == null) return false;
        widget.pageCommands?.previousPart();
      case ShortcutAction.nextPart:
        if (widget.pageCommands == null) return false;
        widget.pageCommands?.nextPart();
      case ShortcutAction.fullWindow:
        if (widget.fullScreen) _toggleFullScreen();
        if (widget.pageCommands == null) return false;
        widget.pageCommands?.toggleInfo();
      case ShortcutAction.refresh:
        unawaited(session.retry());
      default:
        return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const ColoredBox(color: Colors.black);
    final session = widget.session;
    return Focus(
      focusNode: _focusNode,
      includeSemantics: false,
      child: ListenableBuilder(
        listenable: _focusNode,
        builder: (context, _) => Semantics(
          container: true,
          explicitChildNodes: true,
          label: '视频播放器',
          focusable: _focusNode.canRequestFocus,
          onTap: _toggleControls,
          focused: _focusNode.hasPrimaryFocus,
          onFocus: _focusNode.requestFocus,
          child: ListenableBuilder(
            listenable: Listenable.merge([session, widget.controlsVisible]),
            builder: (context, _) => ValueListenableBuilder<PlaybackSnapshot>(
              valueListenable: session.snapshots,
              builder: (context, snapshot, _) {
                final settings = widget.settings.value;
                final durationMs = snapshot.duration.inMilliseconds.toDouble();
                final positionMs = snapshot.position.inMilliseconds.toDouble();
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
                            child: GestureDetector(
                              key: const ValueKey('player-surface-tap-target'),
                              behavior: HitTestBehavior.translucent,
                              onTap: _toggleControls,
                              onDoubleTap: () {
                                if (!widget.active) return;
                                _focusNode.requestFocus();
                                _toggleFullScreen();
                              },
                            ),
                          ),
                          if (_showRateFeedback)
                            Positioned(
                              key: const ValueKey('player-rate-hud'),
                              left: 16,
                              top: controls ? 52 : 16,
                              child: IgnorePointer(
                                child: Semantics(
                                  liveRegion: true,
                                  child: Container(
                                    key: const ValueKey('player-rate-feedback'),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: .7),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '播放速度 ${snapshot.rate}x',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (controls &&
                              layout.compact &&
                              !_composeExpanded &&
                              session.error == null &&
                              !session.isResolving &&
                              snapshot.phase != PlaybackPhase.opening)
                            Center(
                              child: Row(
                                key: const ValueKey('compact-playback-actions'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (widget.pageCommands != null &&
                                      (session.detail?.parts.length ?? 0) > 1)
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
                                  ),
                                  if (widget.pageCommands != null &&
                                      (session.detail?.parts.length ?? 0) > 1)
                                    IconButton(
                                      tooltip: '下一分 P',
                                      onPressed: widget.pageCommands?.nextPart,
                                      icon: const Icon(
                                        Icons.skip_next,
                                        color: Colors.white,
                                      ),
                                    ),
                                ],
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
                                      alpha: settings.subtitleBackgroundOpacity,
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
                          if (controls && session.error == null)
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 0,
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
                                    if ((session.detail?.parts.length ?? 0) > 1)
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
                                icon: const Icon(Icons.fast_forward, size: 18),
                                label: Text(
                                  '跳过${sponsorCategoryLabel(segment.category)}',
                                ),
                              ),
                            ),
                          if (session.error == null &&
                              (session.isResolving ||
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
                          if (controls && widget.active)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
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
                                          padding: const EdgeInsets.symmetric(
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
                                          onSeek: (position) =>
                                              unawaited(session.seek(position)),
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
                                        ),
                                      ),
                                    ],
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
    );
  }
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
      tooltip: fullScreen ? '退出全屏（Esc）' : '全屏（F）',
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
            onSelected: session.changeQuality,
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
            onSelected: session.setRate,
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
            onSelected: session.selectSubtitle,
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
    onSelected: (action) => action(),
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
    this.prominent = false,
  });
  final PlaybackSession session;
  final PlaybackSnapshot snapshot;
  final VoidCallback onFocus;
  final bool prominent;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: session.error != null
        ? '重新加载'
        : snapshot.desiredPlaying
        ? '暂停（空格）'
        : '播放（空格）',
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
