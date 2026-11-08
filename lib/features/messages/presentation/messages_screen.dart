import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/page_back_scope.dart';
import '../../../core/presentation/workspace_activity.dart';
import '../../../domain/user.dart';
import '../../../shared/ui/network_avatar.dart';
import '../../../shared/ui/page_tab_style.dart';
import '../../../shared/ui/page_toolbar.dart';
import '../../../shared/ui/paging_tab_strip.dart';
import '../../../shared/ui/retained_tab_view.dart';
import '../../../shared/ui/smooth_scroll_behavior.dart';
import '../../../shared/ui/state_view.dart';
import '../../../shared/ui/app_dialog.dart';
import '../../auth/application/auth_controller.dart';
import '../application/messages_controller.dart';
import '../application/message_center_controller.dart';
import '../domain/message_repository.dart';
import '../domain/message_composer.dart';
import 'message_content_view.dart';
import 'message_center_views.dart';
import 'message_composer_bar.dart';
import 'message_rich_text.dart';
import 'message_reply_sheet.dart';

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
  final Map<String, MessageLocalImage> _imageDrafts = {};
  final _privateFilter = _ConversationFilter();
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
    // The page owns dialog work even when its narrow toolbar is not mounted.
    ref.watch(messageCenterControllerProvider.notifier);
    final auth = ref.watch(
      authControllerProvider.select((state) => (state.isSignedIn, state.mid)),
    );
    ref.listen(authControllerProvider.select((s) => (s.isSignedIn, s.mid)), (
      _,
      _,
    ) {
      _drafts.clear();
      _imageDrafts.clear();
      _privateFilter.clear();
      _openInitialConversation();
    });
    if (!auth.$1) {
      return Column(
        children: [
          const PageToolbar(title: '我的消息'),
          Expanded(
            child: StateView.empty(
              message: '登录后查看我的消息',
              icon: Icons.mail_outline,
              actionLabel: '登录',
              onAction: widget.onLogin,
            ),
          ),
        ],
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
      enabled: selectedId != null || section != InboxSection.private,
      onBack: () {
        if (section == InboxSection.private && selectedId != null) {
          controller.closeConversation();
        } else {
          controller.selectSection(InboxSection.private);
        }
        return true;
      },
      child: TabPagingScope(
        progress: _pagingProgress,
        child: Column(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 600 &&
                    (section != InboxSection.private || selectedId != null)) {
                  return const SizedBox.shrink();
                }
                return PageToolbar(
                  title: '我的消息',
                  actions: [
                    MessageFansButton(onOpenUser: widget.onOpenUser),
                    const MessageReadAllButton(),
                    MessageCenterMoreButton(onOpenUser: widget.onOpenUser),
                  ],
                );
              },
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final sidebar = constraints.maxWidth >= 1000;
                  final narrow = constraints.maxWidth < 600;
                  final pages = RetainedTabView<InboxSection>(
                    key: ValueKey(auth.$2),
                    viewKey: const ValueKey('message-section-pager'),
                    tabs: InboxSection.values,
                    value: section,
                    progress: _pagingProgress,
                    // Categories use explicit entry points in the message center.
                    swipeEnabled: false,
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
                                  filter: tab == InboxSection.private
                                      ? _privateFilter
                                      : null,
                                  onOpenUser: widget.onOpenUser,
                                  onOpenTarget: widget.onOpenTarget,
                                );
                                if (tab != InboxSection.private) {
                                  return Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 860,
                                      ),
                                      child: list,
                                    ),
                                  );
                                }
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
                                        initialImage: _imageDrafts[selectedId],
                                        onSendImage: (image) async {
                                          final sent = await controller
                                              .sendImage(image);
                                          if (sent &&
                                              mounted &&
                                              identical(
                                                _imageDrafts[selectedId],
                                                image,
                                              )) {
                                            setState(
                                              () => _imageDrafts.remove(
                                                selectedId,
                                              ),
                                            );
                                          }
                                          return sent;
                                        },
                                        onImageChanged: (image) {
                                          setState(() {
                                            _imageDrafts.remove(selectedId);
                                            if (image != null) {
                                              _imageDrafts[selectedId] = image;
                                            }
                                            while (_imageDrafts.length > 8) {
                                              _imageDrafts.remove(
                                                _imageDrafts.keys.first,
                                              );
                                            }
                                          });
                                        },
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
                                        onRefresh: () => controller.loadThread(
                                          refresh: true,
                                        ),
                                        onSend: (text) async {
                                          final sent = await controller.send(
                                            text,
                                          );
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
                                    SizedBox(
                                      width: sidebar ? 300 : 280,
                                      child: list,
                                    ),
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
                  );
                  if (sidebar) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(
                          width: 180,
                          child: _MessageSections(sidebar: true),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: pages),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      if (!narrow)
                        const _MessageSections()
                      else if (section != InboxSection.private)
                        _MessageSectionBack(section: section)
                      else if (selectedId == null)
                        const _MessageSections(shortcuts: true),
                      const Divider(height: 1),
                      Expanded(child: pages),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageSections extends ConsumerWidget {
  const _MessageSections({this.sidebar = false, this.shortcuts = false});
  final bool sidebar, shortcuts;

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
    final controller = ref.read(messagesControllerProvider.notifier);
    if (sidebar) {
      return SingleChildScrollView(
        key: const ValueKey('message-sidebar'),
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            for (final tab in InboxSection.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: TextButton(
                  key: ValueKey('message-section-${tab.name}'),
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    minimumSize: const Size(double.infinity, 56),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    backgroundColor: tab == section
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : null,
                    foregroundColor: tab == section
                        ? Theme.of(context).colorScheme.onSecondaryContainer
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => controller.selectSection(tab),
                  child: Row(
                    children: [
                      Icon(_icon(tab), size: 21),
                      const SizedBox(width: 10),
                      Expanded(child: Text(tab.label)),
                      if ((unread[tab] ?? 0) > 0) ...[
                        const SizedBox(width: 8),
                        Badge(
                          label: Text(
                            (unread[tab] ?? 0) > 99 ? '99+' : '${unread[tab]}',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    }
    if (shortcuts) {
      return Padding(
        key: const ValueKey('message-shortcuts'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final tab in InboxSection.values.skip(1))
              Expanded(
                child: InkWell(
                  key: ValueKey('message-section-${tab.name}'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => controller.selectSection(tab),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 2,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Badge(
                          isLabelVisible: (unread[tab] ?? 0) > 0,
                          label: Text(
                            (unread[tab] ?? 0) > 99
                                ? '99+'
                                : '${unread[tab] ?? 0}',
                          ),
                          child: CircleAvatar(
                            radius: 23,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .secondaryContainer,
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .primary,
                            child: Icon(_icon(tab)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          tab == InboxSection.mentions ? '@我' : tab.label,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
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

class _MessageSectionBack extends ConsumerWidget {
  const _MessageSectionBack({required this.section});
  final InboxSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Row(
      children: [
        IconButton(
          key: const ValueKey('message-section-private'),
          tooltip: '返回消息首页',
          onPressed: () => ref
              .read(messagesControllerProvider.notifier)
              .selectSection(InboxSection.private),
          icon: const Icon(Icons.arrow_back),
        ),
        Expanded(
          child: Text(
            section.label,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ],
    ),
  );
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

class _ConversationFilter {
  String query = '';
  bool searching = false, unreadOnly = false;
  void clear() {
    query = '';
    searching = false;
    unreadOnly = false;
  }
}

class _InboxList extends ConsumerStatefulWidget {
  const _InboxList({
    required this.section,
    this.filter,
    this.onOpenUser,
    this.onOpenTarget,
  });
  final InboxSection section;
  final _ConversationFilter? filter;
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<Uri>? onOpenTarget;
  @override
  ConsumerState<_InboxList> createState() => _InboxListState();
}

class _InboxListState extends ConsumerState<_InboxList> {
  String get _query => widget.filter?.query ?? '';
  set _query(String value) => widget.filter?.query = value;
  bool get _searching => widget.filter?.searching ?? false;
  set _searching(bool value) => widget.filter?.searching = value;
  bool get _unreadOnly => widget.filter?.unreadOnly ?? false;
  set _unreadOnly(bool value) => widget.filter?.unreadOnly = value;
  // A retained neighbor must keep its own rows during category transitions rather
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
    final visible = isPrivate
        ? items
              .where(
                (entry) =>
                    (!_unreadOnly || entry.unread > 0) &&
                    (_query.isEmpty ||
                        '${entry.title} ${entry.text}'.toLowerCase().contains(
                          _query.toLowerCase(),
                        )),
              )
              .toList(growable: false)
        : items;
    final list = visible.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    items.isEmpty ? '暂时没有消息' : '已加载的会话中没有匹配结果',
                    textAlign: TextAlign.center,
                  ),
                ),
                _InboxFooter(section: section),
              ],
            ),
          )
        : ListView.builder(
            key: PageStorageKey('inbox-${section.name}'),
            padding: EdgeInsets.symmetric(
              horizontal: isPrivate ? 8 : 16,
              vertical: 8,
            ),
            itemCount: visible.length + 1,
            itemBuilder: (context, index) {
              if (index == visible.length) {
                return _InboxFooter(section: section);
              }
              final entry = visible[index];
              if (isPrivate) {
                return _ConversationRow(
                  entry: entry,
                  selected: entry.id == selected,
                  onOpen: () => controller.selectConversation(entry),
                );
              }
              return _NotificationRow(
                entry: entry,
                onOpenUser: widget.onOpenUser,
                onOpenTarget: widget.onOpenTarget,
              );
            },
          );
    if (!isPrivate) return list;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '私信',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                key: const ValueKey('message-search-toggle'),
                tooltip: _searching ? '关闭会话搜索' : '搜索会话',
                onPressed: () => setState(() {
                  _searching = !_searching;
                  if (!_searching) _query = '';
                }),
                icon: Icon(
                  _searching ? Icons.search_off_rounded : Icons.search_rounded,
                ),
              ),
              FilterChip(
                key: const ValueKey('message-unread-filter'),
                label: const Text('未读'),
                selected: _unreadOnly,
                onSelected: (value) => setState(() => _unreadOnly = value),
              ),
            ],
          ),
        ),
        if (_searching)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextFormField(
              key: const ValueKey('message-search-field'),
              initialValue: _query,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: '搜索已加载的会话',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
        const _InboxWriteMessage(),
        Expanded(child: list),
      ],
    );
  }
}

class _InboxWriteMessage extends ConsumerWidget {
  const _InboxWriteMessage();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.watch(
      messagesControllerProvider.select(
        (state) => state.selected == null ? state.writeMessage : null,
      ),
    );
    return message == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.all(8),
            child: Text(message, textAlign: TextAlign.center),
          );
  }
}

enum _ConversationAction { pin, mute, remove }

class _ConversationRow extends ConsumerWidget {
  const _ConversationRow({
    required this.entry,
    required this.selected,
    required this.onOpen,
  });
  final InboxEntry entry;
  final bool selected;
  final VoidCallback onOpen;

  List<PopupMenuEntry<_ConversationAction>> _items() => [
    PopupMenuItem(
      value: _ConversationAction.pin,
      child: Text(entry.pinned ? '取消置顶' : '置顶会话'),
    ),
    PopupMenuItem(
      value: _ConversationAction.mute,
      child: Text(entry.muted ? '关闭免打扰' : '消息免打扰'),
    ),
    const PopupMenuDivider(),
    const PopupMenuItem(value: _ConversationAction.remove, child: Text('移除会话')),
  ];

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    _ConversationAction action,
  ) async {
    if (!context.mounted) return;
    final original = ref.read(messagesControllerProvider);
    if (!original.inbox.items.any((item) => identical(item, entry)) &&
        !identical(original.selected, entry)) {
      return;
    }
    final repository = ref.read(messageRepositoryProvider);
    final account = (repository.accountScope, repository.sessionEpoch);
    final controller = ref.read(messagesControllerProvider.notifier);
    InboxEntry? currentEntry() {
      if (!context.mounted) return null;
      final currentRepository = ref.read(messageRepositoryProvider);
      if ((currentRepository.accountScope, currentRepository.sessionEpoch) !=
          account) {
        return null;
      }
      final state = ref.read(messagesControllerProvider);
      for (final item in state.inbox.items) {
        if (item.id == entry.id && item.canSend) return item;
      }
      final selected = state.selected;
      return selected?.id == entry.id && (selected?.canSend ?? false)
          ? selected
          : null;
    }

    switch (action) {
      case _ConversationAction.pin:
        await controller.setPinned(entry, !entry.pinned);
      case _ConversationAction.mute:
        await controller.setMuted(entry, !entry.muted);
      case _ConversationAction.remove:
        final confirm = await showAppDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('移除会话？'),
            content: Text('将“${entry.title}”从会话列表中移除，此操作不会撤回已发送的消息。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('移除'),
              ),
            ],
          ),
        );
        if (confirm == true && context.mounted) {
          final latest = currentEntry();
          if (latest != null) await controller.removeConversation(latest);
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(messagesControllerProvider.notifier);
    final busy = ref.watch(
      messagesControllerProvider.select(
        (state) => state.managingIds.contains(entry.id),
      ),
    );
    final manageable = controller.supportsManagement && entry.canSend;
    final theme = Theme.of(context);
    return GestureDetector(
      onLongPress: !manageable || busy
          ? null
          : () async {
              final action = await showModalBottomSheet<_ConversationAction>(
                context: context,
                showDragHandle: true,
                builder: (context) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        title: Text(entry.pinned ? '取消置顶' : '置顶会话'),
                        leading: const Icon(Icons.push_pin_outlined),
                        onTap: () =>
                            Navigator.pop(context, _ConversationAction.pin),
                      ),
                      ListTile(
                        title: Text(entry.muted ? '关闭免打扰' : '消息免打扰'),
                        leading: const Icon(Icons.notifications_off_outlined),
                        onTap: () =>
                            Navigator.pop(context, _ConversationAction.mute),
                      ),
                      ListTile(
                        title: const Text('移除会话'),
                        leading: const Icon(Icons.delete_outline),
                        onTap: () =>
                            Navigator.pop(context, _ConversationAction.remove),
                      ),
                    ],
                  ),
                ),
              );
              if (action != null && context.mounted) {
                await _act(context, ref, action);
              }
            },
      onSecondaryTapDown: !manageable || busy
          ? null
          : (details) async {
              final overlay =
                  Overlay.of(context).context.findRenderObject() as RenderBox;
              final local = overlay.globalToLocal(details.globalPosition);
              final action = await showMenu<_ConversationAction>(
                context: context,
                position: RelativeRect.fromSize(
                  Rect.fromLTWH(local.dx, local.dy, 0, 0),
                  overlay.size,
                ),
                items: _items(),
              );
              if (action != null && context.mounted) {
                await _act(context, ref, action);
              }
            },
      child: Material(
        color: selected
            ? theme.colorScheme.secondaryContainer
            : entry.pinned
            ? theme.colorScheme.surfaceContainerLow
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          key: ValueKey(entry.id),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          leading: Badge(
            isLabelVisible: entry.unread > 0,
            label: Text(entry.unread > 99 ? '99+' : '${entry.unread}'),
            child: NetworkAvatar(
              url: entry.avatarUrl,
              name: entry.title,
              radius: 22,
            ),
          ),
          title: Text(
            entry.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.text, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (entry.time != null)
                    Text(_time(entry.time), style: theme.textTheme.labelSmall),
                  if (entry.pinned)
                    const Tooltip(
                      message: '已置顶',
                      child: Icon(Icons.push_pin_rounded, size: 13),
                    ),
                  if (entry.muted)
                    const Tooltip(
                      message: '免打扰',
                      child: Icon(Icons.notifications_off_outlined, size: 13),
                    ),
                ],
              ),
            ],
          ),
          trailing: !manageable
              ? null
              : PopupMenuButton<_ConversationAction>(
                  key: ValueKey('message-menu-${entry.id}'),
                  tooltip: '管理会话',
                  enabled: !busy,
                  onSelected: (action) => _act(context, ref, action),
                  itemBuilder: (_) => _items(),
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.more_horiz_rounded),
                ),
          onTap: onOpen,
        ),
      ),
    );
  }
}

