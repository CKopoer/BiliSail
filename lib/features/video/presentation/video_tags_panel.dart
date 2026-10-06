import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/video.dart';
import '../application/video_extras_controller.dart';

final class VideoTagsPanel extends ConsumerWidget {
  const VideoTagsPanel({super.key, required this.id, this.onSearch});

  final VideoId id;
  final ValueChanged<String>? onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ref
        .watch(videoTagsProvider(id))
        .when(
          loading: () => Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('正在加载标签…', style: theme.textTheme.bodySmall),
          ),
          error: (error, _) =>
              error is AppFailure && error.kind == AppFailureKind.cancelled
              ? const SizedBox.shrink()
              : Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => ref.invalidate(videoTagsProvider(id)),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('标签加载失败，点击重试'),
                  ),
                ),
          data: (tags) => tags.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('标签', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) => Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final tag in tags)
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: constraints.maxWidth,
                                ),
                                child: Tooltip(
                                  message: '搜索：$tag',
                                  child: ActionChip(
                                    label: Text(
                                      tag,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    labelStyle: theme.textTheme.bodySmall,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    onPressed: onSearch == null
                                        ? null
                                        : () => onSearch?.call(tag),
                                  ),
                                ),
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
