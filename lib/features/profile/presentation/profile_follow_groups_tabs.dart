import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/user.dart';
import '../../../shared/ui/content_section_tabs.dart';
import '../application/profile_controller.dart';

class ProfileFollowGroupsTabs extends ConsumerStatefulWidget {
  const ProfileFollowGroupsTabs({
    super.key,
    required this.id,
    this.active = true,
  });

  final UserId id;
  final bool active;

  @override
  ConsumerState<ProfileFollowGroupsTabs> createState() =>
      _ProfileFollowGroupsTabsState();
}

class _ProfileFollowGroupsTabsState
    extends ConsumerState<ProfileFollowGroupsTabs> {
  bool _visited = false;

  @override
  Widget build(BuildContext context) {
    if (widget.active) _visited = true;
    if (!_visited) return const SizedBox.shrink();
    final id = widget.id;
    final (available, groups, selected, loading, message, blacklist) = ref
        .watch(
          profileControllerProvider(id).select(
            (state) => (
              state.followGroupsAvailable,
              state.followGroups,
              state.followingGroupId,
              state.followGroupsLoading,
              state.followGroupsMessage,
              state.showBlacklist,
            ),
          ),
        );
    if (!available) return const SizedBox.shrink();
    final controller = ref.read(profileControllerProvider(id).notifier);
    // This strip belongs to the profile session, like the retained content
    // pages. Hide its layout/input/tickers while keeping its scroll state.
    return Visibility(
      visible: widget.active && !blacklist,
      maintainState: true,
      child: Column(
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
      ),
    );
  }
}
