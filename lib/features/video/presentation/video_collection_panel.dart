import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/video.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../shared/ui/scroll_boundary_handoff.dart';
import '../../../shared/ui/video_card.dart';
import '../application/collection_subscription_controller.dart';
import '../application/video_controller.dart';
import '../domain/collection_subscription_repository.dart';

typedef _CollectionRow = ({
  VideoCollectionEntry entry,
  VideoPart? part,
  bool heading,
});

/// One bounded card owns the collection heading, selection and nested parts.
final class VideoCollectionPanel extends ConsumerStatefulWidget {
  const VideoCollectionPanel({
    super.key,
    required this.video,
    required this.selected,
    required this.onSelectPart,
    this.onLogin,
    this.onOpenVideoPart,
    this.playbackReversed = false,
    this.onTogglePlaybackOrder,
    this.displayReversed = false,
    this.onToggleDisplayOrder,
  });
  final VideoDetail video;
  final VideoPart selected;
  final ValueChanged<VideoPart> onSelectPart;
  final VoidCallback? onLogin;
  final void Function(VideoId, String?)? onOpenVideoPart;
  final bool playbackReversed;
  final VoidCallback? onTogglePlaybackOrder;
  final bool displayReversed;
  final VoidCallback? onToggleDisplayOrder;

  @override
  ConsumerState<VideoCollectionPanel> createState() =>
      _VideoCollectionPanelState();
}

