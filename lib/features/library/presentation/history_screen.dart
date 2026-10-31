import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/app_failure.dart';
import '../../../core/network/api_requests.dart';
import '../../../core/presentation/workspace_activity.dart';
import '../../../shared/ui/app_dialog.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../shared/ui/paged_scroll_viewport.dart';
import '../../../shared/ui/responsive_card_grid.dart';
import '../../../shared/ui/state_view.dart';
import '../../../shared/ui/video_grid.dart';
import '../../../shared/ui/video_card.dart';
import '../application/library_controller.dart';
import '../domain/library_repository.dart';

final class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key, this.showHeading = true});

  final bool showHeading;

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();

  static Future<void> _perform(
    BuildContext context,
    WidgetRef ref,
    Future<bool> Function(HistoryController) operation,
    String success,
  ) async {
    if (!WorkspaceActivity.isActive(context)) return;
    final scope = ref.read(libraryRepositoryProvider).accountScope;
    final epoch = ref.read(sessionEpochProvider)();
    String? message;
    try {
      if (await operation(ref.read(historyProvider.notifier))) {
        message = success;
      }
    } on HistoryWriteUncertain {
      message = '操作结果暂时无法确认，请刷新历史记录核对';
    } on AppFailure catch (failure) {
      if (failure.kind != AppFailureKind.cancelled) message = failure.message;
    }
    if (context.mounted &&
        scope == ref.read(libraryRepositoryProvider).accountScope &&
        epoch == ref.read(sessionEpochProvider)() &&
        WorkspaceActivity.isActive(context) &&
        message != null) {
      showAppNotice(context, message);
    }
  }

  static Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    if (!WorkspaceActivity.isActive(context)) return;
    final scope = ref.read(libraryRepositoryProvider).accountScope;
    final epoch = ref.read(sessionEpochProvider)();
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('清空观看历史？'),
        content: const Text('将清空当前账号在所有设备上的全部云端观看历史，包括本页未显示的直播、专栏等记录。此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !context.mounted ||
        scope != ref.read(libraryRepositoryProvider).accountScope ||
        epoch != ref.read(sessionEpochProvider)()) {
      return;
    }
    await _perform(
      context,
      ref,
      (controller) => controller.clear(),
      '已清空云端观看历史',
    );
  }

  static String _watchedAt(DateTime value) {
    final date = value.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '观看于 ${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
  }

  static String _watchDate(DateTime value) {
    final date = value.toLocal();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return date.year == DateTime.now().year
        ? '$month-$day'
        : '${date.year}-$month-$day';
  }
}

