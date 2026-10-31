import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_icon.dart';
import '../../../shared/ui/app_notice.dart';
import '../application/settings_controller.dart';

final class AppIconSettings extends ConsumerStatefulWidget {
  const AppIconSettings({super.key, required this.value});
  final AppIconPreference value;

  @override
  ConsumerState<AppIconSettings> createState() => _AppIconSettingsState();
}

final class _AppIconSettingsState extends ConsumerState<AppIconSettings> {
  bool _saving = false;

  Future<void> _select(AppIconPreference icon) async {
    setState(() => _saving = true);
    try {
      await ref.read(settingsControllerProvider.notifier).setAppIcon(icon);
    } catch (_) {
      if (mounted) showAppNotice(context, '应用图标切换失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = ref.watch(appIconServiceProvider).surface;
    if (surface == AppIconSurface.unsupported) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('应用图标'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final icon in AppIconPreference.values)
                ChoiceChip(
                  avatar: Image.asset(icon.asset, width: 28, height: 28),
                  label: Text(icon.label),
                  selected: widget.value == icon,
                  onSelected: _saving ? null : (_) => _select(icon),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(switch (surface) {
            AppIconSurface.launcher => '切换桌面启动图标。系统可能显示提示，桌面刷新可能需要稍等片刻。',
            AppIconSurface.window =>
              defaultTargetPlatform == TargetPlatform.windows
                  ? '切换窗口图标；EXE/MSI 同步运行中的任务栏和已有开始菜单入口。MSIX 任务栏显示由系统决定，开始菜单及已有固定图标保持原样。其他快捷方式不变。'
                  : '切换运行中的窗口图标，任务栏显示由系统决定。安装包、已有快捷方式和固定图标保持原样。',
            AppIconSurface.dock => '切换运行中的 Dock 图标，重启后会重新应用。访达与启动台图标保持原样。',
            AppIconSurface.unsupported => '',
          }, style: Theme.of(context).textTheme.bodySmall),
          if (ref.read(settingsControllerProvider.notifier).iconRestoreFailed)
            const Text('上次图标恢复失败，请重新选择图标。'),
        ],
      ),
    );
  }
}
