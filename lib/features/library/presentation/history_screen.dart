import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/app_failure.dart';
import '../../../shared/ui/state_view.dart';
import '../../../shared/ui/video_grid.dart';
import '../application/library_controller.dart';

final class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(historyProvider);
        await ref.read(historyProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text('观看历史', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 7),
          Text(
            '继续观看最近打开的视频',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          history.when(
            loading: () =>
                const SizedBox(height: 300, child: StateView.loading()),
            error: (error, _) => SizedBox(
              height: 300,
              child: StateView.error(
                message: error is AppFailure ? error.message : '历史记录加载失败',
                onAction: () => ref.invalidate(historyProvider),
              ),
            ),
            data: (entries) => entries.isEmpty
                ? const SizedBox(
                    height: 280,
                    child: StateView.empty(message: '还没有观看记录'),
                  )
                : VideoGrid.indexed(
                    onOpenUser: (id) => context.go('/user/${id.value}'),
                    items: [for (final entry in entries) entry.video],
                    onOpen: (index) =>
                        context.go(entries[index].location.toString()),
                    progressAt: (index) {
                      final entry = entries[index];
                      if (entry.part.duration.inMilliseconds <= 0) {
                        return null;
                      }
                      return entry.position.inMilliseconds /
                          entry.part.duration.inMilliseconds;
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
