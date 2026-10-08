import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video_codec.dart';
import '../application/download_controller.dart';
import '../domain/download_models.dart';
import 'downloads_screen.dart';

Future<void> showDownloadDialog(
  BuildContext context, {
  required List<DownloadItem> items,
  String? initialKey,
  DownloadSelection? initialSelection,
}) => showDialog<void>(
  context: context,
  builder: (_) => DownloadDialog(
    items: items,
    initialKey: initialKey,
    initialSelection: initialSelection,
  ),
);

final class DownloadDialog extends ConsumerStatefulWidget {
  const DownloadDialog({
    super.key,
    required this.items,
    this.initialKey,
    this.initialSelection,
  });

  final List<DownloadItem> items;
  final String? initialKey;
  final DownloadSelection? initialSelection;

  @override
  ConsumerState<DownloadDialog> createState() => _DownloadDialogState();
}

final class _DownloadDialogState extends ConsumerState<DownloadDialog> {
  late final Set<String> _selected = widget.initialKey == null
      ? widget.items
            .where((item) => item.isValid)
            .map((item) => item.key)
            .toSet()
      : widget.items
            .where((item) => item.isValid && item.key == widget.initialKey)
            .map((item) => item.key)
            .toSet();
  late int? _quality = widget.initialSelection?.quality;
  late VideoCodecPreference _codec =
      widget.initialSelection?.codec ?? VideoCodecPreference.h264;
  late bool _danmaku = widget.initialSelection?.includeDanmaku ?? true;
  late bool _subtitles = widget.initialSelection?.includeSubtitles ?? true;
  late bool _merge = widget.initialSelection?.output == DownloadOutput.mp4;
  List<int> _qualities = const [];
  bool _loading = false;
  bool _submitting = false;
  String? _error;
  RequestCancellation? _cancellation;
  int _generation = 0;
  late final String _openedScope;
  late final int _openedEpoch;
  final Map<String, List<int>> _qualityCache = {};

  String _cacheKey(DownloadItem item) =>
      '$_openedScope:$_openedEpoch:${item.key}';

  bool get _accountChanged {
    final source = ref.read(downloadSourceRepositoryProvider);
    return source.accountScope != _openedScope ||
        source.sessionEpoch != _openedEpoch;
  }

