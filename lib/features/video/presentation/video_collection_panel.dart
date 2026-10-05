import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/video.dart';
import '../../../shared/ui/state_view.dart';
import '../../../shared/ui/video_card.dart';
import '../application/video_controller.dart';

/// One bounded card owns the collection heading, selection and nested parts.
final class VideoCollectionPanel extends ConsumerStatefulWidget {
  const VideoCollectionPanel({
    super.key,
    required this.video,
    required this.selected,
    required this.onSelectPart,
    this.onOpenVideoPart,
  });
  final VideoDetail video;
  final VideoPart selected;
  final ValueChanged<VideoPart> onSelectPart;
  final void Function(VideoId, String?)? onOpenVideoPart;

  @override
  ConsumerState<VideoCollectionPanel> createState() =>
      _VideoCollectionPanelState();
}

final class _VideoCollectionPanelState
    extends ConsumerState<VideoCollectionPanel> {
  bool _expanded = true;
  bool _partsExpanded = true;
  final Set<VideoId> _expandedEntries = {};
  late final ScrollController _scroll;
  bool _scrollInitialized = false;

  double get _rowHeight =>
      40 *
      (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
        1.0,
        double.infinity,
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scrollInitialized) return;
    _scrollInitialized = true;
    final index =
        widget.video.collection?.entries.indexWhere(
          (entry) => entry.id == widget.video.summary.id,
        ) ??
        -1;
    _scroll = ScrollController(
      initialScrollOffset: index > 0 ? index * _rowHeight : 0,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collection = widget.video.collection;
    final theme = Theme.of(context);
    final index =
        collection?.entries.indexWhere(
          (entry) => entry.id == widget.video.summary.id,
        ) ??
        -1;
    final standaloneParts = widget.video.parts.length > 1 && index < 0;
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
            ),
            if (_expanded)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 224),
                child: Scrollbar(
                  controller: _scroll,
                  child: ListView.builder(
                    controller: _scroll,
                    primary: false,
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 4),
                    itemCount: collection.entries.length,
                    itemBuilder: (_, index) =>
                        _entry(collection.entries[index]),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _heading(
    String title,
    bool expanded,
    VoidCallback onTap, {
    String? count,
    int? playCount,
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
          Icon(
            expanded ? Icons.expand_less : Icons.expand_more,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    ),
  );

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
    return Column(
      children: [
        _row(
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
        ),
        if (expanded) ...[
          if (parts.isNotEmpty)
            for (final part in parts) _partRow(entry.id, part, nested: true)
          else
            ref
                .watch(videoDetailProvider(entry.id))
                .when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(12),
                    child: LinearProgressIndicator(),
                  ),
                  error: (error, _) => StateView.error(
                    message: error is AppFailure ? error.message : '分 P 加载失败',
                    onAction: () =>
                        ref.invalidate(videoDetailProvider(entry.id)),
                  ),
                  data: (video) => Column(
                    children: [
                      for (final part in video.parts)
                        _partRow(entry.id, part, nested: true),
                    ],
                  ),
                ),
        ],
      ],
    );
  }

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
