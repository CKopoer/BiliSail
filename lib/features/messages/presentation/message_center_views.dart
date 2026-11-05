import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/user.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../shared/ui/app_dialog.dart';
import '../../../shared/ui/network_avatar.dart';
import '../../auth/application/auth_controller.dart';
import '../application/message_center_controller.dart';
import '../application/messages_controller.dart';
import '../domain/message_center_repository.dart';
import '../domain/message_repository.dart';

class MessageFansButton extends ConsumerWidget {
  const MessageFansButton({super.key, this.onOpenUser});
  final ValueChanged<UserId>? onOpenUser;
  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    tooltip: '新增粉丝',
    onPressed: ref.watch(messageCenterRepositoryProvider) == null
        ? null
        : () => _showPeople(context, ref, MessagePeopleKind.fans, onOpenUser),
    icon: const Icon(Icons.person_add_alt_outlined),
  );
}

class MessageReadAllButton extends ConsumerWidget {
  const MessageReadAllButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(messageCenterRepositoryProvider) != null;
    final busy =
        enabled &&
        ref.watch(
          messageCenterControllerProvider.select((state) => state.busy),
        );
    return IconButton(
      tooltip: '已加载私信一键已读',
      onPressed: !enabled || busy
          ? null
          : () async {
              final state = ref.read(messagesControllerProvider);
              final entries = state.section == InboxSection.private
                  ? state.inbox.items
                        .where(
                          (entry) =>
                              entry.sessionType == 1 &&
                              entry.userId != null &&
                              entry.unread > 0 &&
                              entry.lastSequence != null,
                        )
                        .toList(growable: false)
                  : <InboxEntry>[];
              if (entries.isEmpty) {
                showAppNotice(context, '已加载的私信中没有待确认的未读会话');
                return;
              }
              final repository = ref.read(messageCenterRepositoryProvider);
              final account = (
                repository?.accountScope,
                repository?.sessionEpoch,
              );
              if (!await _confirm(
                    context,
                    '将已加载的私信标为已读？',
                    '将确认 ${entries.length} 个已加载会话的最后已知消息，尚未加载的新消息与其他消息分类不在此次范围内。',
                  ) ||
                  !context.mounted) {
                return;
              }
              final currentRepository = ref.read(
                messageCenterRepositoryProvider,
              );
              if (!identical(repository, currentRepository) ||
                  (
                        currentRepository?.accountScope,
                        currentRepository?.sessionEpoch,
                      ) !=
                      account) {
                return;
              }
              final latest = ref.read(messagesControllerProvider);
              final ids = entries.map((entry) => entry.id).toSet();
              final current = latest.section == InboxSection.private
                  ? latest.inbox.items
                        .where((entry) => ids.contains(entry.id))
                        .toList(growable: false)
                  : <InboxEntry>[];
              final result = await ref
                  .read(messageCenterControllerProvider.notifier)
                  .markAllPrivateRead(current);
              if (!context.mounted) return;
              await ref.read(messagesControllerProvider.notifier).refresh();
              if (context.mounted && result != null) {
                showAppNotice(context, result.summary);
              }
            },
      icon: const Icon(Icons.done_all_rounded),
    );
  }
}

enum _CenterAction { settings, clear, up, contacts, groups, refresh }

