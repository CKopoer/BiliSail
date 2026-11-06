import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/ui/app_dialog.dart';
import '../../../shared/ui/app_notice.dart';
import '../application/log_export_controller.dart';

final class LogExportButton extends ConsumerWidget {
  const LogExportButton({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(logExportControllerProvider);
    final onPressed = state.isLoading
        ? null
        : () async {
            await ref.read(logExportControllerProvider.notifier).export();
            if (!context.mounted) return;
            final result = ref.read(logExportControllerProvider);
            if (result.hasError) {
              showAppNotice(context, result.error.toString());
            } else if (result.value case final path?) {
              await showAppDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('日志已导出'),
                  content: SingleChildScrollView(
                    child: SelectableText('压缩包已保存到：\n$path'),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: path));
                        if (context.mounted) {
                          showAppNotice(context, '已复制保存位置');
                        }
                      },
                      child: const Text('复制位置'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('完成'),
                    ),
                  ],
                ),
              );
            }
          };
    final icon = state.isLoading
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.file_download_outlined);
    final label = state.isLoading ? '正在导出…' : '导出日志';
    if (compact) {
      return IconButton(
        key: const ValueKey('export-logs'),
        tooltip: label,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: onPressed,
        icon: icon,
      );
    }
    return TextButton.icon(
      key: const ValueKey('export-logs'),
      onPressed: onPressed,
      icon: icon,
      label: Text(label),
    );
  }
}
