import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/ui/app_dialog.dart';
import '../../../core/presentation/workspace_activity.dart';
import '../../../shared/ui/scroll_collapsing_header.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/video_codec.dart';
import '../../../shared/ui/app_cover_image.dart';
import '../../../shared/ui/page_tab_style.dart';
import '../../../shared/ui/paging_tab_strip.dart';
import '../../../shared/ui/smooth_scroll_behavior.dart';
import '../../../shared/ui/state_view.dart';
import '../application/download_controller.dart';
import '../domain/download_models.dart';
import 'download_destination_dialog.dart';

String downloadByteText(int bytes) {
  if (bytes < 1024) return '$bytes B';
  var value = bytes.toDouble();
  for (final unit in ['KB', 'MB', 'GB', 'TB']) {
    value /= 1024;
    if (value < 1024 || unit == 'TB') {
      return '${value.toStringAsFixed(value < 10 ? 1 : 0)} $unit';
    }
  }
  return '$bytes B';
}

String downloadQualityText(int quality) => switch (quality) {
  127 => '8K',
  126 => '杜比视界',
  125 => 'HDR',
  120 => '4K',
  116 => '1080P 60帧',
  112 => '1080P+',
  80 => '1080P',
  74 => '720P 60帧',
  64 => '720P',
  32 => '480P',
  16 => '360P',
  _ => '画质 $quality',
};

String downloadCodecText(VideoCodecPreference codec) => switch (codec) {
  VideoCodecPreference.h264 => 'H.264',
  VideoCodecPreference.hevc => 'HEVC',
  VideoCodecPreference.av1 => 'AV1',
  VideoCodecPreference.dolbyVision => '杜比视界',
};

final class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({
    super.key,
    this.onPlay,
    this.onOpenDirectory,
    this.allowCustomDirectory = false,
    this.coverProvider,
    this.showHeading = true,
  });

  final ValueChanged<DownloadTask>? onPlay;
  final Future<void> Function(String)? onOpenDirectory;
  final bool allowCustomDirectory;
  final ImageProvider<Object>? Function(DownloadTask)? coverProvider;
  final bool showHeading;

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

