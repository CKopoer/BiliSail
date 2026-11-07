import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/gpu_device_catalog.dart';
import '../../../shared/ui/app_notice.dart';
import '../application/gpu_devices_controller.dart';
import '../application/settings_controller.dart';
import '../domain/app_settings.dart';

final class GpuDeviceSetting extends ConsumerWidget {
  const GpuDeviceSetting({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectable =
        settings.playbackBackend == PlaybackBackendPreference.fvp &&
        ref.watch(gpuDeviceCatalogProvider).supported;
    final description = switch (defaultTargetPlatform) {
      TargetPlatform.windows => 'media_kit 的直通硬解跟随视频渲染 GPU，当前不支持单独指定解码设备。可在 Windows 图形设置中选择应用使用的 GPU；fvp 支持独立选择解码设备。',
      TargetPlatform.android =>
        'Android 由系统 MediaCodec 选择硬件解码器，不能按桌面 GPU 列表指定设备。',
      TargetPlatform.macOS ||
      TargetPlatform.iOS => 'VideoToolbox 由系统选择硬件解码设备，当前后端未开放独立 GPU 选择。',
      _ => '当前平台与播放后端暂未提供 GPU 设备选择，使用后端自动选择。',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('GPU 设备'),
          const SizedBox(height: 8),
          if (!selectable) ...[
            const Chip(label: Text('自动选择')),
            Text(description, style: Theme.of(context).textTheme.bodySmall),
          ] else
            _devices(context, ref),
        ],
      ),
    );
  }

  Widget _devices(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(gpuDevicesProvider);
    Future<void> select(String id) async {
      try {
        await ref.read(settingsControllerProvider.notifier).setFvpGpuDevice(id);
      } on Object {
        if (context.mounted) showAppNotice(context, 'GPU 设备保存失败，请重试');
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('自动选择'),
              selected: settings.fvpGpuDeviceId.isEmpty,
              onSelected: (_) => select(''),
            ),
            for (final device in devices.asData?.value ?? const <GpuDevice>[])
              ChoiceChip(
                label: Text('${device.name}（设备 ${device.index}）'),
                selected: settings.fvpGpuDeviceId == device.id,
                onSelected: (_) => select(device.id),
              ),
          ],
        ),
        devices.when(
          loading: () => const Text('正在读取 GPU 设备…'),
          error: (_, _) => const Text('无法读取 GPU 设备，请刷新重试。已保存的设备偏好保持不变。'),
          data: (available) => Text(
            settings.fvpGpuDeviceId.isNotEmpty &&
                    !available.any(
                      (device) => device.id == settings.fvpGpuDeviceId,
                    )
                ? '已保存的 GPU 当前不可用，暂时自动选择；重新连接设备后会恢复偏好。'
                : available.isEmpty
                ? '未发现可选的硬件 GPU，使用后端自动选择。'
                : '选择 fvp 的视频解码 GPU。硬解不可用时回退软件解码；跨 GPU 传输可能增加开销，不改变应用界面的渲染 GPU。',
          ),
        ),
        TextButton.icon(
          onPressed: devices.isLoading
              ? null
              : () => ref.invalidate(gpuDevicesProvider),
          icon: const Icon(Icons.refresh),
          label: const Text('刷新 GPU 设备'),
        ),
      ],
    );
  }
}
