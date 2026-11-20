import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide SearchController;

import '../../../core/presentation/workspace_activity.dart';
import '../../../shared/ui/app_dialog.dart';
import '../../../shared/ui/smooth_scroll_behavior.dart';
import '../application/search_controller.dart';
import '../domain/search_result.dart';

final class SearchFilterToolbar extends ConsumerWidget {
  const SearchFilterToolbar({super.key, required this.result});

  final SearchState result;

  bool _matchesSearch(BuildContext context, WidgetRef ref) {
    if (!WorkspaceActivity.isActive(context)) return false;
    final current = ref.read(searchControllerProvider);
    return current.query == result.query && current.category == result.category;
  }

  Future<void> _pickOrder(BuildContext context, WidgetRef ref) async {
    final order = await _showSearchSheet<SearchOrder>(
      context,
      (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetHeader(title: '排序方式', closeTooltip: '关闭排序'),
          const Divider(),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Column(
                children: [
                  for (final order in result.category.orders)
                    ListTile(
                      title: Text(order.label),
                      selected: result.order == order,
                      trailing: result.order == order
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: () {
                        if (ModalRoute.of(sheetContext)?.isCurrent == true) {
                          Navigator.of(sheetContext).pop(order);
                        }
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (order == null || !context.mounted || !_matchesSearch(context, ref)) {
      return;
    }
    await ref.read(searchControllerProvider.notifier).selectOrder(order);
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, bool wide) async {
    final selection = wide
        ? await showAppDialog<_SearchFilterSelection>(
            context: context,
            builder: (context) => Dialog(
              constraints: const BoxConstraints(maxWidth: 680),
              child: _SearchFilterEditor(result: result, wide: true),
            ),
          )
        : await _showSearchSheet<_SearchFilterSelection>(
            context,
            (_) => _SearchFilterEditor(result: result, wide: false),
          );
    if (selection == null ||
        !context.mounted ||
        !_matchesSearch(context, ref)) {
      return;
    }
    await ref
        .read(searchControllerProvider.notifier)
        .applyFilters(
          category: result.category,
          order: selection.order,
          duration: selection.duration,
          userType: selection.userType,
          videoZone: selection.videoZone,
          articleZone: selection.articleZone,
          publicationPeriod: selection.publicationPeriod,
          publicationRange: selection.publicationRange,
        );
  }

  String _filterLabel(BuildContext context, SearchFilterField field) =>
      switch (field) {
        SearchFilterField.duration => result.duration.label,
        SearchFilterField.videoZone => result.videoZone.label,
        SearchFilterField.articleZone => result.articleZone.label,
        SearchFilterField.userType => result.userType.label,
        SearchFilterField.publicationPeriod => _publicationLabel(
          context,
          result.publicationPeriod,
          result.publicationRange,
        ),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = result.category.orders;
    if (result.query.isEmpty || orders.length < 2) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final filters = result.activeFilters;
    final count = filters.length + (result.order == orders.first ? 0 : 1);
    final controller = ref.read(searchControllerProvider.notifier);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final inset = constraints.maxWidth < 600 ? 12.0 : 28.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(inset, 4, inset, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: wide
                        ? _SearchOrderStrip(
                            key: ValueKey(result.category),
                            orders: orders,
                            selected: result.order,
                            onSelected: controller.selectOrder,
                          )
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              key: const ValueKey('search-quick-order'),
                              onPressed: () => _pickOrder(context, ref),
                              style: TextButton.styleFrom(
                                foregroundColor: colors.onSurface,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              iconAlignment: IconAlignment.end,
                              icon: const Icon(
                                Icons.expand_more_rounded,
                                size: 18,
                              ),
                              label: Text(
                                result.order.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                  ),
                  TextButton.icon(
                    key: const ValueKey('search-more-filters'),
                    onPressed: () => _edit(context, ref, wide),
                    style: TextButton.styleFrom(
                      backgroundColor: colors.surfaceContainerLow,
                      foregroundColor: colors.onSurface,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 6,
                      children: [
                        const Text('筛选'),
                        if (count > 0)
                          Badge(
                            backgroundColor: colors.primaryContainer,
                            textColor: colors.onPrimaryContainer,
                            label: Text('$count'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (filters.isNotEmpty)
                Wrap(
                  spacing: 6,
                  children: [
                    for (final field in filters)
                      _ActiveFilterChip(
                        label: _filterLabel(context, field),
                        onRemove: () => controller.removeFilter(field),
                      ),
                  ],
                ),
              const Divider(),
            ],
          ),
        );
      },
    );
  }
}

Future<T?> _showSearchSheet<T>(BuildContext context, WidgetBuilder builder) =>
    showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (context) => LayoutBuilder(
        builder: (context, constraints) => ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight * .9),
          child: SafeArea(top: false, child: builder(context)),
        ),
      ),
    );

final class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: '移除筛选：$label',
      child: TextButton.icon(
        onPressed: onRemove,
        iconAlignment: IconAlignment.end,
        icon: const Icon(Icons.close_rounded, size: 14),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          backgroundColor: theme.colorScheme.primaryContainer,
          textStyle: theme.textTheme.labelMedium,
          minimumSize: const Size(0, 28),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    );
  }
}

final class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, required this.closeTooltip});