  @override
  void initState() {
    super.initState();
    final source = ref.read(downloadSourceRepositoryProvider);
    _openedScope = source.accountScope;
    _openedEpoch = source.sessionEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadQualities();
    });
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    super.dispose();
  }

  Future<void> _loadQualities() async {
    _cancellation?.cancel();
    final cancellation = RequestCancellation();
    _cancellation = cancellation;
    final generation = ++_generation;
    final source = ref.read(downloadSourceRepositoryProvider);
    if (_accountChanged) {
      setState(() {
        _loading = false;
        _qualities = const [];
        _error = '账号已变化，请重新打开下载窗口';
      });
      return;
    }
    final chosen = widget.items
        .where((item) => item.isValid && _selected.contains(item.key))
        .toList();
    setState(() {
      _loading = chosen.isNotEmpty;
      _qualities = const [];
      _error = null;
    });
    if (chosen.isEmpty) return;
    try {
      final responses = <List<int>>[];
      final newlyLoaded = <String, List<int>>{};
      // Keep source reads bounded. A cancelled selection never commits its
      // new results to the per-dialog cache.
      for (var start = 0; start < chosen.length; start += 3) {
        if (cancellation.isCancelled || _accountChanged) return;
        final batch = chosen.skip(start).take(3).toList();
        final values = await Future.wait([
          for (final item in batch)
            if (_qualityCache[_cacheKey(item)] case final cached?)
              Future.value(cached)
            else
              ref
                  .read(downloadControllerProvider.notifier)
                  .qualities(item, cancellation: cancellation),
        ]);
        if (cancellation.isCancelled || _accountChanged) return;
        for (var index = 0; index < batch.length; index++) {
          responses.add(values[index]);
          newlyLoaded[_cacheKey(batch[index])] = values[index];
        }
      }
      if (!mounted ||
          cancellation.isCancelled ||
          generation != _generation ||
          source.sessionEpoch != _openedEpoch ||
          source.accountScope != _openedScope) {
        return;
      }
      _qualityCache.addAll(newlyLoaded);
      final common = responses.first.toSet();
      for (final response in responses.skip(1)) {
        common.removeWhere((quality) => !response.contains(quality));
      }
      final available = common.where((quality) => quality > 0).toList()
        ..sort((a, b) => b.compareTo(a));
      setState(() {
        _qualities = available;
        if (!available.contains(_quality)) {
          _quality = available.isEmpty ? null : available.first;
        }
        if (available.isEmpty) {
          _error = '所选分集没有共同可用画质，请调整选择';
        }
        _loading = false;
      });
    } on AppFailure catch (error) {
      if (mounted && !cancellation.isCancelled && generation == _generation) {
        setState(() {
          _loading = false;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted && !cancellation.isCancelled && generation == _generation) {
        setState(() {
          _loading = false;
          _error = '读取画质失败，请重试';
        });
      }
    }
  }

  void _select(String key, bool selected) {
    setState(() {
      if (selected) {
        _selected.add(key);
      } else {
        _selected.remove(key);
      }
    });
    _loadQualities();
  }

  Future<void> _submit() async {
    final quality = _quality;
    if (_loading ||
        _submitting ||
        quality == null ||
        _selected.isEmpty ||
        _accountChanged) {
      if (_accountChanged) {
        setState(() => _error = '账号已变化，请重新打开下载窗口');
      }
      return;
    }
    final source = ref.read(downloadSourceRepositoryProvider);
    final selected = widget.items
        .where((item) => item.isValid && _selected.contains(item.key))
        .toList();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(downloadControllerProvider.notifier)
          .enqueue(
            selected,
            DownloadSelection(
              quality: quality,
              codec: _codec,
              includeDanmaku: _danmaku,
              includeSubtitles: _subtitles,
              output: _merge ? DownloadOutput.mp4 : DownloadOutput.separate,
            ),
          );
      if (!mounted) return;
      if (source.sessionEpoch != _openedEpoch ||
          source.accountScope != _openedScope) {
        setState(() => _error = '账号已变化，请重新打开下载窗口');
        return;
      }
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.pop(context);
      messenger?.showSnackBar(
        SnackBar(content: Text('已添加 ${selected.length} 项下载任务')),
      );
    } on AppFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '添加任务失败，请重试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canMerge = ref.watch(downloadControllerProvider).canMerge;
    ref.watch(downloadSourceRepositoryProvider);
    final accountChanged = _accountChanged;
    final validCount = widget.items.where((item) => item.isValid).length;
    return AlertDialog(
      title: const Text('下载视频'),
      content: SizedBox(
        width: 540,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.65,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('选择分 P 或剧集 · 已选 ${_selected.length} / $validCount'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () {
                              setState(
                                () => _selected.addAll(
                                  widget.items
                                      .where((item) => item.isValid)
                                      .map((item) => item.key),
                                ),
                              );
                              _loadQualities();
                            },
                      child: const Text('全选'),
                    ),
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () {
                              setState(_selected.clear);
                              _loadQualities();
                            },
                      child: const Text('清空'),
                    ),
                  ],
                ),
                Container(
                  constraints: const BoxConstraints(maxHeight: 225),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: widget.items.length,
                    itemBuilder: (context, index) {
                      final item = widget.items[index];
                      return CheckboxListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                        ),
                        title: Text(
                          item.part.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: item.isValid
                            ? Text('第 ${item.part.page} 集')
                            : const Text('不可下载'),
                        value: _selected.contains(item.key),
                        onChanged: item.isValid && !_submitting
                            ? (value) => _select(item.key, value ?? false)
                            : null,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                if (_loading) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  const Text('正在读取实际可用画质…'),
                ] else ...[
                  DropdownButtonFormField<int>(
                    key: ValueKey(_qualities.join(',')),
                    initialValue: _qualities.contains(_quality)
                        ? _quality
                        : null,
                    decoration: const InputDecoration(labelText: '画质'),
                    items: [
                      for (final quality in _qualities)
                        DropdownMenuItem(
                          value: quality,
                          child: Text(downloadQualityText(quality)),
                        ),
                    ],
                    onChanged: _submitting
                        ? null
                        : (value) => setState(() => _quality = value),
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<VideoCodecPreference>(
                  initialValue: _codec,
                  decoration: const InputDecoration(labelText: '视频编码'),
                  items: [
                    for (final codec in VideoCodecPreference.values)
                      DropdownMenuItem(
                        value: codec,
                        child: Text(downloadCodecText(codec)),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) {
                          if (value != null) setState(() => _codec = value);
                        },
                ),
                const SizedBox(height: 5),
                Text(
                  '若所选编码没有对应轨道，任务会明确失败。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('合并为单个 MP4'),
                  subtitle: Text(canMerge ? '保留原画质，字幕和弹幕单独保存' : '当前无法合并，可分轨保存'),
                  value: _merge,
                  onChanged: _submitting || !canMerge
                      ? null
                      : (value) => setState(() => _merge = value ?? false),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('保存弹幕'),
                  value: _danmaku,
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _danmaku = value ?? false),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('保存字幕'),
                  value: _subtitles,
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _subtitles = value ?? false),
                ),
                if (accountChanged) ...[
                  const SizedBox(height: 8),
                  Text(
                    '账号已变化，请重新打开下载窗口',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ] else if (_error case final error?) ...[
                  const SizedBox(height: 8),
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  if (!_loading && _selected.isNotEmpty && _qualities.isEmpty)
                    TextButton(
                      onPressed: _loadQualities,
                      child: const Text('重新读取画质'),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed:
              !accountChanged &&
                  !_loading &&
                  !_submitting &&
                  _selected.isNotEmpty &&
                  _quality != null
              ? _submit
              : null,
          child: Text(_submitting ? '添加中…' : '开始下载'),
        ),
      ],
    );
  }
}
