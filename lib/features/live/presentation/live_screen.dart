import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/workspace_activity.dart';
import '../../../domain/user.dart';
import '../../../shared/ui/network_avatar.dart';
import '../../../shared/ui/playback_sidebar_toggle.dart';
import '../../../shared/ui/smooth_scroll_behavior.dart';
import '../../../shared/ui/state_view.dart';
import '../application/live_controller.dart';
import '../domain/live_chat_repository.dart';
import '../domain/live_room.dart';
import 'live_super_chat_card.dart';
import 'live_player_danmaku.dart';
import 'live_chat_bubble.dart';

typedef LivePlayerBuilder = Widget Function(
  BuildContext context,
  LiveRoom room,
);
typedef LiveComposerBuilder = Widget Function(
  BuildContext context,
  RoomId requestedId,
);

class LiveScreen extends ConsumerStatefulWidget {
  const LiveScreen({
    super.key,
    required this.roomId,
    required this.playerBuilder,
    this.onOpenUser,
    this.composerBuilder,
  });

  final String roomId;
  final LivePlayerBuilder playerBuilder;
  final LiveComposerBuilder? composerBuilder;
  final ValueChanged<UserId>? onOpenUser;

  @override
  ConsumerState<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends ConsumerState<LiveScreen>
    with WidgetsBindingObserver {
  // Keep the same player element when the sidebar is resized or hidden.
  final GlobalKey _playerKey = GlobalKey(debugLabel: 'live-player');
  final ScrollController _chatScrollController = ScrollController();
  final ScrollController _superChatScrollController = ScrollController();
  LiveController? _controller;
  bool? _lastActive;
  bool _infoVisible = true;
  int _tab = 0;
  String? _selectedSuperChatId;
  bool _followChat = true;
  bool _chatUserScrolling = false;
  bool _adjustingChatScroll = false;
  bool _chatFollowScheduled = false;

  bool get _foreground => !const {
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  }.contains(WidgetsBinding.instance.lifecycleState);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant LiveScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) {
      _tab = 0;
      _selectedSuperChatId = null;
      _followChat = true;
      _chatUserScrolling = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Closing a tab unmounts this view during the widget build. A retained
    // controller must stop after that build; disposed providers already cancel.
    final controller = _controller;
    Future<void>.microtask(() {
      if (controller?.isMounted ?? false) controller?.setActive(false);
    });
    _chatScrollController.dispose();
    _superChatScrollController.dispose();
    super.dispose();
  }

  void _jumpChatTo(double offset) {
    _chatUserScrolling = false;
    _adjustingChatScroll = true;
    try {
      _chatScrollController.jumpTo(offset);
    } finally {
      _adjustingChatScroll = false;
    }
  }

