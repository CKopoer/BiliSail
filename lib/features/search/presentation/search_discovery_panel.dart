import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/search_discovery_controller.dart';

final class SearchDiscoveryPanel extends ConsumerStatefulWidget {
  const SearchDiscoveryPanel({super.key, required this.onSearch});
  final ValueChanged<String> onSearch;
  @override
  ConsumerState<SearchDiscoveryPanel> createState() =>
      _SearchDiscoveryPanelState();
}

final class _SearchDiscoveryPanelState
    extends ConsumerState<SearchDiscoveryPanel> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        unawaited(
          ref.read(searchDiscoveryControllerProvider.notifier).loadTrending(),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(searchHistoryScopeProvider, (_, _) {
      Future.microtask(() {
        if (mounted) {
          unawaited(
            ref.read(searchDiscoveryControllerProvider.notifier).loadTrending(),
          );
        }
      });
    });
    final state = ref.watch(searchDiscoveryControllerProvider);
    final controller = ref.read(searchDiscoveryControllerProvider.notifier);
    final theme = Theme.of(context);
    final history = _expanded ? state.history : state.history.take(10);
    return SingleChildScrollView(
      key: const ValueKey('search-discovery-panel'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('搜索历史', style: theme.textTheme.titleSmall)),
              TextButton(
                onPressed: state.history.isEmpty && !state.historyError
                    ? null
                    : () => unawaited(controller.clearHistory()),
                child: const Text('清空'),
              ),
            ],
          ),
          if (state.historyError)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('搜索历史读写失败，请稍后重试'),
            ),
          if (state.history.isEmpty && !state.historyError)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('暂无搜索历史', style: theme.textTheme.bodySmall),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final query in history)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Tooltip(
                    message: query,
                    child: ActionChip(
                      label: Text(
                        query,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      side: BorderSide.none,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      onPressed: () => widget.onSearch(query),
                    ),
                  ),
                ),
            ],
          ),
          if (state.history.length > 10)
            Align(
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                label: Text(_expanded ? '收起' : '展开更多'),
                icon: Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                ),
                iconAlignment: IconAlignment.end,
              ),
            ),
          const SizedBox(height: 20),
          Text('热搜', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          state.trending.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (_, _) => Row(
              children: [
                const Expanded(child: Text('热搜暂时无法加载')),
                TextButton(
                  onPressed: () =>
                      unawaited(controller.loadTrending(force: true)),
                  child: const Text('重试'),
                ),
              ],
            ),
            data: (items) => items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('暂无热搜'),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final columns =
                          constraints.maxWidth >= 380 &&
                              MediaQuery.textScalerOf(context).scale(14) <= 20
                          ? 2
                          : 1;
                      final rows = (items.length / columns).ceil();
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var column = 0; column < columns; column++)
                            Expanded(
                              child: Column(
                                children: [
                                  for (var row = 0; row < rows; row++)
                                    if (column * rows + row < items.length)
                                      Builder(
                                        builder: (context) {
                                          final index = column * rows + row;
                                          final item = items[index];
                                          return Tooltip(
                                            message: item.label,
                                            child: InkWell(
                                              key: ValueKey(
                                                'search-trend-$index',
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              onTap: () =>
                                                  widget.onSearch(item.keyword),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 12,
                                                      horizontal: 4,
                                                    ),
                                                child: Row(
                                                  children: [
                                                    SizedBox(
                                                      width: 28,
                                                      child: Text(
                                                        '${index + 1}',
                                                        style: TextStyle(
                                                          color: index < 3
                                                              ? theme
                                                                    .colorScheme
                                                                    .primary
                                                              : theme
                                                                    .colorScheme
                                                                    .onSurfaceVariant,
                                                        ),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      child: Text(
                                                        item.label,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
