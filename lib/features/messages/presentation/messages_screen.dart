import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/external_links.dart';
import '../../../core/presentation/page_back_scope.dart';
import '../../../core/presentation/workspace_activity.dart';
import '../../../domain/user.dart';
import '../../../shared/ui/network_avatar.dart';
import '../../../shared/ui/page_tab_style.dart';
import '../../../shared/ui/paging_tab_strip.dart';
import '../../../shared/ui/retained_tab_view.dart';
import '../../../shared/ui/smooth_scroll_behavior.dart';
import '../../../shared/ui/state_view.dart';
import '../../auth/application/auth_controller.dart';
import '../application/messages_controller.dart';
import '../domain/message_repository.dart';

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({
    super.key,
    this.onLogin,
    this.onOpenUser,
    this.onOpenTarget,
    this.initialUserId,
    this.initialUserName,
    this.initialUserAvatar,
    this.onInitialConversationOpened,
  });
  final VoidCallback? onLogin;
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<Uri>? onOpenTarget;
  final UserId? initialUserId;
  final String? initialUserName;
  final Uri? initialUserAvatar;
  final VoidCallback? onInitialConversationOpened;
  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  final Map<String, String> _drafts = {};
  final _pagingProgress = TabPagingProgress(0);
  int _openVersion = 0;

  @override
  void dispose() {
    _pagingProgress.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _openInitialConversation();
  }

  @override
  void didUpdateWidget(MessagesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialUserId != widget.initialUserId) {
      _openInitialConversation();
    }
  }

  void _openInitialConversation() {
    final version = ++_openVersion;
    final id = widget.initialUserId;
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || version != _openVersion) return;
      if (ref
          .read(messagesControllerProvider.notifier)
          .openUserConversation(
            id,
            name: widget.initialUserName,
            avatarUrl: widget.initialUserAvatar,
          )) {
        widget.onInitialConversationOpened?.call();
      }
    });
  }

  void _scheduleRead(MessagesState state) {
    final controller = ref.read(messagesControllerProvider.notifier);
    final active = WorkspaceActivity.isActive(context);
    if (active &&
        state.section == InboxSection.private &&
        (state.selected?.unread ?? 0) > 0 &&
        !state.thread.loading &&
        state.thread.error == null &&
        state.thread.items.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !WorkspaceActivity.isActive(context)) return;
        final current = ref.read(messagesControllerProvider);
        if (current.section == InboxSection.private &&
            current.selected?.id == state.selected?.id &&
            identical(current.thread, state.thread)) {
          controller.markRead(automatic: true);
        }
      });
      // A read/write transition can change only controls or a non-visible
      // footer. Ensure its deferred visibility check gets a frame as well.
      WidgetsBinding.instance.ensureVisualUpdate();
    }
    if (active &&
        state.section == InboxSection.system &&
        !state.inbox.loading &&
        state.inbox.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !WorkspaceActivity.isActive(context)) return;
        final current = ref.read(messagesControllerProvider);
        if (current.section == InboxSection.system &&
            identical(current.inbox, state.inbox)) {
          controller.markSystemNotificationsRead();
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(
      authControllerProvider.select((state) => (state.isSignedIn, state.mid)),
    );
    ref.listen(authControllerProvider.select((s) => (s.isSignedIn, s.mid)), (
      _,
      _,
    ) {
      _drafts.clear();
      _openInitialConversation();
    });
    if (!auth.$1) {
      return StateView.empty(
        message: '登录后查看我的消息',
        icon: Icons.mail_outline,
        actionLabel: '登录',
        onAction: widget.onLogin,
      );
    }
    // Read effects still observe every transition, including visibility changes,
    // while navigation only rebuilds when the selected page actually changes.
    ref.listen(messagesControllerProvider, (_, state) => _scheduleRead(state));
    _scheduleRead(ref.read(messagesControllerProvider));
    final (section, selectedId) = ref.watch(
      messagesControllerProvider.select(
        (state) => (state.section, state.selected?.id),
      ),
    );
    final controller = ref.read(messagesControllerProvider.notifier);
    return PageBackHandler(
      enabled: section == InboxSection.private && selectedId != null,
      onBack: () {
        controller.closeConversation();
        return true;
      },
      child: TabPagingScope(
        progress: _pagingProgress,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '我的消息',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: '刷新消息',
                    onPressed: controller.refresh,
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: '官方消息页',
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () => ref.read(externalLinkOpenerProvider)(
                      Uri.https('message.bilibili.com', '/'),
                    ),
                  ),
                ],
              ),
            ),
            const _MessageSections(),
            const Divider(height: 1),
            Expanded(
              child: RetainedTabView<InboxSection>(
                key: ValueKey(auth.$2),
                viewKey: const ValueKey('message-section-pager'),
                tabs: InboxSection.values,
                value: section,
                progress: _pagingProgress,
                onChanged: controller.selectSection,
                pageBuilder: (context, tab, active) => TickerMode(
                  enabled: active && WorkspaceActivity.isActive(context),
                  child: Column(
                    children: [
                      if (tab == InboxSection.system)
                        const _SystemWriteMessage(),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth >= 720;
                            final list = _InboxList(
                              section: tab,
                              onOpenUser: widget.onOpenUser,
                              onOpenTarget: widget.onOpenTarget,
                            );
                            if (tab != InboxSection.private) return list;
                            final thread = selectedId == null
                                ? const StateView.empty(
                                    message: '选择一个会话查看消息',
                                    icon: Icons.chat_bubble_outline,
                                  )
                                : _ConversationView(
                                    key: ValueKey('${auth.$2}:$selectedId'),
                                    ownMid: auth.$2,
                                    narrow: !wide,
                                    initialDraft: _drafts[selectedId] ?? '',
                                    onDraftChanged: (text) {
                                      _drafts.remove(selectedId);
                                      if (text.isNotEmpty) {
                                        _drafts[selectedId] = text;
                                      }
                                      if (_drafts.length > 500) {
                                        _drafts.remove(_drafts.keys.first);
                                      }
                                    },
                                    onBack: controller.closeConversation,
                                    onMore: controller.loadThread,
                                    onRefresh: () =>
                                        controller.loadThread(refresh: true),
                                    onSend: (text) async {
                                      final sent = await controller.send(text);
                                      if (sent &&
                                          mounted &&
                                          _drafts[selectedId] == text) {
                                        // A different view of this conversation may have
                                        // reopened while the original send was pending.
                                        setState(
                                          () => _drafts.remove(selectedId),
                                        );
                                      }
                                      return sent;
                                    },
                                    onMarkRead: controller.markRead,
                                    onOpenUser: widget.onOpenUser,
                                    onOpenTarget: widget.onOpenTarget,
                                  );
                            if (!wide) {
                              return selectedId == null ? list : thread;
                            }
                            return Row(
                              children: [
                                SizedBox(width: 300, child: list),
                                const VerticalDivider(width: 1),
                                Expanded(child: thread),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageSections extends ConsumerWidget {
  const _MessageSections();

  IconData _icon(InboxSection section) => switch (section) {
    InboxSection.private => Icons.chat_bubble_outline_rounded,
    InboxSection.replies => Icons.reply_rounded,
    InboxSection.mentions => Icons.alternate_email_rounded,
    InboxSection.likes => Icons.favorite_border_rounded,
    InboxSection.system => Icons.notifications_none_rounded,
  };

  String _label(InboxSection section) => switch (section) {
    InboxSection.replies => '回复',
    InboxSection.mentions => '我的',
    _ => section.label,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(
      messagesControllerProvider.select((state) => state.section),
    );
    final unreadState = ref.watch(unreadMessagesProvider);
    final unread = unreadState.isLoading || unreadState.hasError
        ? const <InboxSection, int>{}
        : unreadState.value ?? const {};
    return SizedBox(
      height: PageTabStyle.barHeight,
      child: ScrollConfiguration(
        behavior: const SmoothScrollBehavior(horizontalMouseWheel: true)
            .copyWith(
              dragDevices: {
                ...const SmoothScrollBehavior().dragDevices,
                PointerDeviceKind.mouse,
              },
            ),
        child: SingleChildScrollView(
          key: const ValueKey('message-section-strip'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: PagingTabStrip<InboxSection>(
            tabs: InboxSection.values,
            value: section,
            progress: TabPagingScope.maybeOf(context),
            onSelected: ref
                .read(messagesControllerProvider.notifier)
                .selectSection,
            itemKey: (section) => ValueKey('message-section-${section.name}'),
            buttonStyle: PageTabStyle.buttonStyle(context),
            labelBuilder: (context, section) => PageTabStyle.label(
              '${_label(section)}${(unread[section] ?? 0) > 0 ? ' · ${unread[section]}' : ''}',
              icon: _icon(section),
            ),
          ),
        ),
      ),
    );
  }
}

class _SystemWriteMessage extends ConsumerWidget {
  const _SystemWriteMessage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.watch(
      messagesControllerProvider.select((state) => state.writeMessage),
    );
    return message == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(message),
          );
  }
}

class _InboxList extends ConsumerStatefulWidget {
  const _InboxList({required this.section, this.onOpenUser, this.onOpenTarget});
  final InboxSection section;
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<Uri>? onOpenTarget;
  @override
  ConsumerState<_InboxList> createState() => _InboxListState();
}

class _InboxListState extends ConsumerState<_InboxList> {
  // A retained neighbor must keep its own rows during the next swipe rather
  // than render the newly selected category's inbox.
  (List<InboxEntry>, String?, bool, String?) _snapshot = (
    const [],
    null,
    true,
    null,
  );

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(
      messagesControllerProvider.select(
        (state) => state.section == widget.section
            ? (
                state.inbox.items,
                state.selected?.id,
                state.inbox.items.isEmpty && state.inbox.loading,
                state.inbox.items.isEmpty ? state.inbox.error : null,
              )
            : null,
      ),
    );
    if (current != null) _snapshot = current;
    final (items, selected, loading, error) = _snapshot;
    final section = widget.section;
    final controller = ref.read(messagesControllerProvider.notifier);
    final isPrivate = section == InboxSection.private;
    if (loading) return const StateView.loading();
    if (error != null) {
      return StateView.error(
        message: error,
        onAction: () => controller.loadInbox(refresh: true),
      );
    }
    if (items.isEmpty) {
      return const StateView.empty(
        message: '暂时没有消息',
        icon: Icons.inbox_outlined,
      );
    }
    return ListView.builder(
      key: PageStorageKey('inbox-${section.name}'),
      padding: const EdgeInsets.all(8),
      itemCount: items.length + 1,
      itemBuilder: (context, index) {
        if (index == items.length) return _InboxFooter(section: section);
        final entry = items[index], user = items[index].userId;
        return Card(
          elevation: 0,
          color: entry.id == selected
              ? Theme.of(context).colorScheme.secondaryContainer
              : null,
          child: ListTile(
            key: ValueKey(entry.id),
            leading: InkWell(
              onTap: !isPrivate && user != null
                  ? () => widget.onOpenUser?.call(user)
                  : null,
              child: Badge(
                isLabelVisible: entry.unread > 0,
                label: Text(entry.unread > 99 ? '99+' : '${entry.unread}'),
                child: NetworkAvatar(
                  url: entry.avatarUrl,
                  name: entry.title,
                  radius: 20,
                ),
              ),
            ),
            title: Text(
              entry.title,
              maxLines: isPrivate ? 1 : 3,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.text,
                    maxLines: isPrivate ? 2 : null,
                    overflow: isPrivate ? TextOverflow.ellipsis : null,
                  ),
                  if (entry.time != null)
                    Text(
                      _time(entry.time),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  if (!isPrivate && entry.targetUrl != null)
                    TextButton(
                      onPressed: () =>
                          widget.onOpenTarget?.call(entry.targetUrl ?? Uri()),
                      child: const Text('查看原内容'),
                    ),
                ],
              ),
            ),
            onTap: isPrivate
                ? () => controller.selectConversation(entry)
                : null,
          ),
        );
      },
    );
  }
}

class _InboxFooter extends ConsumerStatefulWidget {
  const _InboxFooter({required this.section});
  final InboxSection section;

  @override
  ConsumerState<_InboxFooter> createState() => _InboxFooterState();
}

class _InboxFooterState extends ConsumerState<_InboxFooter> {
  (bool, String?, bool, int) _snapshot = (false, null, false, 0);

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(
      messagesControllerProvider.select(
        (state) => state.section == widget.section
            ? (
                state.inbox.loading,
                state.inbox.error,
                state.inbox.hasMore,
                state.inbox.items.length,
              )
            : null,
      ),
    );
    if (current != null) _snapshot = current;
    final (loading, error, hasMore, length) = _snapshot;
    return _ListFooter(
      loading: loading,
      error: error,
      hasMore: hasMore,
      onMore: ref.read(messagesControllerProvider.notifier).loadInbox,
      endLabel: widget.section == InboxSection.system
          ? '当前显示最近 20 条系统通知，更多请打开官方消息页'
          : length >= 500
          ? '已加载 500 条消息'
          : '没有更多消息',
    );
  }
}

class _ConversationView extends ConsumerStatefulWidget {
  const _ConversationView({
    super.key,
    required this.ownMid,
    required this.narrow,
    required this.initialDraft,
    required this.onDraftChanged,
    required this.onBack,
    required this.onMore,
    required this.onRefresh,
    required this.onSend,
    required this.onMarkRead,
    this.onOpenUser,
    this.onOpenTarget,
  });
  final String? ownMid;
  final bool narrow;
  final String initialDraft;
  final ValueChanged<String> onDraftChanged;
  final VoidCallback onBack, onMore, onRefresh;
  final Future<bool> Function(String) onSend;
  final Future<bool> Function() onMarkRead;
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<Uri>? onOpenTarget;
  @override
  ConsumerState<_ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends ConsumerState<_ConversationView> {
  late final TextEditingController _draft = TextEditingController(
    text: widget.initialDraft,
  );
  // Retain the body when send/read controls change. Delegating through this
  // State keeps callbacks current after the parent updates its handlers.
  late final Widget _thread = _ConversationThread(
    ownMid: widget.ownMid,
    onMore: () => widget.onMore(),
    onRefresh: () => widget.onRefresh(),
    onOpenTarget: (target) => widget.onOpenTarget?.call(target),
  );
  @override
  void didUpdateWidget(covariant _ConversationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A send may finish while this conversation is closed and opened again.
    // Keep newer edits, but synchronize a draft cleared by its successful send.
    if (widget.initialDraft != oldWidget.initialDraft &&
        _draft.text == oldWidget.initialDraft) {
      _draft.text = widget.initialDraft;
    }
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _draft.text;
    final sent = await widget.onSend(text);
    if (sent && mounted && _draft.text == text) {
      _draft.clear();
      widget.onDraftChanged('');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (entry, sending, markingRead, writeMessage, canMarkRead) = ref.watch(
      messagesControllerProvider.select(
        (state) => (
          state.selected,
          state.sending,
          state.markingRead,
          state.writeMessage,
          !state.thread.loading && state.thread.items.isNotEmpty,
        ),
      ),
    );
    if (entry == null) return const SizedBox.shrink();
    final busy = sending || markingRead;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              if (widget.narrow)
                IconButton(
                  tooltip: '返回会话列表',
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back),
                ),
              Expanded(
                child: TextButton(
                  onPressed: entry.userId == null || entry.system
                      ? null
                      : () => widget.onOpenUser?.call(
                          entry.userId ?? const UserId('0'),
                        ),
                  child: Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              IconButton(
                tooltip: '刷新会话',
                onPressed: widget.onRefresh,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: '标为已读',
                onPressed: busy || !canMarkRead ? null : widget.onMarkRead,
                icon: const Icon(Icons.done_all),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _thread),
        if (writeMessage case final message?)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(message, textAlign: TextAlign.center),
          ),
        if (entry.canSend)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _draft,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 1000,
                    onChanged: widget.onDraftChanged,
                    decoration: const InputDecoration(
                      hintText: '输入私信消息',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: busy ? null : _send,
                  child: Text(sending ? '发送中' : '发送'),
                ),
              ],
            ),
          )
        else
          const Padding(padding: EdgeInsets.all(12), child: Text('此会话仅支持查看')),
      ],
    );
  }
}