class MessageCenterMoreButton extends ConsumerWidget {
  const MessageCenterMoreButton({super.key, this.onOpenUser});
  final ValueChanged<UserId>? onOpenUser;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(messageCenterRepositoryProvider) != null;
    return PopupMenuButton<_CenterAction>(
      tooltip: '更多消息操作',
      icon: const Icon(Icons.more_horiz_rounded),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _CenterAction.settings,
          enabled: enabled,
          child: const Text('消息设置'),
        ),
        PopupMenuItem(
          value: _CenterAction.contacts,
          enabled: enabled,
          child: const Text('通讯录'),
        ),
        PopupMenuItem(
          value: _CenterAction.up,
          enabled: enabled,
          child: const Text('UP 助手'),
        ),
        PopupMenuItem(
          value: _CenterAction.groups,
          enabled: enabled,
          child: const Text('粉丝团助手'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _CenterAction.refresh,
          child: Text('重新加载消息'),
        ),
        PopupMenuItem(
          value: _CenterAction.clear,
          enabled: enabled,
          child: const Text('清空已加载的私信会话'),
        ),
      ],
      onSelected: (action) async {
        switch (action) {
          case _CenterAction.settings:
            unawaited(
              ref.read(messageCenterControllerProvider.notifier).loadSettings(),
            );
            await _show(context, '消息设置', const _CenterSettings());
          case _CenterAction.contacts:
            await _showPeople(
              context,
              ref,
              MessagePeopleKind.contacts,
              onOpenUser,
            );
          case _CenterAction.up:
            await _showAssistants(context, ref, MessageAssistantKind.up);
          case _CenterAction.groups:
            await _showAssistants(context, ref, MessageAssistantKind.fanGroups);
          case _CenterAction.refresh:
            await ref.read(messagesControllerProvider.notifier).refresh();
          case _CenterAction.clear:
            await _clearLoaded(context, ref);
        }
      },
    );
  }
}

Future<void> _clearLoaded(BuildContext context, WidgetRef ref) async {
  final state = ref.read(messagesControllerProvider);
  final entries = state.section == InboxSection.private
      ? state.inbox.items
            .where((entry) => entry.canSend)
            .toList(growable: false)
      : <InboxEntry>[];
  if (entries.isEmpty) {
    showAppNotice(context, '请先在私信列表加载要移除的会话');
    return;
  }
  final repository = ref.read(messageCenterRepositoryProvider);
  final account = (repository?.accountScope, repository?.sessionEpoch);
  final confirmed = await _confirm(
    context,
    '清空已加载的私信会话？',
    '将移除已加载的 ${entries.length} 个单人会话，不会撤回已发送的消息。尚未加载的会话不受影响。',
  );
  if (!confirmed || !context.mounted) return;
  final current = ref.read(messageCenterRepositoryProvider);
  if (!identical(repository, current) ||
      (current?.accountScope, current?.sessionEpoch) != account) {
    return;
  }
  final ids = entries.map((entry) => entry.id).toSet();
  final latest = ref.read(messagesControllerProvider);
  final confirmedEntries = latest.section == InboxSection.private
      ? latest.inbox.items
            .where((entry) => ids.contains(entry.id) && entry.canSend)
            .toList(growable: false)
      : <InboxEntry>[];
  final result = await ref
      .read(messageCenterControllerProvider.notifier)
      .clearConversations(confirmedEntries);
  if (!context.mounted) return;
  await ref.read(messagesControllerProvider.notifier).refresh();
  if (context.mounted && result != null) showAppNotice(context, result.summary);
}

Future<void> showConversationSettings(
  BuildContext context,
  WidgetRef ref,
  InboxEntry entry, {
  ValueChanged<UserId>? onOpenUser,
  required VoidCallback onRefresh,
  required Future<bool> Function() onMarkRead,
}) async {
  final repository = ref.read(messageRepositoryProvider);
  final account = (repository.accountScope, repository.sessionEpoch);
  final controller = ref.read(messagesControllerProvider.notifier);
  InboxEntry? resolveEntry() {
    if (!context.mounted) return null;
    final currentRepository = ref.read(messageRepositoryProvider);
    if (!identical(repository, currentRepository) ||
        (currentRepository.accountScope, currentRepository.sessionEpoch) !=
            account) {
      return null;
    }
    final selected = ref.read(messagesControllerProvider).selected;
    return selected?.id == entry.id && selected?.userId == entry.userId
        ? selected
        : null;
  }

  if (ref.read(messageCenterRepositoryProvider) != null && entry.canSend) {
    unawaited(
      ref.read(messageCenterControllerProvider.notifier).loadChat(entry),
    );
  }
  // The dialog lives above the page's ProviderScope. Observe the owning page
  // explicitly rather than creating another messages controller on Navigator.
  // A snapshot also lets the dialog finish closing after its page is disposed.
  final messages = ValueNotifier(ref.read(messagesControllerProvider));
  final subscription = ref.listenManual(
    messagesControllerProvider,
    (_, next) => messages.value = next,
  );
  try {
    await _show(
      context,
      '聊天设置',
      ValueListenableBuilder<MessagesState>(
        valueListenable: messages,
        builder: (_, state, _) => _ChatSettings(
          entry: entry,
          messages: state,
          controller: controller,
          resolveEntry: resolveEntry,
          onOpenUser: onOpenUser,
          onRefresh: onRefresh,
          onMarkRead: onMarkRead,
        ),
      ),
    );
  } finally {
    subscription.close();
    messages.dispose();
  }
}

