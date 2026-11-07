import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/user.dart';
import '../../../shared/ui/network_avatar.dart';
import '../domain/profile_repository.dart';

/// A presentation-only card: no relationship reads, timers or retained state.
class ProfileUserCard extends StatelessWidget {
  const ProfileUserCard({
    super.key,
    required this.entry,
    this.onOpen,
    this.onManage,
  });

  final ProfileEntry entry;
  final ValueChanged<UserId>? onOpen;
  final ValueChanged<ProfileEntry>? onManage;

  static double heightFor(TextScaler scaler) =>
      math.max(76, 28 + scaler.scale(14) * 1.5 + scaler.scale(12) * 1.5 + 4);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = entry.userId;
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('profile-user-${entry.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: id?.isValid == true && onOpen != null
            ? () => onOpen!(id!)
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              NetworkAvatar(url: entry.coverUrl, name: entry.title, radius: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    if (entry.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        entry.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          height: 1.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onManage != null && id?.isValid == true)
                IconButton(
                  tooltip: '管理 ${entry.title}',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onManage!(entry),
                  icon: const Icon(Icons.more_horiz, size: 20),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cache layout just like the submission grid; scrolling does not replace its
/// delegate. Sliver children are released outside the viewport cache.
class ProfileUserGrid extends StatefulWidget {
  const ProfileUserGrid({
    super.key,
    required this.entries,
    this.onOpen,
    this.onManage,
  });
  final List<ProfileEntry> entries;
  final ValueChanged<UserId>? onOpen;
  final ValueChanged<ProfileEntry>? onManage;

  @override
  State<ProfileUserGrid> createState() => _ProfileUserGridState();
}

class _ProfileUserGridState extends State<ProfileUserGrid> {
  (double, TextScaler)? _layout;
  Widget? _grid;

  @override
  void didUpdateWidget(ProfileUserGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.entries, widget.entries) ||
        oldWidget.onOpen != widget.onOpen ||
        oldWidget.onManage != widget.onManage) {
      _grid = null;
    }
  }

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      final layout = (constraints.crossAxisExtent, scaler);
      if (_layout == layout && _grid != null) return _grid!;
      _layout = layout;
      final columns = (layout.$1 / math.max(260, scaler.scale(260)))
          .floor()
          .clamp(1, 6);
      return _grid = SliverGrid.builder(
        itemCount: widget.entries.length,
        addAutomaticKeepAlives: false,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: ProfileUserCard.heightFor(scaler),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        itemBuilder: (context, index) => ProfileUserCard(
          key: ValueKey(widget.entries[index].id),
          entry: widget.entries[index],
          onOpen: widget.onOpen,
          onManage: widget.onManage,
        ),
      );
    },
  );
}
