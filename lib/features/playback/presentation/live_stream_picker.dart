import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/ui/app_dialog.dart';
import '../../settings/application/settings_controller.dart';
import '../application/playback_session.dart';
import '../domain/playback_repository.dart';

String liveStreamLabel(LiveStreamPreference preference) => preference.label;

Future<void> showLiveStreamPicker(
  BuildContext context, {
  required PlaybackSession session,
  required PlaybackMedia media,
  required ValueChanged<bool> onMenuChanged,
}) async {
  onMenuChanged(true);
  final theme = Theme.of(Navigator.of(context).context);
  try {
    await showAppDialog<void>(
      context: context,
      builder: (_) => Theme(
        data: theme,
        child: LiveStreamPicker(session: session, media: media),
      ),
    );
  } finally {
    onMenuChanged(false);
  }
}

/// Selection is staged locally: browsing alternatives never interrupts playback.
class LiveStreamPicker extends ConsumerStatefulWidget {
  const LiveStreamPicker({
    super.key,
    required this.session,
    required this.media,
  });
  final PlaybackSession session;
  final PlaybackMedia media;
  @override
  ConsumerState<LiveStreamPicker> createState() => _LiveStreamPickerState();
}

class _LiveStreamPickerState extends ConsumerState<LiveStreamPicker> {
  late final int _generation;
  late LiveStreamPreference _preference = widget.session.liveStreamPreference;
  late int _quality = widget.session.requestedQuality;
  late int _line = widget.session.liveLine;
  bool _remember = true;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _generation = widget.session.sourceGeneration;
  }

  LivePlaybackStream? get _selected =>
      (_preference.isAutomatic
          ? widget.media.liveStreams
                .where(
                  (stream) =>
                      VideoCodecPreference.fromCodec(stream.preference.codec) ==
                      VideoCodecPreference.h264,
                )
                .firstOrNull
          : null) ??
      widget.media.liveStreams
          .where((stream) => stream.preference == _preference)
          .firstOrNull ??
      widget.media.liveStreams
          .where((stream) => stream.preference == widget.media.liveStream)
          .firstOrNull;

  Future<void> _apply() async {
    if (_generation != widget.session.sourceGeneration) {
      setState(() => _error = '播放内容已变化，请关闭后重新选择');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_remember) {
        await ref
            .read(settingsControllerProvider.notifier)
            .setLiveStreamPreference(_preference);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '偏好保存失败，请重试';
        });
      }
      return;
    }
    if (!mounted) return;
    if (_generation != widget.session.sourceGeneration) {
      setState(() {
        _saving = false;
        _error = '播放内容已变化，请关闭后重新选择';
      });
      return;
    }
    Navigator.of(context).pop();
    await widget.session.changeLiveStream(
      _preference,
      quality: _quality,
      line: _line,
    );
  }

  Widget _heading(String number, String title) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Row(
      children: [
        CircleAvatar(
          radius: 12,
          child: Text(number, style: const TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleSmall),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    final selected = _selected;
    final urls = selected?.urls ?? media.video.urls;
    final qualities = {
      0,
      ...?selected?.qualities,
      if (selected == null) ...media.qualities,
      _quality,
    };
    final saved = ref
        .watch(settingsControllerProvider)
        .asData
        ?.value
        .liveStreamPreference;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: MediaQuery.sizeOf(context).height - 48,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 12, 4),
              child: Row(
                children: [
                  const Icon(Icons.tune),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '直播流与线路',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '当前 ${media.qualityLabels[media.quality] ?? media.quality} · ${liveStreamLabel(media.liveStream ?? LiveStreamPreference.automatic)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    _heading('1', '清晰度'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final quality in qualities)
                          ChoiceChip(
                            label: Text(
                              quality == 0
                                  ? '自动'
                                  : media.qualityLabels[quality] ?? '$quality',
                            ),
                            selected: _quality == quality,
                            onSelected: _saving
                                ? null
                                : (_) => setState(() => _quality = quality),
                          ),
                      ],
                    ),
                    _heading('2', '直播流'),
                    const Text('H.264 兼容性较好；HEVC / AV1 可尝试节省带宽，实际解码效果取决于设备。'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final preference in [
                          LiveStreamPreference.automatic,
                          ...media.liveStreams
                              .map((stream) => stream.preference)
                              .toSet(),
                        ])
                          ChoiceChip(
                            label: Text(liveStreamLabel(preference)),
                            selected: _preference == preference,
                            onSelected: _saving
                                ? null
                                : (_) => setState(() {
                                    _preference = preference;
                                    _line = 0;
                                    final available =
                                        _selected?.qualities ?? media.qualities;
                                    if (_quality != 0 &&
                                        !available.contains(_quality)) {
                                      _quality = 0;
                                    }
                                  }),
                          ),
                      ],
                    ),
                    _heading('3', 'CDN 线路'),
                    for (var i = 0; i < urls.length; i++)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        selected: _line == i,
                        leading: Icon(
                          _line == i
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                        ),
                        title: Text('直播线路 ${liveLineLabel(i)}'),
                        subtitle: Text(
                          urls[i].host,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: _saving ? null : () => setState(() => _line = i),
                      ),
                    const Divider(),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('记住直播流偏好'),
                      subtitle: Text(
                        saved == null || saved.isAutomatic
                            ? '新房间优先使用所选组合；缺少时自动回退'
                            : '已保存：${liveStreamLabel(saved)}',
                      ),
                      value: _remember,
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _remember = value),
                    ),
                    const Text('仅保存协议、格式和编码。清晰度沿用独立默认设置，CDN 线路由每个房间实时提供。'),
                    if (_error case final error?)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 24, 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _preference = LiveStreamPreference.automatic;
                            _line = 0;
                          }),
                    child: const Text('恢复自动'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saving ? null : _apply,
                    child: Text(_saving ? '保存中…' : '应用'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