Future<void> _show(BuildContext context, String title, Widget child) =>
    showAppDialog<void>(
      context: context,
      builder: (_) => _AccountDialog(title: title, child: child),
    );

class _AccountDialog extends ConsumerWidget {
  const _AccountDialog({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authControllerProvider.select((state) => state.mid), (
      old,
      next,
    ) {
      if (old != next) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.of(context).maybePop();
        });
      }
    });
    return AlertDialog(
      title: Text(title),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      content: SizedBox(width: 520, height: 500, child: child),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _CenterSettings extends ConsumerWidget {
  const _CenterSettings();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(messageCenterControllerProvider);
    final controller = ref.read(messageCenterControllerProvider.notifier);
    if (state.loadingSettings) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      children: [
        if (state.error != null)
          _Status(text: state.error!, onRetry: controller.loadSettings),
        for (final setting in MessageSetting.values)
          if (state.settings?.values[setting] case final value?)
            ListTile(
              title: Text(setting.label),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: DropdownButton<int>(
                  value: value,
                  isExpanded: true,
                  items: [
                    for (final option in setting.options.entries)
                      DropdownMenuItem(
                        value: option.key,
                        child: Text(option.value),
                      ),
                  ],
                  onChanged: state.busy
                      ? null
                      : (value) {
                          if (value != null) {
                            controller.setSetting(setting, value);
                          }
                        },
                ),
              ),
            ),
        const Divider(),
        ListTile(
          title: const Text('黑名单'),
          leading: const Icon(Icons.block_outlined),
          onTap: () =>
              _showPeople(context, ref, MessagePeopleKind.blocked, null),
        ),
        ListTile(
          title: const Text('屏蔽词'),
          leading: const Icon(Icons.filter_alt_outlined),
          onTap: () {
            unawaited(controller.loadWords());
            _show(context, '私信屏蔽词', const _BlockedWords());
          },
        ),
        if (state.message case final message?) _Status(text: message),
      ],
    );
  }
}

class _BlockedWords extends ConsumerStatefulWidget {
  const _BlockedWords();
  @override
  ConsumerState<_BlockedWords> createState() => _BlockedWordsState();
}