final class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  final _searchController = TextEditingController();
  final _scrollController = HeaderScrollController();
  bool _completed = false;
  String _query = '';
  String _normalizedQuery = '';
  DownloadQueueStructure? _shownStructure;
  bool _shownCompleted = false;
  String _shownQuery = '';
  List<DownloadTaskEntry> _shown = const [];
  Map<String, int> _shownIndices = const {};

  List<DownloadTaskEntry> _shownEntries(DownloadQueueStructure structure) {
    if (identical(_shownStructure, structure) &&
        _shownCompleted == _completed &&
        _shownQuery == _normalizedQuery) {
      return _shown;
    }
    _shownStructure = structure;
    _shownCompleted = _completed;
    _shownQuery = _normalizedQuery;
    final group = _completed ? structure.completed : structure.queued;
    _shown = _normalizedQuery.isEmpty
        ? group
        : group
              .where((entry) => entry.searchText.contains(_normalizedQuery))
              .toList(growable: false);
    _shownIndices = {
      for (var index = 0; index < _shown.length; index++)
        _shown[index].id: index + 3,
    };
    return _shown;
  }

  DownloadTask? _task(String id) =>
      ref.read(downloadQueueIndexProvider).tasksById[id];

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on AppFailure catch (error) {
      if (mounted) _notice(error.message);
    } catch (_) {
      if (mounted) _notice('操作失败，请重试');
    }
  }

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _remove(DownloadTask task) async {
    final deleteFiles = await showAppDialog<bool>(
      context: context,
      builder: (_) => _DeleteTaskDialog(task: task),
    );
    if (deleteFiles == null || !mounted) return;
    await _run(
      () => ref
          .read(downloadControllerProvider.notifier)
          .remove(task.id, deleteFiles: deleteFiles),
    );
  }

  @override
  Widget build(BuildContext context) {
    _scrollController.configure(
      context,
      active: WorkspaceActivity.isActive(context),
    );
    final (initialized, failure) = ref.watch(
      downloadControllerProvider.select(
        (state) => (state.initialized, state.failure),
      ),
    );
    final structure = ref.watch(
      downloadQueueIndexProvider.select((index) => index.structure),
    );
    final controller = ref.read(downloadControllerProvider.notifier);
    final shown = _shownEntries(structure);
    final activeCount = structure.activeCount;
    final resumableCount = structure.resumableCount;

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 600;
            final actions = [
              IconButton(
                tooltip: '刷新下载',
                onPressed: () => _run(controller.refresh),
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                tooltip: '下载设置',
                onPressed: () => showAppDialog<void>(
                  context: context,
                  builder: (_) => _DownloadSettingsDialog(
                    preferences: ref
                        .read(downloadControllerProvider)
                        .preferences,
                    allowCustomDirectory: widget.allowCustomDirectory,
                  ),
                ),
                icon: const Icon(Icons.settings_outlined),
              ),
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.showHeading || !compact)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: widget.showHeading
                              ? Text('下载', style: theme.textTheme.titleLarge)
                              : const SizedBox.shrink(),
                        ),
                        if (!compact) ...actions,
                      ],
                    ),
                  ),
                SizedBox(
                  height: PageTabStyle.barHeight,
                  child: Row(
                    children: [
                      Expanded(
                        child: ScrollConfiguration(
                          behavior: const SmoothScrollBehavior(
                            horizontalMouseWheel: true,
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: PagingTabStrip<bool>(
                              tabs: const [false, true],
                              value: _completed,
                              onSelected: (value) =>
                                  setState(() => _completed = value),
                              buttonStyle: PageTabStyle.buttonStyle(context),
                              labelBuilder: (context, completedTab) => Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  PageTabStyle.label(
                                    completedTab ? '已完成' : '队列',
                                    icon: completedTab
                                        ? Icons.download_done_rounded
                                        : Icons.downloading_rounded,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${completedTab ? structure.completed.length : structure.queued.length}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (compact) ...[...actions, const SizedBox(width: 12)],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 72),
            itemCount: shown.length + 3,
            findChildIndexCallback: (key) => switch (key) {
              ValueKey<int>(:final value) => value,
              ValueKey<String>(:final value) => _shownIndices[value],
              _ => null,
            },
            itemBuilder: (context, index) {
              if (index == 0) {
                return LayoutBuilder(
                  key: const ValueKey(0),
                  builder: (context, constraints) {
                    final search = ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (text) => setState(() {
                          _query = text;
                          _normalizedQuery = text.trim().toLowerCase();
                        }),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search_rounded, size: 20),
                          hintText: '搜索标题或分集',
                        ),
                      ),
                    );
                    final actions = Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        OutlinedButton.icon(
                          onPressed: activeCount == 0
                              ? null
                              : () => _run(controller.pauseAll),
                          icon: const Icon(Icons.pause_rounded, size: 18),
                          label: const Text('全部暂停'),
                        ),
                        OutlinedButton.icon(
                          onPressed: resumableCount == 0
                              ? null
                              : () => _run(controller.resumeAll),
                          icon: const Icon(Icons.play_arrow_rounded, size: 18),
                          label: const Text('全部继续'),
                        ),
                      ],
                    );
                    final textScale =
                        MediaQuery.textScalerOf(context).scale(14) / 14;
                    if (constraints.maxWidth >= 720 * textScale) {
                      return Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: search,
                            ),
                          ),
                          const SizedBox(width: 16),
                          actions,
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(alignment: Alignment.centerLeft, child: search),
                        const SizedBox(height: 8),
                        actions,
                      ],
                    );
                  },
                );
              }
              if (index == 1) {
                return const _DownloadTransferredLabel(key: ValueKey(1));
              }
              if (index == 2) {
                return Column(
                  key: const ValueKey(2),
                  children: [
                    if (!initialized)
                      const SizedBox(height: 260, child: StateView.loading())
                    else if (failure != null)
                      SizedBox(
                        height: 180,
                        child: StateView.error(
                          message: failure.message,
                          onAction: () => _run(controller.refresh),
                        ),
                      ),
                    if (initialized && shown.isEmpty)
                      SizedBox(
                        height: 240,
                        child: StateView.empty(
                          message: _query.isNotEmpty
                              ? '没有匹配的下载任务'
                              : _completed
                              ? '还没有已完成的下载'
                              : '还没有下载任务',
                          icon: Icons.download_outlined,
                        ),
                      ),
                  ],
                );
              }
              final id = shown[index - 3].id;
              return Padding(
                key: ValueKey(id),
                padding: const EdgeInsets.only(bottom: 12),
                child: _DownloadTaskRow(
                  id: id,
                  onPause: () => _run(() => controller.pause(id)),
                  onResume: () => _run(() => controller.resume(id)),
                  onRemove: () {
                    final task = _task(id);
                    if (task != null) _remove(task);
                  },
                  onPlay: widget.onPlay == null
                      ? null
                      : () {
                          final task = _task(id);
                          if (task != null) widget.onPlay?.call(task);
                        },
                  onOpenDirectory: widget.onOpenDirectory == null
                      ? null
                      : () => _run(() async {
                          final task = _task(id);
                          if (task != null) {
                            await widget.onOpenDirectory?.call(task.directory);
                          }
                        }),
                  coverProvider: widget.coverProvider,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

final class _DownloadTransferredLabel extends ConsumerWidget {
  const _DownloadTransferredLabel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transferred = ref.watch(
      downloadQueueIndexProvider.select((index) => index.transferredBytes),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 16),
      child: Text(
        '已传输 ${downloadByteText(transferred)}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

final class _DownloadTaskRow extends ConsumerWidget {
  const _DownloadTaskRow({
    required this.id,
    required this.onPause,
    required this.onResume,
    required this.onRemove,
    this.onPlay,
    this.onOpenDirectory,
    this.coverProvider,
  });

  final String id;
  final VoidCallback onPause, onResume, onRemove;
  final VoidCallback? onPlay, onOpenDirectory;
  final ImageProvider<Object>? Function(DownloadTask)? coverProvider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref.watch(
      downloadQueueIndexProvider.select((index) => index.tasksById[id]),
    );
    if (task == null) return const SizedBox.shrink();
    return _DownloadTaskCard(
      task: task,
      onPause: onPause,
      onResume: onResume,
      onRemove: onRemove,
      onPlay: onPlay,
      onOpenDirectory: onOpenDirectory,
      coverProvider: coverProvider,
    );
  }
}

final class _DownloadTaskCard extends StatelessWidget {
  const _DownloadTaskCard({
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onRemove,
    this.onPlay,
    this.onOpenDirectory,
    this.coverProvider,
  });
  final DownloadTask task;
  final VoidCallback onPause, onResume, onRemove;
  final VoidCallback? onPlay, onOpenDirectory;
  final ImageProvider<Object>? Function(DownloadTask)? coverProvider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final completed = task.status == DownloadStatus.completed;
    final status = switch (task.status) {
      DownloadStatus.queued => '等待下载',
      DownloadStatus.resolving => '解析中',
      DownloadStatus.downloading => '下载中',
      DownloadStatus.verifying => '正在保存',
      DownloadStatus.muxing => '合并中',
      DownloadStatus.paused => '已暂停',
      DownloadStatus.failed => '下载失败',
      DownloadStatus.completed => '已完成',
    };
    final statusIcon = switch (task.status) {
      DownloadStatus.queued => Icons.schedule_rounded,
      DownloadStatus.resolving => Icons.link_rounded,
      DownloadStatus.downloading => Icons.downloading_rounded,
      DownloadStatus.verifying => Icons.fact_check_outlined,
      DownloadStatus.muxing => Icons.merge_rounded,
      DownloadStatus.paused => Icons.pause_rounded,
      DownloadStatus.failed => Icons.error_outline_rounded,
      DownloadStatus.completed => Icons.check_circle_outline_rounded,
    };
    final statusColor = switch (task.status) {
      DownloadStatus.failed => scheme.error,
      DownloadStatus.paused || DownloadStatus.queued => scheme.onSurfaceVariant,
      _ => scheme.primary,
    };
    final statusBackground = switch (task.status) {
      DownloadStatus.failed => scheme.errorContainer,
      DownloadStatus.paused ||
      DownloadStatus.queued => scheme.surfaceContainerHigh,
      _ => scheme.primaryContainer,
    };
    final total = task.totalBytes;
    final bytes = total == null
        ? downloadByteText(task.downloadedBytes)
        : '${downloadByteText(task.downloadedBytes)} / ${downloadByteText(total)}';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 480;
            final localCover = completed ? coverProvider?.call(task) : null;
            final cover = ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: narrow ? 96 : 160,
                height: narrow ? 54 : 90,
                child: localCover != null
                    ? Image(
                        image: localCover,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: scheme.surfaceContainerHigh,
                          child: Icon(
                            Icons.download_done_rounded,
                            color: scheme.primary,
                          ),
                        ),
                      )
                    : completed || task.item.video.coverUrl.isEmpty
                    ? ColoredBox(
                        color: scheme.surfaceContainerHigh,
                        child: Icon(
                          Icons.download_done_rounded,
                          color: scheme.primary,
                        ),
                      )
                    : AppCoverImage(
                        url: task.item.video.coverUrl,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: scheme.surfaceContainerHigh,
                          child: const Icon(Icons.movie_outlined),
                        ),
                      ),
              ),
            );
            final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final inlineActions = constraints.maxWidth >= 640 * textScale;
            final transferDetails = Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: statusBackground,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 14, color: statusColor),
                        const SizedBox(width: 5),
                        Text(
                          status,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Text(bytes, style: theme.textTheme.bodySmall),
                if (task.status == DownloadStatus.downloading &&
                    task.bytesPerSecond > 0)
                  Text(
                    '${downloadByteText(task.bytesPerSecond)}/s',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
              ],
            );
            final actions = Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              children: [
                if (completed && onPlay != null)
                  TextButton.icon(
                    onPressed: onPlay,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('播放'),
                  ),
                if (task.active)
                  TextButton.icon(
                    onPressed: onPause,
                    icon: const Icon(Icons.pause_rounded, size: 18),
                    label: const Text('暂停'),
                  ),
                if (task.status == DownloadStatus.paused ||
                    task.status == DownloadStatus.failed)
                  TextButton.icon(
                    onPressed: onResume,
                    icon: Icon(
                      task.status == DownloadStatus.failed
                          ? Icons.refresh_rounded
                          : Icons.play_arrow_rounded,
                      size: 18,
                    ),
                    label: Text(
                      task.status == DownloadStatus.failed ? '重试' : '继续',
                    ),
                  ),
                if (completed && onOpenDirectory != null)
                  TextButton.icon(
                    onPressed: onOpenDirectory,
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: const Text('打开目录'),
                  ),
                TextButton.icon(
                  onPressed: onRemove,
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onSurfaceVariant,
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('删除任务'),
                ),
              ],
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    cover,
                    SizedBox(width: narrow ? 12 : 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.item.video.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            task.item.part.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                          if (!narrow) ...[
                            const SizedBox(height: 10),
                            _DownloadFormatLabels(task: task),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (narrow) ...[
                  const SizedBox(height: 12),
                  _DownloadFormatLabels(task: task),
                ],
                const SizedBox(height: 12),
                if (inlineActions)
                  Row(
                    children: [
                      Expanded(child: transferDetails),
                      const SizedBox(width: 12),
                      actions,
                    ],
                  )
                else
                  transferDetails,
                if (!completed) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(4),
                    color: statusColor,
                    backgroundColor: scheme.surfaceContainerHighest,
                    value:
                        (task.status == DownloadStatus.muxing
                            ? task.muxProgress
                            : task.progress) ??
                        switch (task.status) {
                          DownloadStatus.resolving ||
                          DownloadStatus.downloading ||
                          DownloadStatus.verifying => null,
                          DownloadStatus.muxing => null,
                          _ => 0,
                        },
                  ),
                ],
                if (task.failure case final failure?) ...[
                  const SizedBox(height: 10),
                  Text(
                    failure.message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ],
                for (final warning in task.warnings)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '提示：$warning',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if (!inlineActions) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 6),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