class _NotificationRow extends ConsumerWidget {
  const _NotificationRow({
    required this.entry,
    this.onOpenUser,
    this.onOpenTarget,
  });
  final InboxEntry entry;
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<Uri>? onOpenTarget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = entry.userId;
    final canReply = entry.replyContext != null;
    final source = [
      entry.sourceTitle,
      entry.sourceText,
    ].where((text) => text.isNotEmpty).join(' · ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: !canReply
            ? null
            : () => showMessageReply(
                context,
                ref,
                entry,
                onOpenTarget: onOpenTarget,
              ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!entry.system) ...[
                    InkWell(
                      onTap: user == null ? null : () => onOpenUser?.call(user),
                      child: NetworkAvatar(
                        url: entry.avatarUrl,
                        name: entry.title,
                        radius: 21,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        if (entry.text.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: MessageRichText(
                              text: entry.text,
                              emotes: entry.emotes,
                              onOpenTarget: onOpenTarget,
                              maxLines: entry.system ? null : 2,
                            ),
                          ),
                        if (source.isNotEmpty || entry.sourceImageUrl != null)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (entry.sourceImageUrl case final image?) ...[
                                  PrivateMessageImage(
                                    url: image,
                                    width: 72,
                                    height: 48,
                                    preview: false,
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: MessageRichText(
                                    text: source,
                                    emotes: entry.emotes,
                                    onOpenTarget: onOpenTarget,
                                    maxLines: 2,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (entry.time != null)
                              Text(
                                _time(entry.time),
                                style: theme.textTheme.labelSmall,
                              ),
                            if (canReply)
                              TextButton.icon(
                                onPressed: () => showMessageReply(
                                  context,
                                  ref,
                                  entry,
                                  onOpenTarget: onOpenTarget,
                                ),
                                icon: const Icon(Icons.reply_rounded, size: 17),
                                label: const Text('回复'),
                              ),
                            if (entry.targetUrl case final target?)
                              TextButton(
                                onPressed: () => onOpenTarget?.call(target),
                                child: const Text('查看原内容'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Divider(height: 1, indent: entry.system ? 0 : 54),
            ],
          ),
        ),
      ),
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
    required this.onImageChanged,
    required this.onSendImage,
    this.initialImage,
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
  final MessageLocalImage? initialImage;
  final ValueChanged<MessageLocalImage?> onImageChanged;
  final Future<bool> Function(MessageLocalImage) onSendImage;
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
    final (entry, sending, markingRead, writeMessage) = ref.watch(
      messagesControllerProvider.select(
        (state) => (
          state.selected,
          state.sending,
          state.markingRead,
          state.writeMessage,
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
              NetworkAvatar(
                url: entry.avatarUrl,
                name: entry.title,
                radius: 18,
              ),
              const SizedBox(width: 8),
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
                tooltip: '聊天设置',
                onPressed: () => showConversationSettings(
                  context,
                  ref,
                  entry,
                  onOpenUser: widget.onOpenUser,
                  onRefresh: widget.onRefresh,
                  onMarkRead: widget.onMarkRead,
                ),
                icon: const Icon(Icons.settings_outlined),
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
          MessageComposerBar(
            text: _draft,
            onChanged: widget.onDraftChanged,
            onSend: _send,
            busy: busy,
            image: widget.initialImage,
            onImageChanged: widget.onImageChanged,
            onSendImage: widget.onSendImage,
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
    final contact = ref.watch(
      messagesControllerProvider.select(
        (state) => (state.selected?.title, state.selected?.avatarUrl),
      ),
    );
    final ownProfile = ref.watch(
      authControllerProvider.select(
        (state) => (state.userName, state.avatarUrl),
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
        if (message.kind == MessageContentKind.withdrawn ||
            message.kind == MessageContentKind.notice) {
          return Padding(
            key: ValueKey(message.id),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            child: Center(
              child: Text(
                message.text,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          );
        }
        final older = items.length - 2 - index >= 0
            ? items[items.length - 2 - index]
            : null;
        final showTime =
            message.time != null &&
            (older?.time == null ||
                message.time!.difference(older!.time!).abs() >=
                    const Duration(minutes: 5));
        final avatar = NetworkAvatar(
          url: own ? ownProfile.$2 : contact.$2,
          name: own ? ownProfile.$1 ?? '我' : contact.$1 ?? '',
          radius: 17,
        );
        return Padding(
          key: ValueKey(message.id),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              if (showTime)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    _time(message.time),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: own
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                children: [
                  if (!own) ...[avatar, const SizedBox(width: 8)],
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: own
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: MessageContentView(
                            message: message,
                            onOpenTarget: onOpenTarget,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (own) ...[const SizedBox(width: 8), avatar],
                ],
              ),
            ],
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
