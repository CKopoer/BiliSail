import 'dart:async';

import '../../../domain/user.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/video.dart';
import '../../../shared/ui/network_avatar.dart';
import '../../../shared/ui/video_card.dart';
import '../application/video_author_controller.dart';
import '../domain/video_author_repository.dart';

final class VideoAuthorHeader extends ConsumerWidget {
  const VideoAuthorHeader({
    super.key,
    required this.video,
    this.onLogin,
    this.onOpenUser,
  });
  final VideoDetail video;
  final VoidCallback? onLogin;
  final ValueChanged<UserId>? onOpenUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mid = video.authorMid;
    final provider = mid == null
        ? null
        : videoAuthorControllerProvider(VideoAuthorId(mid));
    final state = provider == null ? null : ref.watch(provider);
    final author = state?.author;
    final theme = Theme.of(context);
    final following = author?.following == true;
    final needsRefresh =
        state?.uncertain == true || (author == null && state?.message != null);
    Widget? button;
    if (state != null && !state.isSelf) {
      if (following &&
          state.signedIn &&
          !needsRefresh &&
          provider != null &&
          mid != null) {
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
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(6),
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
            minimumSize: const Size(80, 32),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: state.busy || state.loading
              ? null
              : !state.signedIn
              ? onLogin
              : () {
                  if (provider == null) return;
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
    }
    final userId = UserId.tryParse(video.authorMid) ?? video.summary.authorId;
    final identity = InkWell(
      onTap: userId?.isValid == true && onOpenUser != null
          ? () => onOpenUser!(userId!)
          : null,
      child: Row(
        children: [
          NetworkAvatar(
            url: video.summary.authorAvatarUrl,
            name: video.summary.author,
            radius: 21,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.summary.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  '${compactCount(author?.followerCount)}粉丝 · '
                  '${compactCount(author?.likeCount)}获赞',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            // Large text keeps the statistics legible without squeezing the button.
            if (button == null) return identity;
            if (constraints.maxWidth < 300 ||
                MediaQuery.textScalerOf(context).scale(14) > 20) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  identity,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: button),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: identity),
                const SizedBox(width: 8),
                button,
              ],
            );
          },
        ),
        if (state?.message case final String message)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(message, style: theme.textTheme.bodySmall),
                ),
                if (state != null && !state.signedIn && provider != null)
                  IconButton(
                    tooltip: '刷新 UP 主信息',
                    onPressed: state.loading
                        ? null
                        : () => ref.read(provider.notifier).refresh(),
                    icon: const Icon(Icons.refresh, size: 18),
                  ),
              ],
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
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    return CheckboxListTile(
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
                    );
                  },
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
