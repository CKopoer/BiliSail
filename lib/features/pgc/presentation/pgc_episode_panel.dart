import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/ui/smooth_scroll_behavior.dart';
import '../domain/pgc_repository.dart';

/// A bounded episode viewport keeps long seasons cheap to lay out.
final class PgcEpisodePanel extends StatefulWidget {
  const PgcEpisodePanel({
    super.key,
    required this.season,
    required this.selected,
    required this.onSelect,
  });

  final PgcSeason season;
  final PgcEpisode? selected;
  final ValueChanged<PgcEpisode> onSelect;

  @override
  State<PgcEpisodePanel> createState() => _PgcEpisodePanelState();
}

final class _PgcEpisodePanelState extends State<PgcEpisodePanel> {
  static const _listRowHeight = 44.0;
  static const _gridRowHeight = 62.0;

  final ScrollController _scroll = ScrollController();
  final ScrollController _groupScroll = ScrollController();
  late String _group;
  bool _descending = false;
  bool _grid = false;
  bool _focusSelected = true;
  bool _scrollToStart = false;
  bool _groupHovered = false;

  @override
  void initState() {
    super.initState();
    _group = _section(widget.selected);
  }

  @override
  void didUpdateWidget(covariant PgcEpisodePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.season.id != widget.season.id ||
        oldWidget.selected?.id != widget.selected?.id) {
      _group = _section(widget.selected);
      _focusSelected = true;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _groupScroll.dispose();
    super.dispose();
  }

  static String _section(PgcEpisode? episode) {
    final title = episode?.sectionTitle?.trim();
    return title == null || title.isEmpty ? '正片' : title;
  }

  void _queueScroll(
    int selectedIndex,
    double listRowHeight,
    double gridRowHeight,
  ) {
    if (!_focusSelected && !_scrollToStart) return;
    final focusSelected = _focusSelected;
    _focusSelected = false;
    _scrollToStart = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      final row = _grid ? selectedIndex ~/ 3 : selectedIndex;
      final rowHeight = _grid ? gridRowHeight + 5 : listRowHeight;
      final target = focusSelected && selectedIndex >= 0
          ? row * rowHeight - (position.viewportDimension - rowHeight) / 2
          : 0.0;
      _scroll.jumpTo(target.clamp(0.0, position.maxScrollExtent));
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final listRowHeight = math.max(
      _listRowHeight,
      scaler.scale(_listRowHeight),
    );
    final gridRowHeight = math.max(
      _gridRowHeight,
      scaler.scale(_gridRowHeight),
    );
    final groupHeight = math.max(42.0, scaler.scale(42));
    final groups = <String, List<PgcEpisode>>{};
    for (final episode in widget.season.episodes) {
      (groups[_section(episode)] ??= []).add(episode);
    }
    if (groups.isNotEmpty && !groups.containsKey(_group)) {
      _group = groups.keys.first;
    }
    final entries = [...?groups[_group]];
    final episodes = _descending ? entries.reversed.toList() : entries;
    final selectedIndex = episodes.indexWhere(
      (episode) => episode.id == widget.selected?.id,
    );
    _queueScroll(selectedIndex, listRowHeight, gridRowHeight);
    final currentIndex = widget.season.episodes.indexWhere(
      (episode) => episode.id == widget.selected?.id,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '选集 (${currentIndex < 0 ? 0 : currentIndex + 1}/${widget.season.episodes.length})',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  key: const ValueKey('pgc-episode-view'),
                  tooltip: _grid ? '切换为列表' : '切换为网格',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    _grid = !_grid;
                    _focusSelected = true;
                  }),
                  icon: Icon(
                    _grid ? Icons.view_list : Icons.grid_view,
                    size: 19,
                  ),
                ),
                IconButton(
                  key: const ValueKey('pgc-episode-order'),
                  tooltip: _descending ? '切换为正序' : '切换为倒序',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    _descending = !_descending;
                    _focusSelected = true;
                  }),
                  icon: Icon(
                    _descending ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 19,
                  ),
                ),
              ],
            ),
            if (groups.isNotEmpty) ...[
              SizedBox(
                height: groupHeight,
                child: MouseRegion(
                  key: const ValueKey('pgc-section-tabs'),
                  onEnter: (_) => setState(() => _groupHovered = true),
                  onExit: (_) => setState(() => _groupHovered = false),
                  child: ScrollConfiguration(
                    behavior: const SmoothScrollBehavior(
                      horizontalMouseWheel: true,
                    ).copyWith(scrollbars: false),
                    child: Scrollbar(
                      key: const ValueKey('pgc-section-scrollbar'),
                      controller: _groupScroll,
                      thumbVisibility: _groupHovered,
                      interactive: true,
                      thickness: 3,
                      radius: const Radius.circular(2),
                      scrollbarOrientation: ScrollbarOrientation.bottom,
                      child: ListView(
                        key: const ValueKey('pgc-section-list'),
                        controller: _groupScroll,
                        primary: false,
                        padding: const EdgeInsets.only(bottom: 6),
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final entry in groups.entries)
                            TextButton(
                              key: ValueKey('pgc-section-${entry.key}'),
                              onPressed: () => setState(() {
                                _group = entry.key;
                                _scrollToStart = true;
                                _focusSelected = false;
                              }),
                              style: TextButton.styleFrom(
                                foregroundColor: _group == entry.key
                                    ? colors.primary
                                    : colors.onSurface,
                              ),
                              child: Text(entry.key),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 232,
                child: _grid
                    ? GridView.builder(
                        key: const ValueKey('pgc-episode-grid'),
                        controller: _scroll,
                        itemCount: episodes.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisExtent: gridRowHeight,
                          crossAxisSpacing: 5,
                          mainAxisSpacing: 5,
                        ),
                        itemBuilder: (context, index) =>
                            _tile(context, episodes[index], grid: true),
                      )
                    : ListView.builder(
                        key: const ValueKey('pgc-episode-list'),
                        controller: _scroll,
                        itemExtent: listRowHeight,
                        itemCount: episodes.length,
                        itemBuilder: (context, index) =>
                            _tile(context, episodes[index], grid: false),
                      ),
              ),
            ] else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('暂无剧集'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, PgcEpisode episode, {required bool grid}) {
    final colors = Theme.of(context).colorScheme;
    final selected = episode.id == widget.selected?.id;
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? colors.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          key: ValueKey('pgc-episode-${episode.episodeId}'),
          borderRadius: BorderRadius.circular(4),
          onTap: () => widget.onSelect(episode),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: grid ? 5 : 7),
            child: Row(
              children: [
                if (!episode.playable) ...[
                  const Icon(Icons.lock_outline, size: 14),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    episode.displayTitle,
                    maxLines: grid ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: selected ? colors.primary : colors.onSurface,
                      fontWeight: selected
                          ? FontWeight.w700
                          : FontWeight.normal,
                    ),
                  ),
                ),
                if (!grid && episode.badge?.isNotEmpty == true) ...[
                  const SizedBox(width: 5),
                  Text(
                    episode.badge ?? '',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
