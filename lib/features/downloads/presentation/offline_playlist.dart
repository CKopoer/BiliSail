import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../core/presentation/workspace_activity.dart';
import '../../../shared/ui/content_section_tabs.dart';
import '../../../shared/ui/playback_split_layout.dart';
import '../../../shared/ui/scroll_collapsing_header.dart';
import '../../../shared/ui/video_card.dart' show durationLabel;
import '../domain/download_models.dart';
import '../domain/offline_library.dart';
import 'download_local_cover.dart';
import 'downloads_screen.dart' show downloadQualityText, downloadCodecText;

class OfflineSummary extends StatelessWidget {
  const OfflineSummary({
    super.key,
    required this.task,
    required this.work,
    required this.expanded,
    required this.onToggle,
  });
  final DownloadTask task;
  final DownloadWork? work;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final item = task.item, theme = Theme.of(context);
    final duration = task.duration ?? item.part.duration;
    final description = work?.description.trim() ?? '';
    final part = item.displayPartTitle.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.video.title, style: theme.textTheme.titleLarge),
          if (part.isNotEmpty && part != item.video.title)
            Text(part, style: theme.textTheme.titleMedium),
          const SizedBox(height: 5),
          Tooltip(
            message:
                '${downloadCodecText(task.selection.codec)} · ${task.selection.output.label}',
            child: Text(
              [
                if (item.episodeId == null && item.video.author.isNotEmpty)
                  item.video.author,
                '本地',
                downloadQualityText(task.selection.quality),
                if (duration > Duration.zero) durationLabel(duration),
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LayoutBuilder(
                builder: (context, bounds) {
                  final style = theme.textTheme.bodyMedium!;
                  final measure = TextPainter(
                    text: TextSpan(text: description, style: style),
                    maxLines: 2,
                    textScaler: MediaQuery.textScalerOf(context),
                    textDirection: Directionality.of(context),
                  )..layout(maxWidth: bounds.maxWidth);
                  final clipped = measure.didExceedMaxLines;
                  measure.dispose();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        description,
                        maxLines: expanded ? null : 2,
                        overflow: expanded ? null : TextOverflow.ellipsis,
                        style: style,
                      ),
                      if (clipped)
                        TextButton(
                          onPressed: onToggle,
                          child: Text(expanded ? '收起简介' : '展开简介'),
                        ),
                    ],
                  );
                },
              ),
            ),
          for (final warning in task.warnings)
            Text('离线附属内容提示：$warning', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class OfflinePlaylist extends StatefulWidget {
  const OfflinePlaylist({
    super.key,
    required this.library,
    required this.onSelect,
    this.current,
    this.onBack,
    this.summary,
    this.coverProvider,
  });
  final OfflineLibrary library;
  final DownloadTask? current;
  final ValueChanged<DownloadTask> onSelect;
  final VoidCallback? onBack;
  final Widget? summary;
  final ImageProvider<Object>? Function(DownloadTask)? coverProvider;
  @override
  State<OfflinePlaylist> createState() => _OfflinePlaylistState();
}

typedef _Row = ({
  String title,
  OfflineGroup? group,
  OfflineEntry? entry,
  String? videoId,
});

class _OfflinePlaylistState extends State<OfflinePlaylist> {
  final _loader = DownloadCoverLoader();
  final _scroll = HeaderScrollController();
  final _header = GlobalKey();
  String? _expandedGroup;
  final _expandedVideos = <String>{};
  bool _library = false;
  double _libraryOffset = 0;
  String? _located;
  @override
  void didUpdateWidget(OfflinePlaylist oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current?.id != widget.current?.id) {
      _library = false;
      _expandedGroup = null;
      _libraryOffset = 0;
      _located = null;
      _expandedVideos.clear();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _loader.dispose();
    super.dispose();
  }

  Iterable<_Row> _members(OfflineGroup group) sync* {
    String? last;
    for (final entry in group.entries) {
      final item = entry.task.item;
      if (group.kind == OfflineGroupKind.season && entry.section != last) {
        last = entry.section;
        yield (title: last ?? '未分区', group: null, entry: null, videoId: null);
      }
      if (group.kind == OfflineGroupKind.collection) {
        final id = item.video.id.value;
        final multipart =
            group.multipartVideos.contains(id) ||
            (widget.library.workFor(item)?.partCount ?? 0) > 1 ||
            item.part.page > 1;
        if (multipart) {
          if (last != id) {
            yield (
              title: item.video.title,
              group: null,
              entry: null,
              videoId: id,
            );
          }
          last = id;
          if (!_expandedVideos.contains(id)) continue;
        }
      }
      yield (title: '', group: null, entry: entry, videoId: null);
    }
  }

  void _position(int index, double extent, String id) {
    if (_located == id) return;
    _located = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || _located != id || index < 0) {
        return;
      }
      final position = _scroll.position;
      final header = _header.currentContext?.size?.height ?? 0;
      final offset = header + extent * index;
      if (offset + extent > position.pixels + position.viewportDimension ||
          offset < position.pixels) {
        _scroll.jumpTo((offset - extent).clamp(0.0, position.maxScrollExtent));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _scroll.configure(context, active: WorkspaceActivity.isActive(context));
    final current = widget.current;
    final location = current == null ? null : widget.library.find(current.id);
    final group = location?.group;
    final showCurrent = group?.showCurrent ?? false;
    final all = !showCurrent || _library;
    if (!all && _located == null && current != null) {
      _expandedVideos.add(current.item.video.id.value);
    }
    final rows = <_Row>[];
    if (all) {
      for (final work in widget.library.groups) {
        rows.add((title: work.title, group: work, entry: null, videoId: null));
        if (_expandedGroup == work.id) rows.addAll(_members(work));
      }
    } else if (group != null) {
      rows.addAll(_members(group));
    }
    final extent = math.max(
      56.0,
      MediaQuery.textScalerOf(context).scale(15) * 3.7 + 4,
    );
    if (!all && current != null) {
      _position(
        rows.indexWhere(
          (r) => r.entry != null && identical(r.entry, location?.entry),
        ),
        extent,
        current.id,
      );
    }
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            key: _header,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.onBack != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text('返回下载'),
                  ),
                ),
              if (!PlaybackSplitLayout.infoBelowOf(context) &&
                  widget.summary != null)
                widget.summary!,
            ],
          ),
        ),
        PinnedHeaderSliver(
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: ContentSectionTabs<bool>(
              entries: [if (showCurrent) (false, group!.label), (true, '全部下载')],
              value: all,
              onSelected: (value) {
                if (value == all) return;
                if (all && _scroll.hasClients) _libraryOffset = _scroll.offset;
                setState(() {
                  _library = value;
                  _located = null;
                });
                if (value) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _library && _scroll.hasClients) {
                      _scroll.jumpTo(
                        _libraryOffset.clamp(
                          0.0,
                          _scroll.position.maxScrollExtent,
                        ),
                      );
                    }
                  });
                }
              },
            ),
          ),
        ),
        if (!all && group != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                '${group.kind == OfflineGroupKind.collection ? '${group.title} · ' : ''}已下载 ${group.count}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        SliverFixedExtentList.builder(
          itemExtent: extent,
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            if (row.group case final work?) {
              final task = work.entries.first.task,
                  image = widget.coverProvider?.call(task);
              const fallback = ColoredBox(
                color: Color(0x1967798a),
                child: Icon(Icons.video_library_outlined),
              );
              return ListTile(
                leading: SizedBox(
                  width: 54,
                  height: 34,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: image == null
                        ? fallback
                        : DownloadLocalCover(
                            loader: _loader,
                            image: image,
                            placeholder: fallback,
                          ),
                  ),
                ),
                title: Text(
                  work.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  work.count,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Icon(
                  _expandedGroup == work.id
                      ? Icons.expand_less
                      : Icons.expand_more,
                ),
                onTap: () => setState(
                  () => _expandedGroup = _expandedGroup == work.id
                      ? null
                      : work.id,
                ),
              );
            }
            if (row.videoId case final id?) {
              return ListTile(
                title: Text(
                  row.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Icon(
                  _expandedVideos.contains(id)
                      ? Icons.expand_less
                      : Icons.expand_more,
                ),
                onTap: () => setState(() {
                  if (!_expandedVideos.remove(id)) _expandedVideos.add(id);
                }),
              );
            }
            final entry = row.entry;
            if (entry == null) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    row.title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              );
            }
            final task = current == null
                ? entry.task
                : entry.preferred(current);
            final item = task.item, selected = task.id == current?.id;
            final parent = widget.library.find(task.id)!.group;
            final isPart =
                item.episodeId == null &&
                (parent.kind == OfflineGroupKind.video && parent.multipart ||
                    parent.multipartVideos.contains(item.video.id.value) ||
                    (widget.library.workFor(item)?.partCount ?? 0) > 1 ||
                    item.part.page > 1);
            final label = item.episodeId != null
                ? item.displayPartTitle
                : isPart
                ? 'P${item.part.page} · ${item.part.title}'
                : item.video.title;
            return Material(
              color: selected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Colors.transparent,
              child: ListTile(
                selected: selected,
                dense: true,
                leading: selected
                    ? const Icon(
                        Icons.play_arrow_rounded,
                        semanticLabel: '正在播放',
                      )
                    : null,
                title: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: entry.versions.length > 1
                    ? PopupMenuButton<DownloadTask>(
                        tooltip: '${entry.versions.length} 个本地版本',
                        onSelected: widget.onSelect,
                        itemBuilder: (_) => [
                          for (final version in entry.versions)
                            CheckedPopupMenuItem(
                              value: version,
                              checked: version.id == current?.id,
                              child: Text(
                                '${downloadQualityText(version.selection.quality)} · ${downloadCodecText(version.selection.codec)} · ${version.selection.output.label}',
                              ),
                            ),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Text('${entry.versions.length} 个版本'),
                        ),
                      )
                    : Text(
                        durationLabel(task.duration ?? item.part.duration),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                onTap: () => widget.onSelect(task),
              ),
            );
          },
        ),
      ],
    );
  }
}