final class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late final TextEditingController _searchText;
  final _searchFocus = FocusNode();
  bool _searchExpanded = false;

  @override
  void initState() {
    super.initState();
    final keyword = ref.read(historyProvider).keyword;
    _searchText = TextEditingController(text: keyword);
    _searchExpanded = keyword.isNotEmpty;
  }

  @override
  void dispose() {
    _searchText.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    if (!WorkspaceActivity.isActive(context)) return;
    setState(() => _searchExpanded = !_searchExpanded);
    if (_searchExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _searchExpanded && WorkspaceActivity.isActive(context)) {
          _searchFocus.requestFocus();
        }
      });
    } else {
      _searchFocus.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(historyProvider.select((state) => state.keyword), (_, keyword) {
      if (_searchText.text != keyword) _searchText.text = keyword;
    });
    final history = ref.watch(historyProvider);
    final controller = ref.read(historyProvider.notifier);
    return PagedScrollViewport(
      key: ValueKey(history.keyword),
      keepScrollOffset: false,
      active: true,
      canLoadMore:
          history.hasMore &&
          !history.loadingMore &&
          history.pageError == null &&
          !history.writeBusy &&
          !history.writeUncertain,
      contentVersion: history.items,
      onLoadMore: controller.loadMore,
      onRefresh: controller.refresh,
      refreshTooltip: '刷新云端观看历史',
      builder: (scrollController) => RefreshIndicator(
        onRefresh: controller.refresh,
        child: CustomScrollView(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverCardGridPadding(
              top: widget.showHeading ? 16 : 8,
              bottom: 84,
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final inlineSearch =
                              constraints.maxWidth >=
                              840 *
                                  MediaQuery.textScalerOf(context).scale(14) /
                                  14;
                          final search = _HistorySearchField(
                            keyword: history.keyword,
                            enabled: !history.writeBusy,
                            textController: _searchText,
                            focusNode: _searchFocus,
                          );
                          final showClearLabel =
                              constraints.maxWidth >=
                              280 *
                                  MediaQuery.textScalerOf(context).scale(14) /
                                  14;
                          final repository = ref.watch(
                            libraryRepositoryProvider,
                          );
                          final enabled =
                              repository is WatchHistoryMutations &&
                              repository.accountScope.startsWith('user:') &&
                              history.items.asData != null &&
                              !history.writeBusy &&
                              !history.writeUncertain;
                          final icon = history.writeBusy
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.delete_sweep_outlined);
                          final action = enabled
                              ? () => HistoryScreen._confirmClear(context, ref)
                              : null;
                          final toolbar = Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (widget.showHeading) ...[
                                      Text(
                                        '观看历史',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge,
                                      ),
                                      const SizedBox(height: 7),
                                    ],
                                    Text(
                                      constraints.maxWidth < 600
                                          ? '云端观看记录'
                                          : '当前账号的云端观看记录',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                    if (history.writeUncertain)
                                      const Text('操作结果待确认，请刷新核对'),
                                  ],
                                ),
                              ),
                              if (inlineSearch) ...[
                                const SizedBox(width: 16),
                                SizedBox(width: 320, child: search),
                              ] else
                                IconButton(
                                  key: const ValueKey('history-search-toggle'),
                                  tooltip: _searchExpanded ? '收起搜索' : '展开搜索',
                                  isSelected: _searchExpanded,
                                  onPressed: history.writeBusy
                                      ? null
                                      : _toggleSearch,
                                  icon: Icon(
                                    _searchExpanded
                                        ? Icons.close
                                        : Icons.search,
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 48,
                                    minHeight: 48,
                                  ),
                                  visualDensity: VisualDensity.standard,
                                ),
                              const SizedBox(width: 12),
                              if (showClearLabel)
                                TextButton.icon(
                                  key: const ValueKey('history-clear'),
                                  onPressed: action,
                                  icon: icon,
                                  label: const Text('清空历史'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Theme.of(context)
                                        .colorScheme
                                        .error,
                                    minimumSize: const Size(48, 48),
                                    visualDensity: VisualDensity.standard,
                                  ),
                                )
                              else
                                IconButton(
                                  key: const ValueKey('history-clear'),
                                  tooltip: '清空历史',
                                  onPressed: action,
                                  icon: icon,
                                  color: Theme.of(context).colorScheme.error,
                                  visualDensity: VisualDensity.standard,
                                  constraints: const BoxConstraints(
                                    minWidth: 48,
                                    minHeight: 48,
                                  ),
                                ),
                            ],
                          );
                          return inlineSearch
                              ? toolbar
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    toolbar,
                                    if (_searchExpanded) ...[
                                      const SizedBox(height: 8),
                                      search,
                                    ],
                                  ],
                                );
                        },
                      ),
                    ),
                  ),
                  const _HistoryEntriesSliver(),
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        if (history.loadingMore)
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        if (history.pageError case final error?)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: StateView.error(
                              message: error is AppFailure
                                  ? error.message
                                  : '更多历史加载失败',
                              onAction: controller.loadMore,
                            ),
                          ),
                        if (history.limitReached)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('已显示 500 条记录，可更换关键词继续查找'),
                          ),
                      ],
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