class _ConversationThread extends ConsumerWidget {
  const _ConversationThread({
    required this.ownMid,
    required this.onMore,
    required this.onRefresh,
    this.onOpenTarget,
  });

  final String? ownMid;
  final VoidCallback onMore, onRefresh;
  final ValueChanged<Uri>? onOpenTarget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (items, loading, error) = ref.watch(
      messagesControllerProvider.select(
        (state) => (
          state.thread.items,
          state.thread.items.isEmpty && state.thread.loading,
          state.thread.items.isEmpty ? state.thread.error : null,
        ),
      ),
    );
    if (loading) return const StateView.loading();
    if (error != null) {
      return StateView.error(message: error, onAction: onRefresh);
    }
    if (items.isEmpty) return const StateView.empty(message: '暂无会话消息');
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(16),
      itemCount: items.length + 1,
      itemBuilder: (context, index) {
        if (index == items.length) {
          return _ThreadFooter(onMore: onMore);
        }
        final message = items[items.length - 1 - index];
        final own = message.senderId.value == ownMid;
        return Align(
          key: ValueKey(message.id),
          alignment: own ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                crossAxisAlignment: own
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    _time(message.time),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 3),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: own
                          ? Theme.of(context).colorScheme.secondaryContainer
                          : Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(message.text),
                          if (message.imageUrl case final image?)
                            _PrivateImage(url: image),
                          if (message.targetUrl case final Uri target
                              when message.imageUrl == null)
                            TextButton(
                              onPressed: () => onOpenTarget?.call(target),
                              child: const Text('查看分享内容'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ThreadFooter extends ConsumerWidget {
  const _ThreadFooter({required this.onMore});
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (loading, error, hasMore, length) = ref.watch(
      messagesControllerProvider.select(
        (state) => (
          state.thread.loading,
          state.thread.error,
          state.thread.hasMore,
          state.thread.items.length,
        ),
      ),
    );
    return _ListFooter(
      loading: loading,
      error: error,
      hasMore: hasMore,
      onMore: onMore,
      label: '加载更早的消息',
      endLabel: length >= 500 ? '已加载 500 条消息' : '没有更早的消息',
    );
  }
}

/// Private pictures never enter the public disk cache; evict decoded pixels on close.
class _PrivateImage extends StatefulWidget {
  const _PrivateImage({required this.url});
  final Uri url;
  @override
  State<_PrivateImage> createState() => _PrivateImageState();
}

class _PrivateImageState extends State<_PrivateImage> {
  late final _image = NetworkImage(widget.url.toString());
  @override
  void dispose() {
    _image.evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Image(
      image: _image,
      width: 220,
      height: 180,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const Text('图片暂时无法加载'),
    ),
  );
}

class _ListFooter extends StatelessWidget {
  const _ListFooter({
    required this.loading,
    required this.hasMore,
    required this.onMore,
    this.error,
    this.label = '加载更多',
    this.endLabel = '没有更多消息',
  });
  final bool loading, hasMore;
  final String? error;
  final VoidCallback onMore;
  final String label;
  final String endLabel;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      children: [
        if (error != null) Text(error ?? '', textAlign: TextAlign.center),
        if (loading)
          const LinearProgressIndicator()
        else if (hasMore)
          TextButton(
            onPressed: onMore,
            child: Text(error == null ? label : '重试'),
          )
        else
          Text(endLabel, textAlign: TextAlign.center),
      ],
    ),
  );
}

String _time(DateTime? time) {
  if (time == null) return '';
  final local = time.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
