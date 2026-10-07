import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/user.dart';
import '../../features/video/application/video_author_controller.dart';
import '../../features/video/domain/video_author_repository.dart';

/// Shares follow writes and their uncertainty handling across user surfaces.
final class UserFollowButton extends ConsumerWidget {
  const UserFollowButton({
    super.key,
    required this.id,
    this.onLogin,
    this.compact = false,
    this.showMessage = true,
  });

  final UserId id;
  final VoidCallback? onLogin;
  final bool compact, showMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!id.isValid) return const SizedBox.shrink();
    final mid = id.value;
    final provider = videoAuthorControllerProvider(VideoAuthorId(mid));
    final state = ref.watch(provider);
    if (state.isSelf) return const SizedBox.shrink();
    final author = state.author;
    final theme = Theme.of(context);
    final following = author?.following == true;
    final needsRefresh =
        state.uncertain || (author == null && state.message != null);
    final Widget button;
    if (following && state.signedIn && !needsRefresh) {
      button = PopupMenuButton<String>(
        tooltip: '关注操作',
        enabled:
            !state.busy &&
            !state.loading &&
            !state.groupsLoading &&
            !state.groupsBusy,
        position: PopupMenuPosition.under,
        onSelected: (action) {
          final controller = ref.read(provider.notifier);
          if (action == 'groups') {
            unawaited(controller.loadGroups());
            unawaited(
              showDialog<void>(
                context: context,
                builder: (_) => _FollowGroupsDialog(id: VideoAuthorId(mid)),
              ),
            );
          } else if (action == 'unfollow') {
            unawaited(controller.toggleFollow());
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'groups', child: Text('设置分组')),
          PopupMenuItem(value: 'unfollow', child: Text('取消关注')),
        ],
        child: Container(
          constraints: BoxConstraints(minHeight: compact ? 32 : 48),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(compact ? 6 : 4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.busy)
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                )
              else
                const Icon(Icons.menu, size: 16),
              const SizedBox(width: 5),
              Text(state.busy ? '处理中' : '已关注'),
            ],
          ),
        ),
      );
    } else {
      button = TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: following || needsRefresh
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.primary,
          backgroundColor: following || needsRefresh
              ? theme.colorScheme.surfaceContainerHigh
              : theme.colorScheme.primaryContainer,
          minimumSize: Size(80, compact ? 32 : 40),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          tapTargetSize: compact
              ? MaterialTapTargetSize.shrinkWrap
              : MaterialTapTargetSize.padded,
        ),
        onPressed: state.busy || state.loading
            ? null
            : !state.signedIn
            ? onLogin
            : () {
                final controller = ref.read(provider.notifier);
                if (needsRefresh) {
                  controller.refresh();
                } else {
                  controller.toggleFollow();
                }
              },
        icon: state.busy || state.loading
            ? SizedBox.square(
                dimension: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : Icon(
                needsRefresh
                    ? Icons.refresh
                    : following
                    ? Icons.check
                    : Icons.add,
                size: 15,
              ),
        label: Text(
          state.busy
              ? '处理中'
              : needsRefresh
              ? '刷新状态'
              : following
              ? '已关注'
              : '关注',
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        button,
        if (showMessage && state.message != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                state.message ?? '',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
      ],
    );
  }
}

final class _FollowGroupsDialog extends ConsumerWidget {
  const _FollowGroupsDialog({required this.id});

  final VideoAuthorId id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = videoAuthorControllerProvider(id);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final groups = state.groups;
    return AlertDialog(
      title: const Text('设置分组'),
      scrollable: true,
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.groupsLoading)
              const Center(child: CircularProgressIndicator())
            else if (groups == null)
              const Text('分组加载失败，请重试')
            else if (groups.isEmpty)
              const Text('暂无可设置的分组')
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final group in groups)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(group.name),
                          value: state.selectedGroupIds.contains(group.id),
                          onChanged: state.groupsBusy || state.groupsUncertain
                              ? null
                              : (selected) => controller.selectGroup(
                                  group.id,
                                  selected == true,
                                ),
                        ),
                    ],
                  ),
                ),
              ),
            if (state.groupsMessage case final String message)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: state.groupsBusy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        if (state.groupsUncertain || groups == null)
          TextButton(
            onPressed: state.groupsLoading || state.groupsBusy
                ? null
                : () => unawaited(controller.loadGroups()),
            child: const Text('刷新状态'),
          )
        else
          FilledButton(
            onPressed:
                state.groupsLoading ||
                    state.groupsBusy ||
                    !state.signedIn ||
                    state.author?.following != true
                ? null
                : () async {
                    if (await controller.saveGroups() && context.mounted) {
                      Navigator.pop(context);
                    }
                  },
            child: Text(state.groupsBusy ? '保存中' : '保存'),
          ),
      ],
    );
  }
}
