import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/user.dart';
import '../../../shared/ui/content_section_tabs.dart';
import '../application/profile_controller.dart';

class ProfileFollowGroupsTabs extends ConsumerWidget {
  const ProfileFollowGroupsTabs({super.key, required this.id});

  final UserId id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (available, groups, selected, loading, message) = ref.watch(
      profileControllerProvider(id).select(
        (state) => (
          state.followGroupsAvailable,
          state.followGroups,
          state.followingGroupId,
          state.followGroupsLoading,
          state.followGroupsMessage,
        ),
      ),
    );
    if (!available) return const SizedBox.shrink();
    final controller = ref.read(profileControllerProvider(id).notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ContentSectionTabs<String>(
          entries: [
            ('all', '全部关注'),
            for (final group in groups ?? []) (group.id, group.name),
          ],
          value: selected ?? 'all',
          onSelected: (value) =>
              controller.selectFollowingGroup(value == 'all' ? null : value),
          itemKey: (value) => ValueKey('profile-follow-group-$value'),
          scrollKey: const PageStorageKey('profile-follow-groups-scroll'),
        ),
        if (loading) const LinearProgressIndicator(minHeight: 2),
        if (message != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('profile-follow-groups-retry'),
              onPressed: controller.loadFollowGroups,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(
                '$message，点击重试',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
    );
  }
}