  final String title, closeTooltip;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        IconButton(
          tooltip: closeTooltip,
          onPressed: () {
            if (ModalRoute.of(context)?.isCurrent == true) {
              Navigator.of(context).pop();
            }
          },
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
  );
}

final class _SearchOrderStrip extends StatelessWidget {
  const _SearchOrderStrip({
    super.key,
    required this.orders,
    required this.selected,
    required this.onSelected,
  });

  final List<SearchOrder> orders;
  final SearchOrder selected;
  final ValueChanged<SearchOrder> onSelected;

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: const SmoothScrollBehavior(horizontalMouseWheel: true).copyWith(
        dragDevices: {
          ...const SmoothScrollBehavior().dragDevices,
          PointerDeviceKind.mouse,
        },
      ),
      child: SingleChildScrollView(
        key: const ValueKey('search-order-strip'),
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            for (final order in orders)
              _FilterOption(
                label: order.label,
                selected: order == selected,
                onPressed: () => onSelected(order),
              ),
          ],
        ),
      ),
    );
  }
}

typedef _SearchFilterSelection = ({
  SearchOrder order,
  SearchDuration duration,
  SearchUserType userType,
  SearchVideoZone videoZone,
  SearchArticleZone articleZone,
  SearchPublicationPeriod publicationPeriod,
  SearchPublicationRange? publicationRange,
});

final class _SearchFilterEditor extends StatefulWidget {
  const _SearchFilterEditor({required this.result, required this.wide});

  final SearchState result;
  final bool wide;

  @override
  State<_SearchFilterEditor> createState() => _SearchFilterEditorState();
}

final class _SearchFilterEditorState extends State<_SearchFilterEditor> {
  late var _order = widget.result.order;
  late var _duration = widget.result.duration;
  late var _userType = widget.result.userType;
  late var _videoZone = widget.result.videoZone;
  late var _articleZone = widget.result.articleZone;
  late var _period = widget.result.publicationPeriod;
  late var _range = _period == SearchPublicationPeriod.customRange
      ? widget.result.publicationRange
      : null;

  void _reset() => setState(() {
    _order = widget.result.category.orders.first;
    _duration = SearchDuration.any;
    _userType = SearchUserType.any;
    _videoZone = SearchVideoZone.any;
    _articleZone = SearchArticleZone.any;
    _period = SearchPublicationPeriod.any;
    _range = null;
  });

  void _dismiss([_SearchFilterSelection? selection]) {
    if (ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop(selection);
    }
  }

  void _apply() => _dismiss((
    order: _order,
    duration: _duration,
    userType: _userType,
    videoZone: _videoZone,
    articleZone: _articleZone,
    publicationPeriod: _period,
    publicationRange: _period == SearchPublicationPeriod.customRange
        ? _range
        : null,
  ));

