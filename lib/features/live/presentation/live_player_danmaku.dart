import 'dart:async';

import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/workspace_activity.dart';
import '../../settings/domain/app_settings.dart';
import '../application/live_controller.dart';
import '../domain/live_chat_repository.dart';
import '../domain/live_room.dart';

/// Keeps the requested room ID's controller when the API resolves a short ID.
final class LiveDanmakuRoomScope extends InheritedWidget {
  const LiveDanmakuRoomScope({
    super.key,
    required this.requestedId,
    required super.child,
  });
  final RoomId requestedId;
  static RoomId? requestedIdOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<LiveDanmakuRoomScope>()
      ?.requestedId;
  @override
  bool updateShouldNotify(LiveDanmakuRoomScope oldWidget) =>
      requestedId != oldWidget.requestedId;
}

/// Subscribes only to newly received chat; HTTP history is never replayed.
final class LivePlayerDanmaku extends ConsumerStatefulWidget {
  const LivePlayerDanmaku({
    super.key,
    required this.roomId,
    required this.settings,
  });
  final RoomId roomId;
  final AppSettings settings;
  @override
  ConsumerState<LivePlayerDanmaku> createState() => _LivePlayerDanmakuState();
}

final class _LivePlayerDanmakuState extends ConsumerState<LivePlayerDanmaku>
    with WidgetsBindingObserver {
  final Stopwatch _clock = Stopwatch()..start();
  late final LiveDanmakuController _danmaku;
  StreamSubscription<List<LiveChatMessage>>? _messages;
  LiveController? _liveController;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = _isForeground(WidgetsBinding.instance.lifecycleState);
    _danmaku = LiveDanmakuController(monotonicNow: () => _clock.elapsed);
    _configure();
  }

  void _configure() => _danmaku.configure(
    area: widget.settings.danmakuArea,
    speed: widget.settings.danmakuSpeed,
    maxPerSecond: widget.settings.danmakuMaxPerSecond,
  );
  static bool _isForeground(AppLifecycleState? state) =>
      state != AppLifecycleState.hidden &&
      state != AppLifecycleState.paused &&
      state != AppLifecycleState.detached;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() => _foreground = _isForeground(state));
    if (!_foreground) _danmaku.setEnabled(false);
  }

  @override
  void didUpdateWidget(covariant LivePlayerDanmaku oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configure();
    if (oldWidget.roomId != widget.roomId) {
      _danmaku.clear();
      _liveController = null;
    }
  }

  void _receive(List<LiveChatMessage> batch) {
    final settings = widget.settings;
    _danmaku.add(
      batch
          .where(
            (message) =>
                !settings.danmakuBlockedWords.any(message.text.contains),
          )
          .map((message) {
            final mode = switch (message.mode) {
              4 => DanmakuMode.bottom,
              5 => DanmakuMode.top,
              _ => DanmakuMode.scroll,
            };
            return LiveDanmakuEvent(
              id: message.deduplicationKey,
              text: message.text,
              mode: mode,
              color: Color(message.color),
              fontSize: message.fontSize * settings.danmakuFontScale,
            );
          })
          .where(
            (event) => switch (event.mode) {
              DanmakuMode.scroll => settings.danmakuScrollEnabled,
              DanmakuMode.top => settings.danmakuTopEnabled,
              DanmakuMode.bottom => settings.danmakuBottomEnabled,
            },
          ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_messages?.cancel());
    _danmaku.dispose();
    _clock.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final providerId =
        LiveDanmakuRoomScope.requestedIdOf(context) ?? widget.roomId;
    ref.listen(liveControllerProvider(providerId), (previous, next) {
      if ((previous?.room != null && next.room == null) ||
          (next.loading && !(previous?.loading ?? false)) ||
          next.connectionPhase == LiveConnectionPhase.closed) {
        _danmaku.clear();
      }
    });
    final controller = ref.watch(liveControllerProvider(providerId).notifier);
    if (!identical(controller, _liveController)) {
      unawaited(_messages?.cancel());
      _liveController = controller;
      _messages = controller.receivedDanmaku.listen(_receive);
    }
    _danmaku.setEnabled(
      _foreground &&
          WorkspaceActivity.isActive(context) &&
          widget.settings.danmakuEnabled,
    );
    return LiveDanmakuOverlay(controller: _danmaku);
  }
}
