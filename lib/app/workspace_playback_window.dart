import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/input/input_stroke.dart';
import '../core/input/shortcut_dispatcher.dart';
import '../core/platform/playback_window_chrome.dart';
import '../core/platform/window_service.dart';
import '../core/presentation/app_input_host.dart';
import '../core/presentation/input_scope.dart';
import '../features/settings/domain/shortcut_settings.dart';
import '../shared/ui/app_notice.dart';
import '../shared/ui/smooth_scroll_behavior.dart';
import 'shortcut_coordinator.dart';

/// A local Navigator and input host keep dialogs, fullscreen and shortcuts in
/// the playback view while repositories and the workspace remain shared.
class WorkspacePlaybackWindow extends StatefulWidget {
  const WorkspacePlaybackWindow({
    super.key,
    required this.child,
    required this.shortcuts,
    required this.onBack,
    required this.onClose,
    required this.onActivateBrowser,
    this.onHome,
    required this.theme,
  });

  final Widget child;
  final ShortcutSettings shortcuts;
  final VoidCallback onBack;
  final VoidCallback onClose;
  final VoidCallback onActivateBrowser;
  final VoidCallback? onHome;
  final ThemeData theme;

  @override
  State<WorkspacePlaybackWindow> createState() =>
      _WorkspacePlaybackWindowState();
}

class _WorkspacePlaybackWindowState extends State<WorkspacePlaybackWindow> {
  final _input = ShortcutCoordinator();
  final _backOwner = Object();
  WindowService? _window;
  Timer? _captionTimer;
  Timer? _themeTimer;

  void _scheduleWindowTheme() {
    _themeTimer?.cancel();
    final window = _window;
    if (window == null || !window.hasCustomPlaybackTitleBar) return;
    // DWM may pump native messages; update outside the Flutter frame stack.
    _themeTimer = Timer(Duration.zero, () {
      _themeTimer = null;
      if (!mounted || !identical(_window, window)) return;
      unawaited(
        window
            .configurePlaybackTitleBar(
              brightness: widget.theme.brightness,
              backgroundColor: widget.theme.scaffoldBackgroundColor,
            )
            .catchError((Object error, StackTrace stack) {
              if (!mounted) return;
              FlutterError.reportError(
                FlutterErrorDetails(
                  exception: error,
                  stack: stack,
                  library: 'BiliSail playback window theme',
                ),
              );
            }),
      );
    });
  }

  @override
  void didUpdateWidget(WorkspacePlaybackWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.theme.brightness != widget.theme.brightness ||
        oldWidget.theme.scaffoldBackgroundColor !=
            widget.theme.scaffoldBackgroundColor) {
      _scheduleWindowTheme();
    }
  }

  void _nativeBack() {
    // Native caption input sits outside Navigator's modal barrier. Keep the
    // same isolation that the old in-content button received from that barrier.
    if (_input.routes.modal || _input.barriers != 0) return;
    _input.beforeNavigation();
    widget.onBack();
  }

  void _nativeHome() {
    if (_input.routes.modal || _input.barriers != 0) return;
    _input.beforeNavigation();
    (widget.onHome ?? widget.onActivateBrowser)();
  }

  void _unbindBack(WindowService window) {
    unawaited(
      window.unbindTitleBarBack(_backOwner).catchError((
        Object error,
        StackTrace stack,
      ) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'BiliSail playback caption cleanup',
          ),
        );
      }),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final window = WindowServiceScope.maybeOf(context);
    if (identical(window, _window)) return;
    _captionTimer?.cancel();
    final previous = _window;
    _window = window;
    if (window != null) window.onMiniPlayerClose = widget.onClose;
    _scheduleWindowTheme();
    if (previous != null) _unbindBack(previous);
    if (window == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_window, window)) return;
      _captionTimer = Timer(Duration.zero, () {
        _captionTimer = null;
        if (!mounted || !identical(_window, window)) return;
        unawaited(
          window
              .bindTitleBarBack(
                owner: _backOwner,
                onBack: _nativeBack,
                onHome: _nativeHome,
              )
              .catchError((Object error, StackTrace stack) {
                if (!mounted) return;
                FlutterError.reportError(
                  FlutterErrorDetails(
                    exception: error,
                    stack: stack,
                    library: 'BiliSail playback caption',
                  ),
                );
              }),
        );
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    });
  }

  @override
  void dispose() {
    _captionTimer?.cancel();
    _themeTimer?.cancel();
    final window = _window;
    if (window != null) _unbindBack(window);
    _input.dispose();
    super.dispose();
  }

  CommandOutcome _command(Object command, InputStroke stroke) {
    // Closing/activating another native window while a side button is held
    // can start a second Down in that view. Keep the frozen target until Up
    // so the handoff happens after release; Cancel/blur never executes it.
    if (stroke.device == InputDevice.mouse) {
      if (stroke.phase != InputPhase.up) return CommandOutcome.noOp;
    } else if (stroke.phase == InputPhase.up) {
      return CommandOutcome.noOp;
    }
    _input.beforeNavigation();
    switch (command) {
      case ShortcutAction.closeTab:
        // The workspace handles page-local detail before media history/close.
        widget.onBack();
      case ShortcutAction.nextTab || ShortcutAction.previousTab:
        widget.onActivateBrowser();
    }
    return CommandOutcome.completed;
  }

  @override
  Widget build(BuildContext context) {
    _input.configure(widget.shortcuts);
    final window = WindowServiceScope.maybeOf(context);
    return MaterialApp(
      title: '哔帆 · 播放',
      theme: widget.theme,
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      scrollBehavior: const SmoothScrollBehavior(),
      navigatorObservers: [_input.routes],
      builder: (context, child) => AppInputHost<Object>(
        dispatcher: _input,
        routes: _input.routes,
        onEditingChanged: window == null
            ? null
            : (active) => window.setTextInputActive(active),
        child: AppNoticeHost(
          child: CommandTargetScope<Object>(
            scope: CommandScope.workspace,
            commands: {
              for (final command in <Object>[
                ShortcutAction.closeTab,
                ShortcutAction.nextTab,
                ShortcutAction.previousTab,
              ])
                command: (stroke) => _command(command, stroke),
            },
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
      home: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              if (window != null && window.hasCustomPlaybackTitleBar)
                PlaybackWindowChrome(
                  window: window,
                  onBack: _nativeBack,
                  onHome: _nativeHome,
                  onClose: widget.onClose,
                ),
              Expanded(child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}
