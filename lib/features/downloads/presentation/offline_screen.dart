import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../shared/ui/state_view.dart';
import '../application/download_controller.dart';
import '../domain/download_models.dart';
import 'downloads_screen.dart';

/// The composition root supplies the existing player using the verified local task.
final class OfflineScreen extends ConsumerStatefulWidget {
  const OfflineScreen({
    super.key,
    required this.taskId,
    required this.playerBuilder,
    this.onBackToDownloads,
    this.coverProvider,
  });

  final String taskId;
  final Widget Function(BuildContext, DownloadTask) playerBuilder;
  final VoidCallback? onBackToDownloads;
  final ImageProvider<Object>? Function(DownloadTask)? coverProvider;

  @override
  ConsumerState<OfflineScreen> createState() => _OfflineScreenState();
}

final class _OfflineScreenState extends ConsumerState<OfflineScreen> {
  Future<DownloadTask>? _verified;
  String? _identity;

  void _back() {
    if (widget.onBackToDownloads case final callback?) {
      callback();
    } else {
      Navigator.maybePop(context);
    }
  }

  void _verify(DownloadTask task) {
    final identity = '${task.id}:${task.scope}';
    if (_identity == identity && _verified != null) return;
    _identity = identity;
    _verified = ref.read(downloadRepositoryProvider).offlineTask(task.id);
  }

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(downloadControllerProvider);
    final source = ref.watch(downloadSourceRepositoryProvider);
    DownloadTask? current;
    for (final task in queue.tasks) {
      if (task.id == widget.taskId &&
          task.scope == source.accountScope &&
          task.status == DownloadStatus.completed) {
        current = task;
        break;
      }
    }
    if (current == null) {
      _verified = null;
      _identity = null;
      return _OfflineUnavailable(onBack: _back);
    }
    final verifiedCurrent = current;
    _verify(verifiedCurrent);
    return FutureBuilder<DownloadTask>(
      future: _verified,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const StateView.loading(message: '正在核验本地文件…');
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          return StateView.error(
            message: error is AppFailure ? error.message : '本地文件不可用',
            onAction: () => setState(() {
              _verified = null;
              _identity = null;
            }),
          );
        }
        final verified = snapshot.data;
        if (verified == null ||
            verified.status != DownloadStatus.completed ||
            verified.id != verifiedCurrent.id ||
            verified.scope != verifiedCurrent.scope ||
            source.accountScope != verified.scope) {
          return _OfflineUnavailable(onBack: _back);
        }
        final cover = widget.coverProvider?.call(verified);
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _back,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('返回下载'),
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 440;
                final image = ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: narrow ? 120 : 192,
                    height: narrow ? 68 : 108,
                    child: cover == null
                        ? ColoredBox(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHigh,
                            child: const Icon(Icons.download_done_rounded),
                          )
                        : Image(
                            image: cover,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => ColoredBox(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHigh,
                              child: const Icon(Icons.download_done_rounded),
                            ),
                          ),
                  ),
                );
                final details = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      verified.item.video.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(verified.item.part.title),
                    const SizedBox(height: 6),
                    Text(
                      '本地 · ${downloadQualityText(verified.selection.quality)} · ${downloadCodecText(verified.selection.codec)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                );
                return narrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [image, const SizedBox(height: 12), details],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          image,
                          const SizedBox(width: 16),
                          Expanded(child: details),
                        ],
                      );
              },
            ),
            for (final warning in verified.warnings)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '离线附属内容提示：$warning',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 18),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: widget.playerBuilder(context, verified),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

final class _OfflineUnavailable extends StatelessWidget {
  const _OfflineUnavailable({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => StateView.empty(
    icon: Icons.cloud_off_outlined,
    message: '这项离线下载已不可用，可能已删除或切换了账号',
    actionLabel: '返回下载',
    onAction: onBack,
  );
}
