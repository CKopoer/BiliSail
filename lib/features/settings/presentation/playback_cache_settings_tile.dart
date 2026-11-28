import 'package:bili_player/playback_cache_limits.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/ui/app_dialog.dart';
import '../domain/app_settings.dart';

final class PlaybackCacheSettingsTile extends StatelessWidget {
  const PlaybackCacheSettingsTile({
    super.key,
    required this.value,
    required this.save,
  });

  final PlaybackCacheSettings value;
  final Future<void> Function(PlaybackCacheSettings) save;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: const Text('播放缓存大小'),
    subtitle: Text(
      '点播前向 ${value.videoForwardMiB} MiB · 后向 ${value.videoBackwardMiB} MiB\n'
      '直播前向 ${value.liveForwardMiB} MiB',
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: () async {
      final result = await showAppDialog<PlaybackCacheSettings>(
        context: context,
        builder: (context) => _PlaybackCacheDialog(value: value),
      );
      if (context.mounted && result != null && result != value) {
        await save(result);
      }
    },
  );
}

final class _PlaybackCacheDialog extends StatefulWidget {
  const _PlaybackCacheDialog({required this.value});

  final PlaybackCacheSettings value;

  @override
  State<_PlaybackCacheDialog> createState() => _PlaybackCacheDialogState();
}

final class _PlaybackCacheDialogState extends State<_PlaybackCacheDialog> {
  final _form = GlobalKey<FormState>();
  late final _videoForward = TextEditingController(
    text: widget.value.videoForwardMiB.toString(),
  );
  late final _videoBackward = TextEditingController(
    text: widget.value.videoBackwardMiB.toString(),
  );
  late final _liveForward = TextEditingController(
    text: widget.value.liveForwardMiB.toString(),
  );

  @override
  void dispose() {
    _videoForward.dispose();
    _videoBackward.dispose();
    _liveForward.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState?.validate() != true) return;
    Navigator.of(context).pop((
      videoForwardMiB: int.parse(_videoForward.text.trim(), radix: 10),
      videoBackwardMiB: int.parse(_videoBackward.text.trim(), radix: 10),
      liveForwardMiB: int.parse(_liveForward.text.trim(), radix: 10),
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('播放缓存大小'),
    scrollable: true,
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field('点播前向缓存', _videoForward, min: 1),
          const SizedBox(height: 12),
          _field('点播后向缓存', _videoBackward, min: 0),
          const SizedBox(height: 12),
          _field('直播前向缓存', _liveForward, min: 1),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('保存')),
    ],
  );

  Widget _field(
    String label,
    TextEditingController controller, {
    required int min,
  }) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label, suffixText: 'MiB'),
    validator: (value) {
      final size = int.tryParse(value?.trim() ?? '', radix: 10);
      return size != null && size >= min && size <= maximumPlaybackCacheMiB
          ? null
          : '请输入 $min～$maximumPlaybackCacheMiB 的整数';
    },
  );
}
