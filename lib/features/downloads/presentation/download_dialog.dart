import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/ui/app_dialog.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/audio_quality.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video_codec.dart';
import '../application/download_controller.dart';
import '../domain/download_models.dart';
import 'download_destination_dialog.dart';
import 'downloads_screen.dart';

Future<void> showDownloadDialog(
  BuildContext context, {
  required List<DownloadItem> items,
  String? initialKey,
  DownloadSelection? initialSelection,
}) => showAppDialog<void>(
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
  late final DownloadItem? _currentItem =
      widget.items
          .where((item) => item.isValid && item.key == widget.initialKey)
          .firstOrNull ??
      widget.items.where((item) => item.isValid).firstOrNull;
  late final Set<String> _selected = widget.initialKey == null
      ? widget.items
            .where((item) => item.isValid)
            .map((item) => item.key)
            .toSet()
      : widget.items
            .where((item) => item.isValid && item.key == widget.initialKey)
            .map((item) => item.key)
            .toSet();
  late int? _preferredQuality = widget.initialSelection?.quality;
  late VideoCodecPreference _preferredCodec =
      widget.initialSelection?.codec ?? VideoCodecPreference.h264;
  late AudioQualityPreference _preferredAudioQuality =
      widget.initialSelection?.audioQuality ?? AudioQualityPreference.aac192;
  late bool _danmaku = widget.initialSelection?.includeDanmaku ?? true;
  late bool _subtitles = widget.initialSelection?.includeSubtitles ?? true;
  late DownloadOutput _output = ref.read(downloadControllerProvider).canMerge
      ? (widget.initialSelection?.output ?? DownloadOutput.mp4)
      : DownloadOutput.separate;
  DownloadOptions? _options;
  bool _loading = false;
  bool _submitting = false;
  String? _error;
  RequestCancellation? _cancellation;
  late final String _openedScope;
  late final int _openedEpoch;

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
      if (mounted) _loadOptions();
    });
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    final item = _currentItem;
    if (item == null || _accountChanged) return;
    _cancellation?.cancel();
    final cancellation = RequestCancellation();
    _cancellation = cancellation;
    setState(() {
      _loading = true;
      _options = null;
      _error = null;
    });
    try {
      final options = await ref
          .read(downloadControllerProvider.notifier)
          .options(item, cancellation: cancellation);
      if (!mounted || cancellation.isCancelled || _accountChanged) return;
      setState(() {
        _options = options;
        if (options.video.isEmpty) {
          _error = '当前分集没有可下载的视频轨道';
        } else if (options.audio.isEmpty) {
          _error = '当前分集没有可下载的音频轨道';
        }
        _loading = false;
      });
    } on AppFailure catch (error) {
      if (mounted && !cancellation.isCancelled && !_accountChanged) {
        setState(() {
          _loading = false;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted && !cancellation.isCancelled && !_accountChanged) {
        setState(() {
          _loading = false;
          _error = '读取下载选项失败，请重试';
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
  }

  Future<void> _submit(DownloadSelection selection) async {
    final option = (quality: selection.quality, codec: selection.codec);
    if (_loading ||
        _submitting ||
        _options?.video.contains(option) != true ||
        _options?.audio.contains(selection.audioQuality) != true ||
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
      if (!await chooseDownloadDestination(context, ref)) {
        return;
      }
      if (!mounted || _accountChanged) return;
      await ref
          .read(downloadControllerProvider.notifier)
          .enqueue(selected, selection);
      if (!mounted) return;
      if (source.sessionEpoch != _openedEpoch ||
          source.accountScope != _openedScope) {
        setState(() => _error = '账号已变化，请重新打开下载窗口');
        return;
      }
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.pop(context);
      messenger?.showSnackBar(
        SnackBar(
          content: Text('已添加 ${selected.length} 项下载任务'),
          duration: const Duration(milliseconds: 1500),
        ),
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
    final options = accountChanged ? null : _options;
    final videoOptions = options?.video ?? const <DownloadVideoOption>{};
    final qualities =
        videoOptions.map((option) => option.quality).toSet().toList()
          ..sort((a, b) => b.compareTo(a));
    final quality = qualities.contains(_preferredQuality)
        ? _preferredQuality
        : qualities.firstOrNull;
    final codecs =
        videoOptions
            .where((option) => option.quality == quality)
            .map((option) => option.codec)
            .toList()
          ..sort((a, b) => a.index.compareTo(b.index));
    final codec = codecs.contains(_preferredCodec)
        ? _preferredCodec
        : codecs.firstOrNull;
    final audioOptions = options?.audio ?? const <AudioQualityPreference>{};
    final audioQuality = _preferredAudioQuality.fallbackOrder
        .where(audioOptions.contains)
        .firstOrNull;
    final output = canMerge ? _output : DownloadOutput.separate;
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
                          : () => setState(
                              () => _selected.addAll(
                                widget.items
                                    .where((item) => item.isValid)
                                    .map((item) => item.key),
                              ),
                            ),
                      child: const Text('全选'),
                    ),
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => setState(_selected.clear),
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
                if (_loading && !accountChanged) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  const Text('正在读取可用画质和音质…'),
                ] else ...[
                  DropdownButtonFormField<int>(
                    initialValue: quality,
                    decoration: const InputDecoration(labelText: '画质'),
                    items: [
                      for (final quality in qualities)
                        DropdownMenuItem(
                          value: quality,
                          child: Text(downloadQualityText(quality)),
                        ),
                    ],
                    onChanged: _submitting
                        ? null
                        : (value) => setState(() => _preferredQuality = value),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<VideoCodecPreference>(
                    initialValue: codec,
                    decoration: const InputDecoration(labelText: '视频编码'),
                    items: [
                      for (final codec in codecs)
                        DropdownMenuItem(
                          value: codec,
                          child: Text(downloadCodecText(codec)),
                        ),
                    ],
                    onChanged: _submitting
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _preferredCodec = value);
                            }
                          },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<AudioQualityPreference>(
                    initialValue: audioQuality,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '音质'),
                    items: [
                      for (final option in AudioQualityPreference.values)
                        if (audioOptions.contains(option))
                          DropdownMenuItem(
                            value: option,
                            child: Text(
                              option.displayLabel,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                    ],
                    onChanged: _submitting || accountChanged
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _preferredAudioQuality = value);
                            }
                          },
                  ),
                  if (_selected.any((key) => key != _currentItem?.key))
                    Text(
                      '其他分集缺少所选音质时会自动选择可用档位',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<DownloadOutput>(
                  initialValue: output,
                  decoration: const InputDecoration(labelText: '保存格式'),
                  items: [
                    for (final output in DownloadOutput.values)
                      DropdownMenuItem(
                        value: output,
                        enabled: !output.isMerged || canMerge,
                        child: Text(output.label),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) {
                          if (value != null) setState(() => _output = value);
                        },
                ),
                const SizedBox(height: 5),
                Text(
                  canMerge ? '保留原画质，字幕和弹幕单独保存' : '当前无法合并，可分轨保存',
                  style: Theme.of(context).textTheme.bodySmall,
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
                  if (!_loading && (quality == null || audioQuality == null))
                    TextButton(
                      onPressed: _loadOptions,
                      child: const Text('重新读取下载选项'),
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
                  quality != null &&
                  codec != null &&
                  audioQuality != null
              ? () => _submit(
                  DownloadSelection(
                    quality: quality,
                    codec: codec,
                    audioQuality: audioQuality,
                    includeDanmaku: _danmaku,
                    includeSubtitles: _subtitles,
                    output: output,
                  ),
                )
              : null,
          child: Text(_submitting ? '添加中…' : '开始下载'),
        ),
      ],
    );
  }
}
