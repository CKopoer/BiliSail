import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/media_cdn.dart';
import '../../../shared/ui/app_dialog.dart';
import '../application/cdn_speed_test_controller.dart';
import '../application/settings_controller.dart';

final class CdnSettingsTile extends ConsumerWidget {
  const CdnSettingsTile({super.key, required this.preference});
  final MediaCdnPreference preference;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    key: const ValueKey('cdn-settings'),
    contentPadding: EdgeInsets.zero,
    title: const Text('视频 CDN'),
    subtitle: Text('当前：${preference.label} · 点击选择并测速'),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => showAppDialog<void>(
      context: context,
      builder: (context) => const CdnSettingsDialog(),
    ),
  );
}

final class CdnSettingsDialog extends ConsumerStatefulWidget {
  const CdnSettingsDialog({super.key});

  @override
  ConsumerState<CdnSettingsDialog> createState() => _CdnSettingsDialogState();
}

final class _CdnSettingsDialogState extends ConsumerState<CdnSettingsDialog> {
  late final CdnSpeedTestController _controller;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(cdnSpeedTestControllerProvider.notifier);
    Future.microtask(() {
      if (mounted) unawaited(_controller.start());
    });
  }

  @override
  void dispose() {
    _controller.cancel();
    super.dispose();
  }

  Future<void> _select(MediaCdnPreference? value) async {
    if (_saving || value == null) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await ref.read(settingsControllerProvider.notifier).setMediaCdn(value);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = '设置保存失败，请重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cdnSpeedTestControllerProvider);
    final selected = ref
        .watch(settingsControllerProvider)
        .asData
        ?.value
        .mediaCdn;
    final completed = state.results.values
        .where(
          (result) =>
              result.measurement != null ||
              !['等待测速', '正在测速…'].contains(result.message),
        )
        .length;
    return AlertDialog(
      title: const Text('CDN 线路与测速'),
      content: SizedBox(
        width: 480,
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '展开后自动测速，会消耗少量流量。每个地址最多读取 1 MiB，结果仅供参考；选择后在下次加载播放源时生效。',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              state.message ??
                  '正在测速 $completed/${MediaCdnPreference.values.length}',
              key: const ValueKey('cdn-speed-status'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_saveError case final message?)
              Text(
                message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: RadioGroup<MediaCdnPreference>(
                groupValue: selected,
                onChanged: _select,
                child: ListView.builder(
                  key: const ValueKey('cdn-options'),
                  itemCount: MediaCdnPreference.values.length,
                  itemBuilder: (context, index) {
                    final option = MediaCdnPreference.values[index];
                    final result = state.results[option];
                    final measurement = result?.measurement;
                    return RadioListTile<MediaCdnPreference>(
                      key: ValueKey('cdn-option-${option.name}'),
                      value: option,
                      enabled: !_saving,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(option.label),
                      subtitle: Text(
                        measurement == null
                            ? result?.message ?? '等待测速'
                            : '${measurement.mebibytesPerSecond.toStringAsFixed(2)} MiB/s · ${measurement.host}',
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: state.running
              ? _controller.stop
              : () => unawaited(_controller.start()),
          child: Text(state.running ? '停止测速' : '重新测速'),
        ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