  void _scheduleChatFollow() {
    if (!_followChat ||
        _chatFollowScheduled ||
        _tab != 0 ||
        !_infoVisible ||
        _lastActive != true) {
      return;
    }
    _chatFollowScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chatFollowScheduled = false;
      if (!mounted ||
          !_followChat ||
          _tab != 0 ||
          !_infoVisible ||
          _lastActive != true ||
          !_chatScrollController.hasClients) {
        return;
      }
      final state = ref.read(liveControllerProvider(RoomId(widget.roomId)));
      if (state.superChats.any((item) => item.id == _selectedSuperChatId)) {
        return;
      }
      final position = _chatScrollController.position;
      if (position.hasContentDimensions &&
          position.pixels != position.maxScrollExtent) {
        _jumpChatTo(position.maxScrollExtent);
      }
    });
    // Metrics may arrive after layout. Request a frame for their correction too.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _onChatPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_chatScrollController.hasClients) {
      return;
    }
    final position = _chatScrollController.position;
    final delta = event.scrollDelta.dy;
    if ((delta < 0 && position.pixels > position.minScrollExtent) ||
        (delta > 0 && position.pixels < position.maxScrollExtent)) {
      _chatUserScrolling = true;
      // A smooth wheel can receive new messages before its first moving frame.
      if (delta < 0) _followChat = false;
    }
  }

  bool _onChatScroll(ScrollNotification notification) {
    if (notification.depth != 0 || _adjustingChatScroll) return false;
    if ((notification is ScrollStartNotification &&
            notification.dragDetails != null) ||
        (notification is UserScrollNotification &&
            notification.direction != ScrollDirection.idle)) {
      _chatUserScrolling = true;
    }
    if (_chatUserScrolling && notification is ScrollUpdateNotification) {
      _followChat = notification.metrics.extentAfter <= 1;
    }
    if (notification is ScrollEndNotification && _chatUserScrolling) {
      _chatUserScrolling = false;
      _scheduleChatFollow();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final id = RoomId(widget.roomId);
    if (!id.isValid) {
      return const StateView.empty(
        message: '直播间号无效',
        icon: Icons.live_tv_outlined,
      );
    }
    final state = ref.watch(liveControllerProvider(id));
    final controller = ref.read(liveControllerProvider(id).notifier);
    final active = WorkspaceActivity.isActive(context) && _foreground;
    if (_controller != controller || _lastActive != active) {
      final previous = _controller;
      _controller = controller;
      _lastActive = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _controller != controller) return;
        if (previous != null && previous != controller && previous.isMounted) {
          previous.setActive(false);
        }
        controller.setActive(active);
      });
    }

    final room = state.room;
    if (room == null) {
      if (state.roomMessage case final message?) {
        return StateView.error(message: message, onAction: controller.load);
      }
      return const StateView.loading(message: '正在加载直播间…');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final playerWidth = _infoVisible && wide
            ? math.max(0.0, constraints.maxWidth - 380)
            : constraints.maxWidth;
        final playerHeight = _infoVisible && !wide
            ? math.min(
                constraints.maxWidth * 9 / 16,
                constraints.maxHeight * 0.55,
              )
            : constraints.maxHeight;
        final compactPlayerHeight = math.min(
          constraints.maxWidth * 9 / 16,
          constraints.maxHeight * 0.55,
        );
        final infoHeight = wide
            ? constraints.maxHeight
            : math.max(0.0, constraints.maxHeight - compactPlayerHeight);
        return Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: playerWidth,
              height: playerHeight,
              child: _player(context, room),
            ),
            Positioned(
              left: wide ? constraints.maxWidth - 380 : 0,
              top: wide ? 0 : compactPlayerHeight,
              width: wide ? 380 : constraints.maxWidth,
              height: infoHeight,
              child: ExcludeFocus(
                excluding: !_infoVisible,
                child: Offstage(
                  offstage: !_infoVisible,
                  child: _sidebar(context, room, state, controller, infoHeight),
                ),
              ),
            ),
            Positioned(
              right: wide && _infoVisible ? 380 : 0,
              top: wide
                  ? math.max(
                      0.0,
                      playerHeight / 2 - PlaybackSidebarToggle.size.height / 2,
                    )
                  : 0,
              child: PlaybackSidebarToggle(
                tooltip: _infoVisible ? '收起直播信息' : '展开直播信息',
                icon: wide
                    ? (_infoVisible ? Icons.chevron_right : Icons.chevron_left)
                    : (_infoVisible ? Icons.expand_less : Icons.expand_more),
                onPressed: () => setState(() => _infoVisible = !_infoVisible),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _player(BuildContext context, LiveRoom room) => ColoredBox(
    key: _playerKey,
    color: Colors.black,
    child: room.isLive
        ? LiveDanmakuRoomScope(
            requestedId: RoomId(widget.roomId),
            child: Builder(
              builder: (context) => widget.playerBuilder(context, room),
            ),
          )
        : Center(
            child: Text(
              '主播尚未开播',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: Colors.white),
            ),
          ),
  );

  Widget _sidebar(
    BuildContext context,
    LiveRoom room,
    LiveState state,
    LiveController controller,
    double height,
  ) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: math.max(0, height * .4)),
            child: SingleChildScrollView(
              child: _roomInfo(context, room, state),
            ),
          ),
          const Divider(height: 1),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _tabButton('聊天', 0),
                      _tabButton('SC (${state.superChats.length})', 1),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: _tab == 0
                    ? (state.connectionPhase == LiveConnectionPhase.failed
                          ? '重新连接弹幕'
                          : '刷新消息')
                    : '刷新 SC',
                onPressed: _tab == 0
                    ? (state.connectionPhase == LiveConnectionPhase.failed
                          ? controller.retryRealtime
                          : state.chatLoading
                          ? null
                          : controller.refreshChat)
                    : (state.superChatLoading
                          ? null
                          : controller.refreshSuperChats),
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                _chat(context, state, controller),
                _superChats(context, state, controller),
              ],
            ),
          ),
          if (widget.composerBuilder case final builder?) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(10),
              child: builder(context, RoomId(widget.roomId)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _roomInfo(BuildContext context, LiveRoom room, LiveState state) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final anchorId = room.anchorId;
    final open =
        anchorId == null || !anchorId.isValid || widget.onOpenUser == null
        ? null
        : () => widget.onOpenUser?.call(anchorId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                key: const ValueKey('live-anchor-avatar'),
                onTap: open,
                borderRadius: BorderRadius.circular(24),
                child: NetworkAvatar(
                  url: room.anchorAvatarUrl,
                  name: room.anchorName,
                  radius: 18,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: InkWell(
                  key: const ValueKey('live-anchor-name'),
                  onTap: open,
                  child: Text(
                    room.anchorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: open == null ? null : colors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                fit: FlexFit.tight,
                child: DefaultTextStyle(
                  style:
                      theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ) ??
                      TextStyle(color: colors.onSurfaceVariant),
                  textAlign: TextAlign.right,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        state.viewerCountText == null
                            ? '在看人数暂无数据'
                            : '当前${state.viewerCountText}人在看',
                        key: const ValueKey('live-viewer-count'),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        state.watchedCountText == null
                            ? '看过人数暂无数据'
                            : '${state.watchedCountText}人看过',
                        key: const ValueKey('live-watched-count'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(room.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 7),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              Text(
                room.isLive ? '● 直播中' : '● 未开播',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: room.isLive ? colors.primary : colors.onSurfaceVariant,
                ),
              ),
              Text('房间号 ${room.id.value}', style: theme.textTheme.bodySmall),
              if (room.areaName.isNotEmpty)
                Text('分区 ${room.areaName}', style: theme.textTheme.bodySmall),
              if (room.popularity case final popularity?)
                Text(
                  '人气 ${_compactCount(popularity)}',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String label, int index) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: _tab == index,
      child: InkWell(
        key: ValueKey('live-tab-$index'),
        onTap: () => setState(() => _tab = index),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 11, 16, 9),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                width: 2,
                color: _tab == index
                    ? theme.colorScheme.primary
                    : Colors.transparent,
              ),
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: _tab == index
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _chat(
    BuildContext context,
    LiveState state,
    LiveController controller,
  ) {
    final theme = Theme.of(context);
    final selected = state.superChats
        .where((message) => message.id == _selectedSuperChatId)
        .firstOrNull;
    if (selected == null) _scheduleChatFollow();
    final bodyCount = state.messages.isEmpty ? 1 : state.messages.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  switch (state.connectionPhase) {
                    LiveConnectionPhase.connected => '实时弹幕已连接',
                    LiveConnectionPhase.fetching ||
                    LiveConnectionPhase.connecting ||
                    LiveConnectionPhase.authenticating => '正在连接实时弹幕…',
                    LiveConnectionPhase.reconnecting => '实时弹幕重连中…',
                    LiveConnectionPhase.failed => '实时弹幕已断开',
                    LiveConnectionPhase.offline => '主播尚未开播',
                    LiveConnectionPhase.closed => '实时弹幕已暂停',
                    LiveConnectionPhase.idle => '历史消息 · 定时刷新',
                  },
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (state.chatLoading || state.superChatLoading)
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
        if (state.superChats.isNotEmpty)
          SizedBox(
            height: 54,
            child: ScrollConfiguration(
              behavior: const SmoothScrollBehavior(horizontalMouseWheel: true)
                  .copyWith(scrollbars: false),
              child: Scrollbar(
                key: const ValueKey('live-sc-scrollbar'),
                controller: _superChatScrollController,
                thumbVisibility: true,
                interactive: true,
                thickness: 3,
                radius: const Radius.circular(2),
                scrollbarOrientation: ScrollbarOrientation.bottom,
                child: ListView.separated(
                  controller: _superChatScrollController,
                  primary: false,
                  padding: const EdgeInsets.fromLTRB(10, 3, 10, 10),
                  scrollDirection: Axis.horizontal,
                  itemCount: state.superChats.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 7),
                  itemBuilder: (context, index) =>
                      _superChatBubble(state.superChats[index]),
                ),
              ),
            ),
          ),
        if (state.superChatMessage case final message?)
          _errorBanner(context, message, controller.refreshSuperChats),
        if (state.connectionMessage case final message?)
          _errorBanner(context, message, controller.retryRealtime),
        if (state.chatMessage case final message?)
          if (state.messages.isNotEmpty)
            _errorBanner(context, message, controller.refreshChat),
        const Divider(height: 1),
        Expanded(
          child: Listener(
            onPointerSignal: _onChatPointerSignal,
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (notification) {
                if (notification.depth == 0) _scheduleChatFollow();
                return false;
              },
              child: NotificationListener<ScrollNotification>(
                onNotification: _onChatScroll,
                child: ListView.builder(
                  key: const ValueKey('live-chat-list'),
                  controller: _chatScrollController,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  itemCount: (selected == null ? 0 : 1) + bodyCount,
                  itemBuilder: (context, index) {
                    if (selected != null && index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _superChatCard(selected),
                      );
                    }
                    final bodyIndex = index - (selected == null ? 0 : 1);
                    if (state.messages.isEmpty) {
                      return switch (state.chatMessage) {
                        final String message => StateView.error(
                          message: message,
                          onAction: controller.refreshChat,
                        ),
                        null when state.chatLoading => const StateView.loading(
                          message: '正在读取最近消息…',
                        ),
                        null => const StateView.empty(
                          message: '暂无聊天消息',
                          icon: Icons.chat_bubble_outline,
                        ),
                      };
                    }
                    final message = state.messages[bodyIndex];
                    return LiveChatBubble(
                      message: message,
                      onOpenUser: widget.onOpenUser,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _superChats(
    BuildContext context,
    LiveState state,
    LiveController controller,
  ) {
    if (state.superChats.isEmpty) {
      if (state.superChatMessage case final message?) {
        return SingleChildScrollView(
          child: StateView.error(
            message: message,
            onAction: controller.refreshSuperChats,
          ),
        );
      }
      if (state.superChatLoading) {
        return const SingleChildScrollView(
          child: StateView.loading(message: '正在读取 SC…'),
        );
      }
      return const SingleChildScrollView(
        child: StateView.empty(message: '暂无 SC', icon: Icons.paid_outlined),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.superChatMessage case final message?)
          _errorBanner(context, message, controller.refreshSuperChats),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 3),
          child: Text('共 ${state.superChats.length} 条 SC'),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
            itemCount: state.superChats.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _superChatCard(state.superChats[index]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorBanner(
    BuildContext context,
    String message,
    VoidCallback retry,
  ) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
        TextButton(onPressed: retry, child: const Text('重试')),
      ],
    ),
  );

  Widget _superChatBubble(LiveSuperChatMessage message) {
    final selected = message.id == _selectedSuperChatId;
    return LiveSuperChatBubble(
      key: ValueKey('live-sc-chip-${message.id}'),
      message: message,
      selected: selected,
      onPressed: () {
        if (!selected && _chatScrollController.hasClients) {
          // Reset the old list anchor before inserting a full SC card at index 0.
          _jumpChatTo(0);
        }
        setState(() {
          _tab = 0;
          _selectedSuperChatId = selected ? null : message.id;
        });
        if (!selected) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                _selectedSuperChatId == message.id &&
                _chatScrollController.hasClients) {
              _jumpChatTo(0);
            }
          });
        }
      },
    );
  }

  Widget _superChatCard(LiveSuperChatMessage message) {
    final userId = message.userId;
    return LiveSuperChatCard(
      key: ValueKey('live-sc-card-${message.id}'),
      message: message,
      onOpenUser: userId == null || !userId.isValid || widget.onOpenUser == null
          ? null
          : () => widget.onOpenUser?.call(userId),
    );
  }

  String _compactCount(int count) {
    if (count < 10000) return count.toString();
    return '${(count / 10000).toStringAsFixed(1)}万';
  }
}