class _BlockedWordsState extends ConsumerState<_BlockedWords> {
  final _word = TextEditingController();
  @override
  void dispose() {
    _word.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(messageCenterControllerProvider);
    final controller = ref.read(messageCenterControllerProvider.notifier);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _word,
                  maxLength: state.blockedWordLength,
                  decoration: const InputDecoration(
                    labelText: '添加屏蔽词',
                    counterText: '',
                  ),
                ),
              ),
              TextButton(
                onPressed: state.busy
                    ? null
                    : () async {
                        if (await controller.addBlockedWord(
                              _word.text.trim(),
                            ) &&
                            mounted) {
                          _word.clear();
                        }
                      },
                child: const Text('添加'),
              ),
            ],
          ),
        ),
        Text('${state.blockedWords.length}/${state.blockedWordLimit}'),
        if (state.error case final error?)
          _Status(text: error, onRetry: controller.loadWords),
        Expanded(
          child: state.loadingWords
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: state.blockedWords.length,
                  itemBuilder: (context, index) {
                    final word = state.blockedWords[index];
                    return ListTile(
                      title: Text(word),
                      trailing: IconButton(
                        tooltip: '删除屏蔽词',
                        onPressed: state.busy
                            ? null
                            : () => controller.removeBlockedWord(word),
                        icon: const Icon(Icons.close),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

Future<void> _showPeople(
  BuildContext context,
  WidgetRef ref,
  MessagePeopleKind kind,
  ValueChanged<UserId>? onOpenUser,
) async {
  unawaited(
    ref
        .read(messageCenterControllerProvider.notifier)
        .loadPeople(kind, refresh: true),
  );
  await _show(context, switch (kind) {
    MessagePeopleKind.fans => '新增粉丝',
    MessagePeopleKind.contacts => '通讯录',
    MessagePeopleKind.blocked => '黑名单',
  }, _People(kind: kind, onOpenUser: onOpenUser));
}

class _People extends ConsumerWidget {
  const _People({required this.kind, this.onOpenUser});
  final MessagePeopleKind kind;
  final ValueChanged<UserId>? onOpenUser;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(messageCenterControllerProvider);
    final controller = ref.read(messageCenterControllerProvider.notifier);
    return Column(
      children: [
        if (state.error case final error?)
          _Status(
            text: error,
            onRetry: () => controller.loadPeople(kind, refresh: true),
          ),
        Expanded(
          child: state.loadingPeople && state.people.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : state.people.isEmpty
              ? const Center(child: Text('暂无记录'))
              : ListView.builder(
                  itemCount: state.people.length,
                  itemBuilder: (context, index) {
                    final person = state.people[index];
                    return ListTile(
                      leading: NetworkAvatar(
                        url: person.avatarUrl,
                        name: person.name,
                        radius: 20,
                      ),
                      title: Text(person.name),
                      subtitle: Text(
                        person.sign.isEmpty
                            ? 'UID ${person.id.value}'
                            : person.sign,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: onOpenUser == null
                          ? null
                          : () {
                              Navigator.pop(context);
                              onOpenUser?.call(person.id);
                            },
                      trailing: TextButton(
                        onPressed: state.busy
                            ? null
                            : () async {
                                if (kind == MessagePeopleKind.blocked) {
                                  if (await _confirm(
                                        context,
                                        '移出黑名单？',
                                        '将允许该用户按你的消息设置联系你。',
                                      ) &&
                                      context.mounted) {
                                    await controller.unblockPerson(person);
                                  }
                                } else {
                                  Navigator.pop(context);
                                  ref
                                      .read(messagesControllerProvider.notifier)
                                      .openUserConversation(
                                        person.id,
                                        name: person.name,
                                        avatarUrl: person.avatarUrl,
                                      );
                                }
                              },
                        child: Text(
                          kind == MessagePeopleKind.blocked ? '移出黑名单' : '发私信',
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (state.peopleHasMore)
          TextButton(
            onPressed: state.loadingPeople
                ? null
                : () => controller.loadPeople(kind),
            child: const Text('加载更多'),
          ),
      ],
    );
  }
}

Future<void> _showAssistants(
  BuildContext context,
  WidgetRef ref,
  MessageAssistantKind kind,
) async {
  final repository = ref.read(messageRepositoryProvider);
  final account = (repository.accountScope, repository.sessionEpoch);
  unawaited(
    ref
        .read(messageCenterControllerProvider.notifier)
        .loadAssistants(kind, refresh: true),
  );
  await _show(
    context,
    kind == MessageAssistantKind.up ? 'UP 助手' : '粉丝团助手',
    _Assistants(
      kind: kind,
      onOpenConversation: (entry) {
        if (!context.mounted) return;
        final current = ref.read(messageRepositoryProvider);
        if (!identical(current, repository) ||
            (current.accountScope, current.sessionEpoch) != account) {
          return;
        }
        // Dialogs are above the workspace page's ProviderScope. Resolve this
        // controller from the caller rather than the dialog's root scope.
        final messages = ref.read(messagesControllerProvider.notifier);
        messages.selectSection(InboxSection.private);
        messages.selectConversation(entry);
      },
    ),
  );
}

class _Assistants extends ConsumerWidget {
  const _Assistants({required this.kind, required this.onOpenConversation});
  final MessageAssistantKind kind;
  final ValueChanged<InboxEntry> onOpenConversation;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(messageCenterControllerProvider);
    final controller = ref.read(messageCenterControllerProvider.notifier);
    return Column(
      children: [
        if (state.error case final error?) _Status(text: error),
        Expanded(
          child: state.loadingAssistants && state.assistants.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : state.assistants.isEmpty
              ? const Center(child: Text('当前账号没有可用会话'))
              : ListView.builder(
                  itemCount: state.assistants.length,
                  itemBuilder: (context, index) {
                    final entry = state.assistants[index];
                    return ListTile(
                      leading: NetworkAvatar(
                        url: entry.avatarUrl,
                        name: entry.title,
                        radius: 20,
                      ),
                      title: Text(entry.title),
                      subtitle: Text(
                        entry.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        onOpenConversation(entry);
                      },
                    );
                  },
                ),
        ),
        TextButton(
          onPressed: state.loadingAssistants
              ? null
              : () => controller.loadAssistants(
                  kind,
                  refresh: !state.assistantsHasMore,
                ),
          child: Text(state.assistantsHasMore ? '加载更多' : '重新加载'),
        ),
      ],
    );
  }
}

class _ChatSettings extends ConsumerWidget {
  const _ChatSettings({
    required this.entry,
    required this.messages,
    required this.controller,
    required this.resolveEntry,
    this.onOpenUser,
    required this.onRefresh,
    required this.onMarkRead,
  });
  final InboxEntry entry;
  final MessagesState messages;
  final MessagesController controller;
  final InboxEntry? Function() resolveEntry;
  final ValueChanged<UserId>? onOpenUser;
  final VoidCallback onRefresh;
  final Future<bool> Function() onMarkRead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = messages;
    final centerEnabled =
        ref.watch(messageCenterRepositoryProvider) != null && entry.canSend;
    final center = centerEnabled
        ? ref.watch(messageCenterControllerProvider)
        : null;
    final centerController = ref.read(messageCenterControllerProvider.notifier);
    final current = state.selected?.id == entry.id ? state.selected! : entry;
    final busy =
        resolveEntry() == null ||
        state.sending ||
        state.markingRead ||
        state.managingIds.contains(entry.id) ||
        (center?.busy ?? false);
    final chat = center?.chat?.entryId == entry.id ? center?.chat : null;
    return ListView(
      children: [
        ListTile(
          leading: NetworkAvatar(
            url: current.avatarUrl,
            name: current.title,
            radius: 24,
          ),
          title: Text(current.title),
          subtitle: Text('UID ${current.userId?.value ?? '—'}'),
          onTap: current.userId == null || onOpenUser == null || busy
              ? null
              : () {
                  if (resolveEntry()?.userId case final userId?) {
                    Navigator.pop(context);
                    onOpenUser?.call(userId);
                  }
                },
        ),
        if (state.supportsManagement && current.canSend) ...[
          SwitchListTile(
            title: const Text('置顶会话'),
            value: current.pinned,
            onChanged: busy
                ? null
                : (value) {
                    if (resolveEntry() case final latest?) {
                      controller.setPinned(latest, value);
                    }
                  },
          ),
          SwitchListTile(
            title: const Text('消息免打扰'),
            value: current.muted,
            onChanged: busy
                ? null
                : (value) {
                    if (resolveEntry() case final latest?) {
                      controller.setMuted(latest, value);
                    }
                  },
          ),
        ],
        if (center?.loadingChat ?? false) const LinearProgressIndicator(),
        if (chat != null && chat.showContentPush)
          SwitchListTile(
            title: const Text('接收内容推送'),
            value: chat.contentPush,
            onChanged: busy
                ? null
                : (value) {
                    if (resolveEntry() case final latest?) {
                      centerController.setContentPush(latest, value);
                    }
                  },
          ),
        if (chat != null)
          SwitchListTile(
            title: const Text('加入黑名单'),
            value: chat.blocked,
            onChanged: busy
                ? null
                : (value) async {
                    if (resolveEntry() == null) return;
                    if (!value ||
                        await _confirm(
                          context,
                          '加入黑名单？',
                          '将解除关注和合集订阅关系，并限制该用户与你互动或查看你的空间。',
                        )) {
                      if (context.mounted) {
                        if (resolveEntry() case final latest?) {
                          await centerController.setBlocked(latest, value);
                        }
                      }
                    }
                  },
          ),
        ListTile(
          leading: const Icon(Icons.done_all),
          title: const Text('标为已读'),
          onTap: busy || state.thread.loading || state.thread.items.isEmpty
              ? null
              : () async {
                  if (resolveEntry() != null) await onMarkRead();
                },
        ),
        ListTile(
          leading: const Icon(Icons.refresh),
          title: const Text('重新加载会话'),
          onTap: busy
              ? null
              : () {
                  if (resolveEntry() != null) onRefresh();
                },
        ),
        if (centerEnabled)
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('举报会话'),
            onTap: busy
                ? null
                : () async {
                    if (resolveEntry() == null) return;
                    await _show(
                      context,
                      '举报会话',
                      _ReportConversation(resolveEntry: resolveEntry),
                    );
                  },
          ),
        if (state.supportsManagement && current.canSend)
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('移除当前会话'),
            subtitle: const Text('从会话列表移除，不撤回已发送消息'),
            onTap: busy
                ? null
                : () async {
                    if (resolveEntry() == null) return;
                    if (await _confirm(context, '移除当前会话？', '此操作不会撤回已发送的消息。') &&
                        context.mounted) {
                      final latest = resolveEntry();
                      if (latest != null &&
                          await controller.removeConversation(latest)) {
                        if (context.mounted) Navigator.pop(context);
                      }
                    }
                  },
          ),
        if (center?.error case final error?) _Status(text: error),
        if (center?.message case final message?) _Status(text: message),
        if (state.writeMessage case final message?) _Status(text: message),
      ],
    );
  }
}

class _ReportConversation extends ConsumerStatefulWidget {
  const _ReportConversation({required this.resolveEntry});
  final InboxEntry? Function() resolveEntry;
  @override
  ConsumerState<_ReportConversation> createState() =>
      _ReportConversationState();
}

class _ReportConversationState extends ConsumerState<_ReportConversation> {
  String? _validationMessage;
  final _text = TextEditingController();
  int _reason = 4;
  static const _reasons = {
    1: '色情低俗',
    2: '政治敏感',
    3: '违法有害',
    4: '广告骚扰',
    5: '人身攻击',
    6: '诈骗',
    0: '其他',
  };
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(messageCenterControllerProvider);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        DropdownButton<int>(
          value: _reason,
          isExpanded: true,
          items: [
            for (final reason in _reasons.entries)
              DropdownMenuItem(value: reason.key, child: Text(reason.value)),
          ],
          onChanged: state.busy
              ? null
              : (value) {
                  if (value != null) {
                    setState(() {
                      _reason = value;
                      _validationMessage = null;
                    });
                  }
                },
        ),
        TextField(
          controller: _text,
          maxLength: 160,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: '补充说明',
            errorText: _validationMessage,
          ),
        ),
        if (state.error case final error?) _Status(text: error),
        FilledButton(
          onPressed: state.busy
              ? null
              : () async {
                  final entry = widget.resolveEntry();
                  if (entry == null) return;
                  final details = _text.text.trim();
                  if (_reason == 0 && details.isEmpty) {
                    setState(() => _validationMessage = '选择“其他”时请补充说明');
                    return;
                  }
                  if (await ref
                          .read(messageCenterControllerProvider.notifier)
                          .reportConversation(
                            entry,
                            _reason,
                            details.isEmpty
                                ? (_reasons[_reason] ?? '其他')
                                : details,
                          ) &&
                      context.mounted) {
                    Navigator.pop(context);
                    showAppNotice(context, '举报已提交');
                  }
                },
          child: const Text('提交举报'),
        ),
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.text, this.onRetry});
  final String text;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      children: [
        Text(text),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('重试')),
      ],
    ),
  );
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    ) ??
    false;