final class _DownloadFormatLabels extends StatelessWidget {
  const _DownloadFormatLabels({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) => Text(
    '${downloadQualityText(task.selection.quality)} · ${downloadCodecText(task.selection.codec)} · ${task.selection.output.label}',
    style: Theme.of(context).textTheme.bodySmall,
  );
}

final class _DeleteTaskDialog extends StatefulWidget {
  const _DeleteTaskDialog({required this.task});
  final DownloadTask task;
  @override
  State<_DeleteTaskDialog> createState() => _DeleteTaskDialogState();
}

final class _DeleteTaskDialogState extends State<_DeleteTaskDialog> {
  bool _deleteFiles = false;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('删除下载任务'),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.task.item.video.title} · ${widget.task.item.part.title}',
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('同时删除已下载文件'),
            value: _deleteFiles,
            onChanged: (value) => setState(() => _deleteFiles = value ?? false),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _deleteFiles),
        child: const Text('删除任务'),
      ),
    ],
  );
}

final class _DownloadSettingsDialog extends ConsumerStatefulWidget {
  const _DownloadSettingsDialog({
    required this.preferences,
    required this.allowCustomDirectory,
  });
  final DownloadPreferences preferences;
  final bool allowCustomDirectory;
  @override
  ConsumerState<_DownloadSettingsDialog> createState() =>
      _DownloadSettingsDialogState();
}

