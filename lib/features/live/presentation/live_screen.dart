import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/workspace_activity.dart';
import '../../../domain/user.dart';
import '../../../shared/ui/network_avatar.dart';
import '../../../shared/ui/playback_sidebar_toggle.dart';
import '../../../shared/ui/playback_info_tabs.dart';
import '../../../shared/ui/smooth_scroll_behavior.dart';
import '../../../shared/ui/state_view.dart';
import '../application/live_controller.dart';
import '../domain/live_chat_repository.dart';
import '../domain/live_room.dart';
import '../domain/live_chat_content.dart';
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
  String? _chatStatusAfterMessageKey;
  String? _displayedChatStatusAfterMessageKey;
  LiveConnectionPhase _displayedChatConnectionPhase = LiveConnectionPhase.idle;
  LiveRoom? _playerRoom;
  String? _playerRequestedId;
  LivePlayerBuilder? _playerBuilder;
  Widget? _playerWidget;
  final _chatContent = LiveChatContentCache();
  final _chatRows =
      <
        String,
        ({
          LiveChatMessage message,
          ValueChanged<UserId>? onOpenUser,
          Widget widget,
        })
      >{};
  List<LiveChatMessage>? _indexedMessages;
  Map<String, int> _messageIndices = const {};

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
      _chatStatusAfterMessageKey = null;
      _indexedMessages = null;
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
    if (delta > 0 && position.extentAfter <= 1 && !_followChat) {
      // A resized viewport can already fit the frozen window. Downward input
      // still means returning to live chat even without a scroll update.
      setState(() => _followChat = true);
      _scheduleChatFollow();
      return;
    }
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
      final delta = notification.scrollDelta ?? 0;
      if (delta < 0 || (delta > 0 && notification.metrics.extentAfter > 1)) {
        _followChat = false;
      } else if (delta > 0 &&
          notification.metrics.extentAfter <= 1 &&
          !_followChat) {
        // Publish the latest bounded window even if no further message arrives.
        setState(() => _followChat = true);
        _scheduleChatFollow();
      }
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
    final page = ref.watch(
      liveControllerProvider(id).select(
        (state) => (
          room: state.room,
          loading: state.loading,
          message: state.roomMessage,
        ),
      ),
    );
    ref.listen(liveControllerProvider(id), (previous, next) {
      if (!identical(previous?.superChats, next.superChats) &&
          !next.superChats.any(
            (message) => message.id == _selectedSuperChatId,
          )) {
        _selectedSuperChatId = null;
      }
      if (next.room == null || next.messages.isEmpty) {
        _chatStatusAfterMessageKey = null;
        // Account/room reloads must also release the previous reading snapshot.
        _indexedMessages = null;
        _followChat = true;
        _chatUserScrolling = false;
      } else if (previous?.connectionPhase != next.connectionPhase) {
        // Anchor before this update's new messages, including a batch that
        // contains both authentication success and the first live chats.
        _chatStatusAfterMessageKey =
            previous?.messages.lastOrNull?.deduplicationKey;
      }
    });
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

    final room = page.room;
    if (room == null) {
      if (page.message case final message?) {
        return StateView.error(message: message, onAction: controller.load);
      }
      return const StateView.loading(message: '正在加载直播间…');
    }

    // Keep the actual builder below the room scope so inherited dependencies
    // still rebuild it, while chat, audience and sidebar updates reuse its tree.
    if (!identical(_playerRoom, room) ||
        _playerRequestedId != widget.roomId ||
        _playerBuilder != widget.playerBuilder) {
      _playerRoom = room;
      _playerRequestedId = widget.roomId;
      _playerBuilder = widget.playerBuilder;
      _playerWidget = _player(context, room);
    }
    final player = _playerWidget ??= _player(context, room);
    final sidebar = _sidebar(context, room, controller);
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
              child: player,
            ),
            Positioned(
              left: wide ? constraints.maxWidth - 380 : 0,
              top: wide ? 0 : compactPlayerHeight,
              width: wide ? 380 : constraints.maxWidth,
              height: infoHeight,
              child: ExcludeFocus(
                excluding: !_infoVisible,
                child: Offstage(offstage: !_infoVisible, child: sidebar),
              ),
            ),
            if (wide)
              Positioned(
                right: _infoVisible ? 380 : 0,
                top: math.max(
                  0.0,
                  playerHeight / 2 - PlaybackSidebarToggle.size.height / 2,
                ),
                child: PlaybackSidebarToggle(
                  tooltip: _infoVisible ? '收起直播信息' : '展开直播信息',
                  icon: _infoVisible ? Icons.chevron_right : Icons.chevron_left,
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
        : Builder(
            builder: (context) => Center(
              child: Text(
                '主播尚未开播',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: Colors.white),
              ),
            ),
          ),
  );

  Widget _sidebar(
    BuildContext context,
    LiveRoom room,
    LiveController controller,
  ) {
    final provider = liveControllerProvider(RoomId(widget.roomId));
    final roomInfo = SingleChildScrollView(child: _roomInfo(context, room));
    final content = Expanded(
      child: WorkspaceActivity(
        active: _lastActive == true && _infoVisible,
        child: PlaybackInfoTabs(
          key: ValueKey(widget.roomId),
          value: _tab,
          onChanged: (tab) => setState(() => _tab = tab),
          viewKey: const ValueKey('live-info-swipe'),
          labels: [
            const Text('聊天'),
            Consumer(
              builder: (context, ref, _) {
                final count = ref.watch(
                  provider.select((state) => state.superChats.length),
                );
                return Text('SC ($count)');
              },
            ),
          ],
          itemKey: (tab) => ValueKey('live-tab-$tab'),
          compact: true,
          preloadPages: true,
          trailing: Consumer(
            builder: (context, ref, _) {
              ref.watch(
                provider.select(
                  (state) => (
                    state.connectionPhase,
                    state.chatLoading,
                    state.superChatLoading,
                  ),
                ),
              );
              final state = ref.read(provider);
              return IconButton(
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
              );
            },
          ),
          pageBuilder: (context, tab, active) => TickerMode(
            enabled: _lastActive == true && _infoVisible && active,
            child: tab == 0
                ? _chat(context, controller)
                : Consumer(
                    builder: (context, ref, _) {
                      ref.watch(
                        provider.select(
                          (state) => (
                            state.superChats,
                            state.superChatLoading,
                            state.superChatMessage,
                          ),
                        ),
                      );
                      return _superChats(
                        context,
                        ref.read(provider),
                        controller,
                      );
                    },
                  ),
          ),
        ),
      ),
    );
    final composer = <Widget>[
      if (widget.composerBuilder case final builder?) ...[
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(10),
          child: builder(context, RoomId(widget.roomId)),
        ),
      ],
    ];
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.max(0, constraints.maxHeight * .4),
              ),
              child: roomInfo,
            ),
            const Divider(height: 1),
            content,
            ...composer,
          ],
        ),
      ),
    );
  }

  Widget _roomInfo(BuildContext context, LiveRoom room) {
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
                  child: Consumer(
                    builder: (context, ref, _) {
                      final counts = ref.watch(
                        liveControllerProvider(RoomId(widget.roomId)).select(
                          (state) => (
                            viewer: state.viewerCountText,
                            watched: state.watchedCountText,
                          ),
                        ),
                      );
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            counts.viewer == null
                                ? '在看人数暂无数据'
                                : '当前${counts.viewer}人在看',
                            key: const ValueKey('live-viewer-count'),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            counts.watched == null
                                ? '看过人数暂无数据'
                                : '${counts.watched}人看过',
                            key: const ValueKey('live-watched-count'),
                          ),
                        ],
                      );
                    },
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

  Widget _chat(BuildContext context, LiveController controller) {
    final provider = liveControllerProvider(RoomId(widget.roomId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Consumer(
          builder: (context, ref, _) {
            ref.watch(
              provider.select(
                (state) => (state.superChats, state.superChatMessage),
              ),
            );
            final state = ref.read(provider);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state.superChats.isNotEmpty)
                  SizedBox(
                    height: 54,
                    child: ScrollConfiguration(
                      behavior: const SmoothScrollBehavior(
                        horizontalMouseWheel: true,
                      ).copyWith(scrollbars: false),
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
              ],
            );
          },
        ),
        Consumer(
          builder: (context, ref, _) {
            ref.watch(
              provider.select(
                (state) => (
                  state.connectionMessage,
                  state.chatMessage,
                  state.messages.isEmpty,
                ),
              ),
            );
            final state = ref.read(provider);
            return Column(
              children: [
                if (state.connectionMessage case final message?)
                  _errorBanner(context, message, controller.retryRealtime),
                if (state.chatMessage case final message?)
                  if (state.messages.isNotEmpty)
                    _errorBanner(context, message, controller.refreshChat),
              ],
            );
          },
        ),
        Expanded(
          child: Consumer(
            builder: (context, ref, _) {
              ref.watch(
                provider.select(
                  (state) => (
                    state.messages,
                    state.chatMessage,
                    state.chatLoading,
                    state.connectionPhase,
                    state.superChatLoading,
                    state.superChats
                        .where((message) => message.id == _selectedSuperChatId)
                        .firstOrNull,
                  ),
                ),
              );
              return _chatMessages(context, ref.read(provider), controller);
            },
          ),
        ),
      ],
    );
  }

  Widget _chatMessages(
    BuildContext context,
    LiveState state,
    LiveController controller,
  ) {
    // Freeze only the displayed window while reading history. The controller
    // keeps receiving up to 500 latest messages independently, so eviction or
    // metadata updates cannot move the text or scrollbar under the user's hand.
    final messages = _followChat
        ? state.messages
        : (_indexedMessages ?? state.messages);
    if (_followChat || _indexedMessages == null) {
      _displayedChatStatusAfterMessageKey = _chatStatusAfterMessageKey;
      _displayedChatConnectionPhase = state.connectionPhase;
    }
    if (!identical(_indexedMessages, messages)) {
      _indexedMessages = messages;
      _messageIndices = {
        for (var index = 0; index < messages.length; index++)
          messages[index].deduplicationKey: index,
      };
      _chatRows.removeWhere((key, _) => !_messageIndices.containsKey(key));
      _chatContent.retain(_messageIndices.keys.toSet());
    }
    final selected = state.superChats
        .where((message) => message.id == _selectedSuperChatId)
        .firstOrNull;
    _scheduleChatFollow();
    final bodyCount = messages.isEmpty ? 1 : messages.length;
    final statusAnchor = _displayedChatStatusAfterMessageKey;
    final anchorIndex = _messageIndices[statusAnchor] ?? -1;
    // Drop the notice with its message once the bounded chat window evicts it.
    final statusIndex = statusAnchor == null
        ? (messages.isEmpty ? bodyCount : 0)
        : anchorIndex < 0
        ? null
        : anchorIndex + 1;
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Keep the selected SC visible independently of chat scroll/eviction.
          // Bound long messages so chat remains reachable on small windows.
          ConstrainedBox(
            key: const ValueKey('live-sc-details'),
            constraints: BoxConstraints(maxHeight: constraints.maxHeight * .5),
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              reverseDuration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => SizeTransition(
                sizeFactor: animation,
                alignment: Alignment.topCenter,
                child: FadeTransition(opacity: animation, child: child),
              ),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [
                  for (final child in previous)
                    ExcludeFocus(
                      child: ExcludeSemantics(
                        child: IgnorePointer(
                          child: TickerMode(enabled: false, child: child),
                        ),
                      ),
                    ),
                  ?current,
                ],
              ),
              child: selected == null
                  ? const SizedBox.shrink(key: ValueKey('live-sc-collapsed'))
                  : SingleChildScrollView(
                      key: ValueKey(('live-selected-sc', selected.id)),
                      primary: false,
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: _superChatCard(selected),
                      ),
                    ),
            ),
          ),
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
                    itemCount: bodyCount + (statusIndex == null ? 0 : 1),
                    findChildIndexCallback: (key) {
                      if (key == const ValueKey('live-chat-status')) {
                        return statusIndex;
                      }
                      if (key is! ValueKey<(String, String)>) return null;
                      final index = _messageIndices[key.value.$2];
                      if (index == null) return null;
                      return index +
                          (statusIndex != null && index >= statusIndex ? 1 : 0);
                    },
                    itemBuilder: (context, bodyIndex) {
                      if (bodyIndex == statusIndex) {
                        return KeyedSubtree(
                          key: const ValueKey('live-chat-status'),
                          child: _chatConnectionStatus(context, state),
                        );
                      }
                      if (messages.isEmpty) {
                        return switch (state.chatMessage) {
                          final String message => StateView.error(
                            message: message,
                            onAction: controller.refreshChat,
                          ),
                          null when state.chatLoading =>
                            const StateView.loading(message: '正在读取最近消息…'),
                          null => const StateView.empty(
                            message: '暂无聊天消息',
                            icon: Icons.chat_bubble_outline,
                          ),
                        };
                      }
                      final messageIndex =
                          bodyIndex -
                          (statusIndex != null && bodyIndex > statusIndex
                              ? 1
                              : 0);
                      final message = messages[messageIndex];
                      return _chatRow(message);
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chatRow(LiveChatMessage message) {
    final key = message.deduplicationKey;
    final previous = _chatRows[key];
    if (previous != null &&
        identical(previous.message, message) &&
        previous.onOpenUser == widget.onOpenUser) {
      return previous.widget;
    }
    final row = KeyedSubtree(
      key: ValueKey(('live-message', key)),
      child: LiveChatBubble(
        key: ValueKey(('live-chat-bubble', key)),
        message: message,
        content: _chatContent.resolve(message),
        onOpenUser: widget.onOpenUser,
      ),
    );
    _chatRows[key] = (
      message: message,
      onOpenUser: widget.onOpenUser,
      widget: row,
    );
    return row;
  }

  Widget _chatConnectionStatus(BuildContext context, LiveState state) {
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('live-chat-connection-status'),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              switch (_displayedChatConnectionPhase) {
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
      clock: ref.read(liveClockProvider),
      onPressed: () {
        setState(() {
          _tab = 0;
          _selectedSuperChatId = _selectedSuperChatId == message.id
              ? null
              : message.id;
        });
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
      clock: ref.read(liveClockProvider),
    );
  }

  String _compactCount(int count) {
    if (count < 10000) return count.toString();
    return '${(count / 10000).toStringAsFixed(1)}万';
  }
}
