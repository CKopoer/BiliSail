import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/search_discovery_controller.dart';
import 'search_history_chip.dart';

final class SearchDiscoveryPanel extends StatelessWidget {
  const SearchDiscoveryPanel({
    super.key,
    required this.controller,
    required this.onSearch,
  });
  final TextEditingController controller;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => _SearchDiscoveryContent(
          query: value.text.trim(),
          isComposing: value.composing.isValid && !value.composing.isCollapsed,
          onSearch: onSearch,
        ),
      );
}

final class _SearchDiscoveryContent extends ConsumerStatefulWidget {
  const _SearchDiscoveryContent({
    required this.query,
    required this.isComposing,
    required this.onSearch,
  });
  final String query;
  final bool isComposing;
  final ValueChanged<String> onSearch;
  @override
  ConsumerState<_SearchDiscoveryContent> createState() =>
      _SearchDiscoveryPanelState();
}

final class _SearchDiscoveryPanelState
    extends ConsumerState<_SearchDiscoveryContent> {
  bool _expanded = false;
  bool _savingRecording = false;
  bool _recordingError = false;

  Future<void> _setRecording(bool enabled) async {
    final save = ref.read(searchHistoryRecordingWriterProvider);
    if (save == null || _savingRecording) return;
    setState(() {
      _savingRecording = true;
      _recordingError = false;
    });
    try {
      await save(enabled);
    } catch (_) {
      if (mounted) setState(() => _recordingError = true);
    } finally {
      if (mounted) setState(() => _savingRecording = false);
    }
  }

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
    if (widget.query.isNotEmpty) {
      // Pause draft queries without unmounting the retained suggestion list.
      return _SearchSuggestions(
        query: widget.isComposing ? '' : widget.query,
        onSearch: widget.onSearch,
      );
    }
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
          if (ref.watch(searchHistoryRecordingWriterProvider) != null)
            Row(
              children: [
                const Expanded(child: Text('记录搜索历史')),
                Switch.adaptive(
                  key: const ValueKey('search-history-recording'),
                  value: ref.watch(searchHistoryRecordingProvider),
                  onChanged: _savingRecording
                      ? null
                      : (value) => unawaited(_setRecording(value)),
                ),
              ],
            ),
          if (!ref.watch(searchHistoryRecordingProvider))
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('已关闭历史记录，新搜索不会保存'),
            ),
          if (_recordingError) const Text('搜索历史设置保存失败，请重试'),
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
                SearchHistoryChip(
                  key: ValueKey(('search-history', query)),
                  query: query,
                  onSearch: () => widget.onSearch(query),
                  onDelete: () => unawaited(controller.removeHistory(query)),
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

final class _SearchSuggestions extends ConsumerStatefulWidget {
  const _SearchSuggestions({required this.query, required this.onSearch});
  final String query;
  final ValueChanged<String> onSearch;

  @override
  ConsumerState<_SearchSuggestions> createState() => _SearchSuggestionsState();
}

final class _SearchSuggestionsState extends ConsumerState<_SearchSuggestions> {
  String? _scope;
  List<String> _items = const [];

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(searchHistoryScopeProvider);
    if (_scope != scope) {
      _scope = scope;
      _items = const [];
    }
    final provider = searchSuggestionsProvider(widget.query);
    final result = ref.watch(provider);
    final items = result.asData?.value;
    // Retain only this panel's last nonempty result while the next query loads.
    if (items != null && items.isNotEmpty) _items = items;
    return SingleChildScrollView(
      key: const ValueKey('search-discovery-panel'),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('搜索联想', style: Theme.of(context).textTheme.titleSmall),
          for (final term in _items)
            ListTile(
              key: ValueKey(('search-suggestion', term)),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.search, size: 18),
              title: Text(term, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => widget.onSearch(term),
            ),
          if (result.hasError)
            Row(
              children: [
                const Expanded(child: Text('搜索联想暂时无法加载')),
                TextButton(
                  onPressed: () => ref.invalidate(provider),
                  child: const Text('重试'),
                ),
              ],
            ),
          if (widget.query.isNotEmpty &&
              _items.isEmpty &&
              !result.isLoading &&
              !result.hasError)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('暂无联想词，可直接提交搜索'),
            ),
        ],
      ),
    );
  }
}