final class _HistorySearchField extends ConsumerWidget {
  const _HistorySearchField({
    required this.keyword,
    required this.enabled,
    required this.textController,
    required this.focusNode,
  });

  final String keyword;
  final bool enabled;
  final TextEditingController textController;
  final FocusNode focusNode;

  void _submit(BuildContext context, WidgetRef ref, String keyword) {
    if (!enabled || !WorkspaceActivity.isActive(context)) return;
    FocusScope.of(context).unfocus();
    final query = keyword.trim();
    textController.text = query;
    ref.read(historyProvider.notifier).search(query);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: textController,
        builder: (context, value, _) => TextField(
          key: const ValueKey('history-search'),
          controller: textController,
          focusNode: focusNode,
          enabled: enabled,
          textInputAction: TextInputAction.search,
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            hintText: '搜索观看历史',
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerLow,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (value.text.isNotEmpty || keyword.isNotEmpty)
                  IconButton(
                    tooltip: '清除搜索',
                    onPressed: enabled
                        ? () {
                            textController.clear();
                            _submit(context, ref, '');
                          }
                        : null,
                    icon: const Icon(Icons.close, size: 20),
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    visualDensity: VisualDensity.standard,
                  ),
                IconButton(
                  tooltip: '搜索观看历史',
                  onPressed: enabled
                      ? () => _submit(context, ref, textController.text)
                      : null,
                  icon: const Icon(Icons.search, size: 20),
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  visualDensity: VisualDensity.standard,
                ),
              ],
            ),
          ),
          onSubmitted: (value) => _submit(context, ref, value),
        ),
      ),
    );
  }
}

// Paging status changes affect the footer without rebuilding unchanged cards.
final class _HistoryEntriesSliver extends ConsumerWidget {
  const _HistoryEntriesSliver();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(historyProvider.select((state) => state.items));
    final searching = ref.watch(
      historyProvider.select((state) => state.keyword.isNotEmpty),
    );
    final controller = ref.read(historyProvider.notifier);
    final writeBlocked = ref.watch(
      historyProvider.select(
        (state) => state.writeBusy || state.writeUncertain,
      ),
    );
    return items.when(
      loading: () => const SliverToBoxAdapter(
        child: SizedBox(height: 300, child: StateView.loading()),
      ),
      error: (error, _) => SliverToBoxAdapter(
        child: SizedBox(
          height: 300,
          child: StateView.error(
            message: error is AppFailure ? error.message : '历史记录加载失败',
            onAction: controller.refresh,
          ),
        ),
      ),
      data: (entries) => entries.isEmpty
          ? SliverToBoxAdapter(
              child: SizedBox(
                height: 280,
                child: StateView.empty(
                  message: searching ? '未找到相关观看记录，试试其他关键词' : '还没有云端观看记录',
                ),
              ),
            )
          : SliverVideoGrid.indexed(
              onOpenUser: (id) => context.go('/user/${id.value}'),
              items: [for (final entry in entries) entry.video],
              menuAt: (index) => VideoCardMenu(
                actions: const [VideoCardMenuAction.removeHistory],
                busy: writeBlocked,
                onSelected: (_) => HistoryScreen._perform(
                  context,
                  ref,
                  (controller) => controller.delete(entries[index]),
                  '已删除观看记录',
                ),
              ),
              onOpen: (index) => context.go(entries[index].location.toString()),
              publishTextAt: (index) =>
                  HistoryScreen._watchDate(entries[index].watchedAt),
              publishTooltipAt: (index) =>
                  HistoryScreen._watchedAt(entries[index].watchedAt),
              progressAt: (index) {
                final entry = entries[index];
                if (entry.part.duration.inMilliseconds <= 0) {
                  return null;
                }
                return (entry.position.inMilliseconds /
                        entry.part.duration.inMilliseconds)
                    .clamp(0, 1);
              },
            ),
    );
  }
}