final class _DownloadSettingsDialogState
    extends ConsumerState<_DownloadSettingsDialog> {
  late int _concurrency = widget.preferences.concurrency.clamp(1, 3);
  late final TextEditingController _directory = TextEditingController(
    text: widget.preferences.directory ?? '',
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _directory.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _directory.text.trim();
    if (widget.allowCustomDirectory &&
        value.isNotEmpty &&
        !_absolutePath(value)) {
      setState(() => _error = '请输入绝对路径');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(downloadControllerProvider.notifier)
          .updatePreferences(
            DownloadPreferences(
              concurrency: _concurrency,
              directory: widget.allowCustomDirectory && value.isNotEmpty
                  ? value
                  : null,
            ),
          );
      if (mounted) Navigator.pop(context);
    } on AppFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _absolutePath(String path) =>
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path) ||
      path.startsWith('/') ||
      path.startsWith(r'\\');

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('下载设置'),
    scrollable: true,
    content: SizedBox(
      width: 400,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('同时下载任务数'),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1')),
              ButtonSegment(value: 2, label: Text('2')),
              ButtonSegment(value: 3, label: Text('3')),
            ],
            selected: {_concurrency},
            onSelectionChanged: _saving
                ? null
                : (value) => setState(() => _concurrency = value.first),
          ),
          const SizedBox(height: 16),
          if (ref.watch(publicDownloadStorageProvider) != null)
            TextButton.icon(
              onPressed: _saving
                  ? null
                  : () async {
                      try {
                        await chooseDownloadDestination(
                          context,
                          ref,
                          force: true,
                        );
                      } on AppFailure catch (e) {
                        if (mounted) setState(() => _error = e.message);
                      }
                    },
              icon: const Icon(Icons.folder_open),
              label: const Text('公共下载位置（更改仅影响新任务）'),
            )
          else
            const Text('默认保存在应用文档目录的离线文件夹。目录变更只影响之后新增的任务。'),
          if (widget.allowCustomDirectory) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _directory,
              decoration: const InputDecoration(
                labelText: '自定义下载目录',
                hintText: '留空使用默认目录',
              ),
            ),
          ],
          if (_error case final error?) ...[
            const SizedBox(height: 12),
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? '保存中…' : '保存'),
      ),
    ],
  );
}