  Future<void> _selectPeriod(SearchPublicationPeriod period) async {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    if (period != SearchPublicationPeriod.customRange) {
      setState(() => _period = period);
      return;
    }
    final first = DateTime(2009, 6, 26);
    final today = DateUtils.dateOnly(DateTime.now());
    final existing = _range;
    final selected = await showAppDialog<DateTimeRange>(
      context: context,
      builder: (context) => DateRangePickerDialog(
        firstDate: first,
        lastDate: today,
        initialDateRange:
            existing != null &&
                !existing.start.isBefore(first) &&
                !existing.end.isAfter(today)
            ? DateTimeRange(start: existing.start, end: existing.end)
            : null,
        initialEntryMode: widget.wide
            ? DatePickerEntryMode.input
            : DatePickerEntryMode.calendar,
        helpText: '选择发布日期',
        cancelText: '取消',
        confirmText: '确定',
        saveText: '确定',
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _period = period;
      _range = SearchPublicationRange(start: selected.start, end: selected.end);
    });
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.result.category;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SheetHeader(title: '搜索筛选', closeTooltip: '关闭筛选'),
        const Divider(),
        Flexible(
          child: SingleChildScrollView(
            key: const ValueKey('search-filter-options'),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                _FilterGroup(
                  title: '排序',
                  choices: category.orders,
                  selected: _order,
                  label: (order) => order.label,
                  onSelected: (order) => setState(() => _order = order),
                ),
                if (category.hasVideoFilters) ...[
                  _FilterGroup(
                    title: '内容时长',
                    choices: SearchDuration.values,
                    selected: _duration,
                    label: (duration) => duration.label,
                    onSelected: (duration) =>
                        setState(() => _duration = duration),
                  ),
                  _FilterGroup(
                    title: '发布时间',
                    choices: SearchPublicationPeriod.values,
                    selected: _period,
                    label: (period) => _publicationLabel(
                      context,
                      period,
                      period == _period ? _range : null,
                    ),
                    onSelected: _selectPeriod,
                  ),
                  _FilterGroup(
                    title: '内容分区',
                    choices: SearchVideoZone.values,
                    selected: _videoZone,
                    label: (zone) => zone.label,
                    onSelected: (zone) => setState(() => _videoZone = zone),
                  ),
                ],
                if (category.hasArticleFilters)
                  _FilterGroup(
                    title: '专栏分区',
                    choices: SearchArticleZone.values,
                    selected: _articleZone,
                    label: (zone) => zone.label,
                    onSelected: (zone) => setState(() => _articleZone = zone),
                  ),
                if (category.hasUserFilters)
                  _FilterGroup(
                    title: '用户类型',
                    choices: SearchUserType.values,
                    selected: _userType,
                    label: (type) => type.label,
                    onSelected: (type) => setState(() => _userType = type),
                  ),
              ],
            ),
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 6,
            children: [
              TextButton(onPressed: _reset, child: const Text('重置')),
              FilledButton(onPressed: _apply, child: const Text('应用筛选')),
            ],
          ),
        ),
      ],
    );
  }
}

final class _FilterGroup<T> extends StatelessWidget {
  const _FilterGroup({
    required this.title,
    required this.choices,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  final String title;
  final List<T> choices;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final heading = Semantics(
      header: true,
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
    final options = Wrap(
      spacing: 4,
      children: [
        for (final choice in choices)
          _FilterOption(
            label: label(choice),
            selected: choice == selected,
            onPressed: () => onSelected(choice),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelWidth = MediaQuery.textScalerOf(context).scale(14) * 5;
        if (constraints.maxWidth >= 600 &&
            labelWidth < constraints.maxWidth / 4) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: labelWidth,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: heading,
                ),
              ),
              Expanded(child: options),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [heading, options],
        );
      },
    );
  }
}

final class _FilterOption extends StatelessWidget {
  const _FilterOption({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      selected: selected,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: selected
              ? colors.onPrimaryContainer
              : colors.onSurface,
          backgroundColor: selected ? colors.primaryContainer : null,
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: theme.textTheme.labelLarge?.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

String _publicationLabel(
  BuildContext context,
  SearchPublicationPeriod period,
  SearchPublicationRange? range,
) {
  if (period != SearchPublicationPeriod.customRange || range == null) {
    return period.label;
  }
  final localizations = MaterialLocalizations.of(context);
  return '${localizations.formatCompactDate(range.start)} – '
      '${localizations.formatCompactDate(range.end)}';
}
