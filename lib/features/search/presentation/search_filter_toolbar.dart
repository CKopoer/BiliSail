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

  Future<void> _edit(BuildContext context, WidgetRef ref, bool wide) async {
    final selection = wide
        ? await showAppDialog<_SearchFilterSelection>(
            context: context,
            builder: (context) => Dialog(
              constraints: const BoxConstraints(maxWidth: 680),
              child: _SearchFilterEditor(result: result, wide: wide),
            ),
          )
        : await showModalBottomSheet<_SearchFilterSelection>(
            context: context,
            useRootNavigator: true,
            useSafeArea: true,
            isScrollControlled: true,
            showDragHandle: true,
            constraints: const BoxConstraints(maxWidth: 640),
            builder: (context) => LayoutBuilder(
              builder: (context, constraints) => ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * .9,
                ),
                child: SafeArea(
                  top: false,
                  child: _SearchFilterEditor(result: result, wide: wide),
                ),
              ),
            ),
          );
    if (selection == null ||
        !context.mounted ||
        !WorkspaceActivity.isActive(context)) {
      return;
    }
    final current = ref.read(searchControllerProvider);
    if (current.query != result.query || current.category != result.category) {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = result.category.orders;
    if (result.query.isEmpty || orders.length < 2) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final details = [
      if (result.duration != SearchDuration.any) result.duration.label,
      if (result.videoZone != SearchVideoZone.any) result.videoZone.label,
      if (result.articleZone != SearchArticleZone.any) result.articleZone.label,
      if (result.publicationPeriod != SearchPublicationPeriod.any)
        _publicationLabel(
          context,
          result.publicationPeriod,
          result.publicationRange,
        ),
      if (result.userType != SearchUserType.any) result.userType.label,
    ];
    final activeCount = details.length + (result.order == orders.first ? 0 : 1);
    final activeDetails = details.join(' · ');
    final detailStyle = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final inset = constraints.maxWidth < 600 ? 12.0 : 28.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(inset, 6, inset, 4),
          child: Material(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                onSelected: ref
                                    .read(searchControllerProvider.notifier)
                                    .selectOrder,
                              )
                            : Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Text(
                                  [result.order.label, ...details].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: detailStyle,
                                ),
                              ),
                      ),
                      TextButton.icon(
                        key: const ValueKey('search-more-filters'),
                        onPressed: () => _edit(context, ref, wide),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: const Size(48, 48),
                          visualDensity: VisualDensity.standard,
                          foregroundColor: activeCount == 0
                              ? colors.onSurface
                              : colors.primary,
                        ),
                        icon: const Icon(Icons.tune_rounded, size: 20),
                        label: Text(
                          activeCount == 0 ? '筛选' : '筛选 ($activeCount)',
                        ),
                      ),
                    ],
                  ),
                  if (wide && details.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: Text(
                        activeDetails,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: detailStyle,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
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
    final colors = Theme.of(context).colorScheme;
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
              Semantics(
                selected: order == selected,
                child: TextButton(
                  onPressed: () => onSelected(order),
                  style: TextButton.styleFrom(
                    foregroundColor: order == selected
                        ? colors.onPrimaryContainer
                        : colors.onSurfaceVariant,
                    backgroundColor: order == selected
                        ? colors.primaryContainer
                        : null,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: Text(order.label),
                ),
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
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
          child: Row(
            children: [
              Expanded(child: Text('搜索筛选', style: theme.textTheme.titleMedium)),
              IconButton(
                tooltip: '关闭筛选',
                onPressed: _dismiss,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        const Divider(),
        Flexible(
          child: SingleChildScrollView(
            key: const ValueKey('search-filter-options'),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 16,
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 6,
    children: [
      Semantics(
        header: true,
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final choice in choices)
            ChoiceChip(
              label: Text(label(choice)),
              selected: choice == selected,
              onSelected: (_) => onSelected(choice),
            ),
        ],
      ),
    ],
  );
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
