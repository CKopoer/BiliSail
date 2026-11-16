import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../shared/ui/app_dialog.dart';
import '../application/download_controller.dart';
import '../domain/public_download_storage.dart';

Future<bool> chooseDownloadDestination(
  BuildContext context,
  WidgetRef ref, {
  bool force = false,
}) async {
  if (ref.read(publicDownloadStorageProvider) == null) return true;
  final controller = ref.read(downloadControllerProvider.notifier);
  if (!force && await controller.hasDestination()) return true;
  if (!context.mounted) return false;
  return await showAppDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _DownloadDestinationDialog(),
      ) ??
      false;
}

final class _DownloadDestinationDialog extends ConsumerStatefulWidget {
  const _DownloadDestinationDialog();

  @override
  ConsumerState<_DownloadDestinationDialog> createState() =>
      _DownloadDestinationDialogState();
}

final class _DownloadDestinationDialogState
    extends ConsumerState<_DownloadDestinationDialog> {
  DownloadFolderListing? _listing;
  bool _busy = false;
  bool _needsAccess = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(null);
    });
  }

  Future<void> _load(String? path) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = ref.read(downloadControllerProvider.notifier);
    try {
      if (_needsAccess) {
        final granted = await controller.requestDirectoryAccess();
        if (!mounted) return;
        if (!granted) {
          setState(() => _error = '需要文件访问权限才能选择和保存下载。请允许访问后重试。');
          return;
        }
        _needsAccess = false;
      }
      final listing = await controller.listDirectories(path);
      if (mounted) setState(() => _listing = listing);
    } on AppFailure catch (error) {
      if (mounted) {
        setState(() {
          _needsAccess = error.kind == AppFailureKind.permission;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取文件夹，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose() async {
    final directory = _listing?.directory;
    if (_busy || directory == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(downloadControllerProvider.notifier)
          .chooseDestination(directory.path);
      if (mounted) Navigator.pop(context, true);
    } on AppFailure catch (error) {
      if (mounted) {
        setState(() {
          _needsAccess = error.kind == AppFailureKind.permission;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '无法保存到此文件夹，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final listing = _listing;
    final directory = listing?.directory;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        icon: Icon(Icons.folder_open_rounded, color: colors.primary),
        title: const Text('选择下载文件夹'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        content: SizedBox(
          width: 440,
          height: (MediaQuery.sizeOf(context).height * 0.55).clamp(160, 460),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: '上一级',
                        onPressed: !_busy && directory != null
                            ? () => _load(listing?.parent)
                            : null,
                        icon: const Icon(Icons.arrow_upward_rounded),
                        color: colors.primary,
                      ),
                      Expanded(
                        child: Text(
                          directory?.path ?? '选择存储位置',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (_busy) const LinearProgressIndicator(),
              if (_error case final error?)
                Flexible(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(error, style: TextStyle(color: colors.error)),
                    ),
                  ),
                ),
              if (!_busy && (_error != null || _needsAccess))
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _load(directory?.path),
                    icon: Icon(
                      _needsAccess
                          ? Icons.security_rounded
                          : Icons.refresh_rounded,
                    ),
                    label: Text(_needsAccess ? '重新授权' : '重新加载'),
                  ),
                ),
              Expanded(
                child: listing == null
                    ? const SizedBox.shrink()
                    : listing.folders.isEmpty
                    ? Center(
                        child: Text(
                          directory == null ? '没有可用的存储设备' : '此文件夹中没有子文件夹',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        itemCount: listing.folders.length,
                        itemBuilder: (context, index) {
                          final folder = listing.folders[index];
                          return ListTile(
                            enabled: !_busy,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            leading: Icon(
                              Icons.folder_rounded,
                              color: colors.primary,
                            ),
                            title: Text(folder.name),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _load(folder.path),
                          );
                        },
                      ),
              ),
              if (listing?.truncated == true) const Text('子文件夹过多，仅显示前 2000 项。'),
              const SizedBox(height: 8),
              Text(
                '仅影响之后新增的任务。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _busy || directory == null || _needsAccess
                ? null
                : _choose,
            child: const Text('选择此文件夹'),
          ),
        ],
      ),
    );
  }
}