final class _VideoCollectionPanelState
    extends ConsumerState<VideoCollectionPanel> {
  bool _expanded = true;
  bool _partsExpanded = true;
  final Set<VideoId> _expandedEntries = {};
  final ScrollController _scroll = ScrollController();
  List<_CollectionRow> _rows = const [];

  double get _rowHeight =>
      40 *
      (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
        1.0,
        double.infinity,
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleScrollToCurrent();
  }

  @override
  void didUpdateWidget(covariant VideoCollectionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.summary.id != widget.video.summary.id ||
        oldWidget.selected.cid != widget.selected.cid ||
        oldWidget.displayReversed != widget.displayReversed) {
      _scheduleScrollToCurrent();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collection = widget.video.collection;
    final subscriptionTarget =
        collection == null || !widget.video.summary.id.isValid
        ? null
        : CollectionSubscriptionTarget(
            collectionId: CollectionId(collection.id),
            videoId: widget.video.summary.id,
            aid: widget.video.aid,
          );
    final subscriptionState = subscriptionTarget == null
        ? null
        : ref.watch(
            collectionSubscriptionControllerProvider(subscriptionTarget),
          );
    final theme = Theme.of(context);
    final index =
        collection?.entries.indexWhere(
          (entry) => entry.id == widget.video.summary.id,
        ) ??
        -1;
    final standaloneParts = widget.video.parts.length > 1 && index < 0;
    _rows = _expanded ? _collectionRows() : const [];
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (standaloneParts) ...[
            _heading(
              '视频选集 · ${widget.video.parts.length} P',
              _partsExpanded,
              () => setState(() => _partsExpanded = !_partsExpanded),
            ),
            if (_partsExpanded)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 224),
                child: ScrollBoundaryHandoff(
                  child: ListView.builder(
                    primary: false,
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: widget.video.parts.length,
                    itemBuilder: (_, index) => _partRow(
                      widget.video.summary.id,
                      widget.video.parts[index],
                    ),
                  ),
                ),
              ),
          ],
          if (collection != null) ...[
            _heading(
              collection.title,
              _expanded,
              () => setState(() => _expanded = !_expanded),
              count: index >= 0
                  ? '${index + 1}/${collection.entries.length}'
                  : '${collection.entries.length} 个视频',
              playCount: collection.playCount,
              trailing: subscriptionTarget == null || subscriptionState == null
                  ? null
                  : _subscriptionButton(subscriptionTarget, subscriptionState),
            ),
            if (subscriptionState?.message case final String message)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            if (_expanded) ...[
              _toolbar(index >= 0),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 224),
                child: ScrollBoundaryHandoff(
                  child: Scrollbar(
                    controller: _scroll,
                    child: ListView.builder(
                      controller: _scroll,
                      primary: false,
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 4),
                      itemExtent: _rowHeight,
                      itemCount: _rows.length,
                      itemBuilder: (_, index) {
                        final row = _rows[index];
                        if (row.heading) return _entry(row.entry);
                        if (row.part case final part?) {
                          return _partRow(row.entry.id, part, nested: true);
                        }
                        return _partsStatus(row.entry);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  List<_CollectionRow> _collectionRows() {
    final entries = widget.video.collection?.entries ?? const [];
    final rows = <_CollectionRow>[];
    for (final entry in widget.displayReversed ? entries.reversed : entries) {
      rows.add((entry: entry, part: null, heading: true));
      if (!_expandedEntries.contains(entry.id)) continue;
      var parts = entry.id == widget.video.summary.id
          ? widget.video.parts
          : entry.parts;
      if (parts.isEmpty) {
        parts =
            ref.watch(videoDetailProvider(entry.id)).asData?.value.parts ??
            const [];
      }
      if (parts.isEmpty) {
        rows.add((entry: entry, part: null, heading: false));
      } else {
        for (final part in parts) {
          rows.add((entry: entry, part: part, heading: false));
        }
      }
    }
    return rows;
  }

  Widget _toolbar(bool hasCurrent) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
      child: Wrap(
        spacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _toolButton('跳至顶部', Icons.vertical_align_top, () => _scrollTo(0)),
          _toolButton(
            '跳至底部',
            Icons.vertical_align_bottom,
            () => _scrollTo(
              _scroll.hasClients ? _scroll.position.maxScrollExtent : 0,
            ),
          ),
          _toolButton(
            '跳至当前',
            Icons.my_location,
            hasCurrent ? _jumpToCurrent : null,
          ),
          _toolButton(
            widget.playbackReversed ? '正序播放' : '倒序播放',
            Icons.playlist_play,
            widget.onTogglePlaybackOrder,
            selected: widget.playbackReversed,
          ),
          Tooltip(
            message: widget.displayReversed ? '顺序' : '倒序',
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurfaceVariant,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              onPressed: widget.onToggleDisplayOrder,
              icon: const Icon(Icons.swap_vert, size: 18),
              label: Text(widget.displayReversed ? '倒序' : '顺序'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolButton(
    String tooltip,
    IconData icon,
    VoidCallback? onPressed, {
    bool selected = false,
  }) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    isSelected: selected,
    icon: Icon(icon, size: 18),
    style: IconButton.styleFrom(
      foregroundColor: selected
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.onSurfaceVariant,
      backgroundColor: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      minimumSize: const Size(36, 36),
      padding: const EdgeInsets.all(8),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
  );

  void _scrollTo(double offset) {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
  }

  void _jumpToCurrent() {
    if (widget.video.parts.length > 1) {
      setState(() => _expandedEntries.add(widget.video.summary.id));
    }
    _scheduleScrollToCurrent();
  }

  void _scheduleScrollToCurrent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_expanded) return;
      final partIndex = _rows.indexWhere(
        (row) =>
            row.entry.id == widget.video.summary.id &&
            row.part?.cid == widget.selected.cid,
      );
      final index = partIndex >= 0
          ? partIndex
          : _rows.indexWhere((row) => row.entry.id == widget.video.summary.id);
      if (index >= 0) _scrollTo(index * _rowHeight);
    });
  }

  Widget _heading(
    String title,
    bool expanded,
    VoidCallback onTap, {
    String? count,
    int? playCount,
    Widget? trailing,
  }) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    if (count != null)
                      Text(
                        '($count)',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
                if (playCount != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${compactCount(playCount)}播放',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing,
            const SizedBox(width: 4),
          ],
          Icon(
            expanded ? Icons.expand_less : Icons.expand_more,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    ),
  );

  Widget _subscriptionButton(
    CollectionSubscriptionTarget target,
    CollectionSubscriptionState state,
  ) {
    final theme = Theme.of(context);
    final subscribed = state.subscribed == true;
    final needsRefresh =
        state.uncertain ||
        state.subscribed == null && state.signedIn && !state.loading;
    final foreground = subscribed || needsRefresh
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.primary;
    final label = state.busy
        ? '处理中'
        : state.loading
        ? '读取中'
        : needsRefresh
        ? '刷新状态'
        : subscribed
        ? '已订阅'
        : '订阅合集';
    final tooltip = needsRefresh
        ? '刷新合集订阅状态'
        : subscribed
        ? '取消订阅合集'
        : '订阅合集';
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          side: BorderSide(color: foreground),
          minimumSize: const Size(0, 27),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
        onPressed: state.busy || state.loading
            ? null
            : !state.signedIn
            ? () {
                if (widget.onLogin case final onLogin?) {
                  onLogin();
                } else {
                  showAppNotice(context, '请先登录后操作');
                }
              }
            : needsRefresh
            ? () => ref
                  .read(
                    collectionSubscriptionControllerProvider(target).notifier,
                  )
                  .refresh()
            : () async {
                final changed = await ref
                    .read(
                      collectionSubscriptionControllerProvider(target).notifier,
                    )
                    .toggle();
                if (mounted &&
                    changed &&
                    widget.video.collection?.id == target.collectionId.value &&
                    widget.video.summary.id == target.videoId &&
                    widget.video.aid == target.aid) {
                  showAppNotice(context, subscribed ? '已取消订阅' : '已订阅合集');
                }
              },
        child: state.busy || state.loading
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: foreground,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(label),
                ],
              )
            : Text(label),
      ),
    );
  }

  Widget _entry(VideoCollectionEntry entry) {
    final current = entry.id == widget.video.summary.id;
    final parts = current ? widget.video.parts : entry.parts;
    final expanded = _expandedEntries.contains(entry.id);
    final duration =
        entry.duration ??
        (parts.isEmpty
            ? null
            : parts.fold<Duration>(
                Duration.zero,
                (sum, part) => sum + part.duration,
              ));
    return _row(
      title: entry.title,
      selected: current,
      duration: duration,
      onTap: () => _open(entry.id, parts.firstOrNull),
      trailing: parts.length != 1
          ? IconButton(
              tooltip: expanded ? '收起分 P' : '展开分 P',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: 16,
              ),
              onPressed: () => setState(() {
                if (!_expandedEntries.remove(entry.id)) {
                  _expandedEntries.add(entry.id);
                }
              }),
            )
          : null,
    );
  }

  Widget _partsStatus(VideoCollectionEntry entry) => ref
      .watch(videoDetailProvider(entry.id))
      .when(
        loading: () => const Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: LinearProgressIndicator()),
        ),
        error: (error, _) => _row(
          title: error is AppFailure ? error.message : '分 P 加载失败',
          selected: false,
          nested: true,
          onTap: () => ref.invalidate(videoDetailProvider(entry.id)),
          trailing: const Icon(Icons.refresh, size: 16),
        ),
        data: (_) => const Center(child: Text('暂无分 P')),
      );

  Widget _partRow(VideoId id, VideoPart part, {bool nested = false}) => _row(
    title: nested ? 'P${part.page} ${part.title}' : part.title,
    selected: id == widget.video.summary.id && part.cid == widget.selected.cid,
    duration: part.duration,
    nested: nested,
    onTap: () => _open(id, part),
  );

  Widget _row({
    required String title,
    required bool selected,
    required VoidCallback onTap,
    Duration? duration,
    Widget? trailing,
    bool nested = false,
  }) {
    final theme = Theme.of(context);
    return SizedBox(
      height: _rowHeight,
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Semantics(
            selected: selected,
            button: true,
            child: Padding(
              padding: EdgeInsets.fromLTRB(nested ? 28 : 12, 4, 10, 4),
              child: Row(
                children: [
                  if (selected) ...[
                    Icon(
                      Icons.equalizer,
                      color: theme.colorScheme.primary,
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: selected ? theme.colorScheme.primary : null,
                      ),
                    ),
                  ),
                  if (duration != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      durationLabel(duration),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _open(VideoId id, VideoPart? part) {
    if (id == widget.video.summary.id && part != null) {
      if (part.cid != widget.selected.cid) widget.onSelectPart(part);
    } else {
      widget.onOpenVideoPart?.call(id, part?.cid);
    }
  }
}
