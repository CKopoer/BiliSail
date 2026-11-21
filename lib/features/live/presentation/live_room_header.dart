import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/user.dart';
import '../../../shared/ui/network_avatar.dart';
import '../../../shared/ui/workspace_link.dart';
import '../application/live_controller.dart';
import '../domain/live_room.dart';

class LiveRoomHeader extends StatefulWidget {
  const LiveRoomHeader({
    super.key,
    required this.room,
    required this.requestedId,
    required this.compact,
    required this.refresh,
    this.onOpenUser,
  });

  final LiveRoom room;
  final RoomId requestedId;
  final bool compact;
  final Widget refresh;
  final ValueChanged<UserId>? onOpenUser;

  @override
  State<LiveRoomHeader> createState() => _LiveRoomHeaderState();
}

class _LiveRoomHeaderState extends State<LiveRoomHeader> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final compact = widget.compact;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final anchor = room.anchorId;
    final open = anchor != null && anchor.isValid && widget.onOpenUser != null
        ? () => widget.onOpenUser?.call(anchor)
        : null;
    final provider = liveControllerProvider(widget.requestedId);
    final viewer = Consumer(
      builder: (context, ref, _) {
        final value = ref.watch(provider.select((s) => s.viewerCountText));
        return Text(
          value == null
              ? (compact ? '在看人数未知' : '在看人数暂无数据')
              : compact
              ? '$value 人在看'
              : '当前$value人在看',
          key: const ValueKey('live-viewer-count'),
          maxLines: compact ? 1 : null,
          overflow: compact ? TextOverflow.ellipsis : null,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        );
      },
    );
    final watched = Consumer(
      builder: (context, ref, _) {
        final value = ref.watch(provider.select((s) => s.watchedCountText));
        return Text(
          value == null ? '看过人数暂无数据' : '$value人看过',
          key: const ValueKey('live-watched-count'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        );
      },
    );
    return SingleChildScrollView(
      primary: false,
      child: Padding(
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 10)
            : const EdgeInsets.fromLTRB(14, 10, 14, 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: compact ? 44 : 0),
              child: Row(
                children: [
                  InkWell(
                    key: const ValueKey('live-anchor-avatar'),
                    onTap: open,
                    onTertiaryTapUp: WorkspaceLinkScope.middleClick(
                      context,
                      open,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    child: NetworkAvatar(
                      url: room.anchorAvatarUrl,
                      name: room.anchorName,
                      radius: compact ? 14 : 18,
                    ),
                  ),
                  SizedBox(width: compact ? 7 : 9),
                  Expanded(
                    flex: compact ? 2 : 1,
                    child: InkWell(
                      key: const ValueKey('live-anchor-name'),
                      onTap: open,
                      onTertiaryTapUp: WorkspaceLinkScope.middleClick(
                        context,
                        open,
                      ),
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
                  if (compact) ...[
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Semantics(
                            label: room.isLive ? '直播中' : '未开播',
                            child: Icon(
                              Icons.circle,
                              size: 6,
                              color: room.isLive
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(child: viewer),
                        ],
                      ),
                    ),
                    IconButton(
                      style: IconButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      tooltip: _expanded ? '收起房间详情' : '展开房间详情',
                      onPressed: () => setState(() => _expanded = !_expanded),
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 44,
                      ),
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                      ),
                    ),
                  ] else
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [viewer, const SizedBox(height: 2), watched],
                      ),
                    ),
                ],
              ),
            ),
            if (!compact || _expanded) ...[
              if (!compact) const SizedBox(height: 8),
              Text(
                room.title,
                style: compact
                    ? theme.textTheme.titleSmall
                    : theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 7),
              DefaultTextStyle(
                style: theme.textTheme.bodySmall ?? const TextStyle(),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    if (!compact)
                      Text(
                        room.isLive ? '● 直播中' : '● 未开播',
                        style: TextStyle(
                          color: room.isLive
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    Text('房间号 ${room.id.value}'),
                    if (room.areaName.isNotEmpty) Text('分区 ${room.areaName}'),
                    if (room.popularity case final count?)
                      Text('人气 ${_formatPopularity(count)}'),
                  ],
                ),
              ),
              if (compact)
                Row(
                  children: [
                    Expanded(child: watched),
                    widget.refresh,
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatPopularity(int count) {
    if (count < 10000) return count.toString();
    return '${(count / 10000).toStringAsFixed(1)}万';
  }
}
