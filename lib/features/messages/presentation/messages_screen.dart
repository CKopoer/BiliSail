import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/external_links.dart';
import '../../../domain/user.dart';
import '../../../shared/ui/network_avatar.dart';
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
  });
  final VoidCallback? onLogin;
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<Uri>? onOpenTarget;
  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  final Map<String, String> _drafts = {};
  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    ref.listen(
      authControllerProvider.select((s) => (s.isSignedIn, s.mid)),
      (_, _) => _drafts.clear(),
    );
    if (!auth.isSignedIn) {
      return StateView.empty(
        message: '登录后查看我的消息',
        icon: Icons.mail_outline,
        actionLabel: '登录',
        onAction: widget.onLogin,
      );
    }
    final state = ref.watch(messagesControllerProvider);
    final controller = ref.read(messagesControllerProvider.notifier);
    final unreadState = ref.watch(unreadMessagesProvider);
    final unread = unreadState.isLoading || unreadState.hasError
        ? const <InboxSection, int>{}
        : unreadState.value ?? const {};
    return Column(
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
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final section in InboxSection.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: state.section == section,
                    label: Text(
                      '${section.label}${(unread[section] ?? 0) > 0 ? ' · ${unread[section]}' : ''}',
                    ),
                    onSelected: (_) => controller.selectSection(section),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final entry = state.selected;
              final wide = constraints.maxWidth >= 720;
              final list = _InboxList(
                state: state.inbox,
                selected: entry?.id,
                isPrivate: state.section == InboxSection.private,
                section: state.section,
                onMore: controller.loadInbox,
                onRefresh: () => controller.loadInbox(refresh: true),
                onSelect: controller.selectConversation,
                onOpenUser: widget.onOpenUser,
                onOpenTarget: widget.onOpenTarget,
              );
              if (state.section != InboxSection.private) return list;
              final thread = entry == null
                  ? const StateView.empty(
                      message: '选择一个会话查看消息',
                      icon: Icons.chat_bubble_outline,
                    )
                  : _ConversationView(
                      key: ValueKey('${auth.mid}:${entry.id}'),
                      entry: entry,
                      ownMid: auth.mid,
                      state: state,
                      narrow: !wide,
                      initialDraft: _drafts[entry.id] ?? '',
                      onDraftChanged: (text) {
                        _drafts.remove(entry.id);
                        if (text.isNotEmpty) _drafts[entry.id] = text;
                        if (_drafts.length > 500) {
                          _drafts.remove(_drafts.keys.first);
                        }
                      },
                      onBack: controller.closeConversation,
                      onMore: controller.loadThread,
                      onRefresh: () => controller.loadThread(refresh: true),
                      onSend: (text) async {
                        final sent = await controller.send(text);
                        if (sent && mounted && _drafts[entry.id] == text) {
                          _drafts.remove(entry.id);
                        }
                        return sent;
                      },
                      onMarkRead: controller.markRead,
                      onOpenUser: widget.onOpenUser,
                      onOpenTarget: widget.onOpenTarget,
                    );
              if (!wide) return entry == null ? list : thread;
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
    );
  }
}

class _InboxList extends StatelessWidget {
  const _InboxList({
    required this.state,
    required this.isPrivate,
    required this.section,
    required this.onMore,
    required this.onRefresh,
    required this.onSelect,
    this.selected,
    this.onOpenUser,
    this.onOpenTarget,
  });
  final MessageListState<InboxEntry> state;
  final bool isPrivate;
  final InboxSection section;
  final String? selected;
  final VoidCallback onMore, onRefresh;
  final ValueChanged<InboxEntry> onSelect;
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<Uri>? onOpenTarget;
  @override
  Widget build(BuildContext context) {
    if (state.loading && state.items.isEmpty) return const StateView.loading();
    if (state.error != null && state.items.isEmpty) {
      return StateView.error(message: state.error ?? '', onAction: onRefresh);
    }
    if (state.items.isEmpty) {
      return const StateView.empty(
        message: '暂时没有消息',
        icon: Icons.inbox_outlined,
      );
    }
    return ListView.builder(
      key: PageStorageKey('inbox-${section.name}'),
      padding: const EdgeInsets.all(8),
      itemCount: state.items.length + 1,
      itemBuilder: (context, index) {
        if (index == state.items.length) {
          return _ListFooter(
            loading: state.loading,
            error: state.error,
            hasMore: state.hasMore,
            onMore: onMore,
            endLabel: section == InboxSection.system
                ? '当前显示最近 20 条系统通知，更多请打开官方消息页'
                : state.items.length >= 500
                ? '已加载 500 条消息'
                : '没有更多消息',
          );
        }
        final entry = state.items[index], user = state.items[index].userId;
        return Card(
          elevation: 0,
          color: entry.id == selected
              ? Theme.of(context).colorScheme.secondaryContainer
              : null,
          child: ListTile(
            key: ValueKey(entry.id),
            leading: InkWell(
              onTap: !isPrivate && user != null
                  ? () => onOpenUser?.call(user)
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
                          onOpenTarget?.call(entry.targetUrl ?? Uri()),
                      child: const Text('查看原内容'),
                    ),
                ],
              ),
            ),
            onTap: isPrivate ? () => onSelect(entry) : null,
          ),
        );
      },
    );
  }
}

class _ConversationView extends StatefulWidget {
  const _ConversationView({
    super.key,
    required this.entry,
    required this.ownMid,
    required this.state,
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
  final InboxEntry entry;
  final String? ownMid;
  final MessagesState state;
  final bool narrow;
  final String initialDraft;
  final ValueChanged<String> onDraftChanged;
  final VoidCallback onBack, onMore, onRefresh;
  final Future<bool> Function(String) onSend;
  final Future<bool> Function() onMarkRead;
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<Uri>? onOpenTarget;
  @override
  State<_ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<_ConversationView> {
  late final TextEditingController _draft = TextEditingController(
    text: widget.initialDraft,
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
    final state = widget.state, entry = widget.entry;
    final busy = state.sending || state.markingRead;
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
                onPressed:
                    busy || state.thread.loading || state.thread.items.isEmpty
                    ? null
                    : widget.onMarkRead,
                icon: const Icon(Icons.done_all),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _thread(context, state.thread)),
        if (state.writeMessage case final message?)
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
                  child: Text(state.sending ? '发送中' : '发送'),
                ),
              ],
            ),
          )
        else
          const Padding(padding: EdgeInsets.all(12), child: Text('此会话仅支持查看')),
      ],
    );
  }

  Widget _thread(BuildContext context, MessageListState<PrivateMessage> list) {
    if (list.loading && list.items.isEmpty) return const StateView.loading();
    if (list.error != null && list.items.isEmpty) {
      return StateView.error(
        message: list.error ?? '',
        onAction: widget.onRefresh,
      );
    }
    if (list.items.isEmpty) return const StateView.empty(message: '暂无会话消息');
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(16),
      itemCount: list.items.length + 1,
      itemBuilder: (context, index) {
        if (index == list.items.length) {
          return _ListFooter(
            loading: list.loading,
            error: list.error,
            hasMore: list.hasMore,
            onMore: widget.onMore,
            label: '加载更早的消息',
            endLabel: list.items.length >= 500 ? '已加载 500 条消息' : '没有更早的消息',
          );
        }
        final message = list.items[list.items.length - 1 - index];
        final own = message.senderId.value == widget.ownMid;
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
                              onPressed: () =>
                                  widget.onOpenTarget?.call(target),
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
