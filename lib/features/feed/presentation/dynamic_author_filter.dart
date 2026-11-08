import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/user.dart';
import '../../../core/presentation/workspace_activity.dart';
import '../../../shared/ui/network_avatar.dart';
import '../../../shared/ui/smooth_scroll_behavior.dart';
import '../application/dynamic_authors_controller.dart';
import '../application/home_controller.dart';
import '../domain/dynamic_author.dart';

/// Lives outside the channel pager so its selection and scroll positions do not
/// belong to either the rich dynamic feed or the video-only feed.
final class DynamicFeedLayout extends ConsumerStatefulWidget {
  const DynamicFeedLayout({
    super.key,
    required this.visible,
    required this.isSignedIn,
    required this.child,
  });

  final bool visible;
  final bool isSignedIn;
  final Widget child;

  @override
  ConsumerState<DynamicFeedLayout> createState() => _DynamicFeedLayoutState();
}

final class _DynamicFeedLayoutState extends ConsumerState<DynamicFeedLayout> {
  bool _visited = false;

  @override
  Widget build(BuildContext context) {
    final repository = widget.isSignedIn && (widget.visible || _visited)
        ? ref.watch(homeRepositoryProvider)
        : null;
    final supported = widget.isSignedIn && repository is HomeDynamicRepository;
    if (!supported) _visited = false;
    if (supported && widget.visible) _visited = true;
    final scope = repository?.accountScope ?? 'guest';
    final state = _visited ? ref.watch(dynamicAuthorsProvider(scope)) : null;
    final visible = supported && widget.visible;
    final active = visible && WorkspaceActivity.isActive(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Leave at least 600 logical pixels for the existing feed/grid. Large
        // system text needs more room before introducing a second column.
        final wide =
            constraints.maxWidth >=
            880 + (MediaQuery.textScalerOf(context).scale(14) - 14) * 8;
        final height = 72 + MediaQuery.textScalerOf(context).scale(12) * 1.4;
        return Flex(
          direction: wide ? Axis.horizontal : Axis.vertical,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: wide ? (visible ? 224 : 0) : null,
              height: wide ? null : (visible ? height : 0),
              child: TickerMode(
                enabled: active,
                child: ExcludeFocus(
                  excluding: !active,
                  child: Offstage(
                    offstage: !visible,
                    child: state == null
                        ? const SizedBox.shrink()
                        : DynamicAuthorFilter(
                            key: ValueKey(scope),
                            wide: wide,
                            state: state,
                            onSelected: ref
                                .read(dynamicAuthorsProvider(scope).notifier)
                                .select,
                            onRefresh: ref
                                .read(dynamicAuthorsProvider(scope).notifier)
                                .refresh,
                            onLoadMore: ref
                                .read(dynamicAuthorsProvider(scope).notifier)
                                .loadMore,
                          ),
                  ),
                ),
              ),
            ),
            Expanded(child: widget.child),
          ],
        );
      },
    );
  }
}

final class DynamicAuthorFilter extends StatefulWidget {
  const DynamicAuthorFilter({
    super.key,
    required this.wide,
    required this.state,
    required this.onSelected,
    required this.onRefresh,
    required this.onLoadMore,
  });

  final bool wide;
  final DynamicAuthorsState state;
  final ValueChanged<UserId?> onSelected;
  final VoidCallback onRefresh;
  final VoidCallback onLoadMore;

  @override
  State<DynamicAuthorFilter> createState() => _DynamicAuthorFilterState();
}

final class _DynamicAuthorFilterState extends State<DynamicAuthorFilter> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  final _storage = PageStorageBucket();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final state = widget.state;
    final items = [
      if (state.selected case final selected?
          when !state.items.any((item) => item.id == selected.id))
        selected,
      ...state.items,
    ];
    final controller = widget.wide ? _vertical : _horizontal;
    final list = ScrollConfiguration(
      behavior: SmoothScrollBehavior(horizontalMouseWheel: !widget.wide)
          .copyWith(scrollbars: false),
      child: ListView.builder(
        key: PageStorageKey(widget.wide),
        controller: controller,
        primary: false,
        scrollDirection: widget.wide ? Axis.vertical : Axis.horizontal,
        padding: widget.wide
            ? const EdgeInsets.fromLTRB(12, 0, 12, 12)
            : const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemExtent: widget.wide ? 56 : 76,
        itemCount: items.length + 2,
        itemBuilder: (context, index) {
          if (index == items.length + 1) {
            return Center(
              child: state.loading
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      tooltip: state.error != null
                          ? 'UP 主列表加载失败，点击重试'
                          : state.hasMore
                          ? '加载更多 UP 主'
                          : '刷新 UP 主列表',
                      onPressed:
                          state.error != null && state.items.isEmpty ||
                              !state.hasMore
                          ? widget.onRefresh
                          : widget.onLoadMore,
                      icon: Icon(
                        state.error != null
                            ? Icons.refresh
                            : state.hasMore
                            ? Icons.more_horiz
                            : Icons.refresh,
                        color: state.error != null
                            ? colors.error
                            : colors.onSurfaceVariant,
                      ),
                    ),
            );
          }
          final author = index == 0 ? null : items[index - 1];
          return _AuthorChoice(
            key: ValueKey('dynamic-author-${author?.id.value ?? 'all'}'),
            author: author,
            wide: widget.wide,
            selected: state.selected?.id == author?.id,
            onTap: () => widget.onSelected(author?.id),
          );
        },
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          right: widget.wide
              ? BorderSide(color: colors.outlineVariant.withValues(alpha: .45))
              : BorderSide.none,
          bottom: widget.wide
              ? BorderSide.none
              : BorderSide(color: colors.outlineVariant.withValues(alpha: .45)),
        ),
      ),
      child: Column(
        children: [
          if (widget.wide)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '最近更新',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (!state.loading &&
                      state.items.isEmpty &&
                      state.error == null)
                    Text('暂无更新', style: theme.textTheme.labelSmall),
                ],
              ),
            ),
          Expanded(
            child: PageStorage(
              bucket: _storage,
              child: Scrollbar(controller: controller, child: list),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }
}

final class _AuthorChoice extends StatelessWidget {
  const _AuthorChoice({
    super.key,
    required this.author,
    required this.wide,
    required this.selected,
    required this.onTap,
  });

  final DynamicAuthor? author;
  final bool wide;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = author?.name ?? (wide ? '全部动态' : '全部');
    final avatar = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? colors.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: author == null
              ? CircleAvatar(
                  radius: 16,
                  backgroundColor: colors.primaryContainer,
                  foregroundColor: colors.onPrimaryContainer,
                  child: const Icon(Icons.dynamic_feed_outlined, size: 19),
                )
              : NetworkAvatar(url: author?.avatarUrl, name: label, radius: 16),
        ),
        if (author?.hasUpdate == true)
          Positioned(
            top: 2,
            right: 2,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primary,
                border: Border.all(color: colors.surface, width: 1.5),
              ),
            ),
          ),
      ],
    );
    final name = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: wide ? TextAlign.start : TextAlign.center,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        fontSize: wide ? 14 : null,
        height: wide ? 1.25 : null,
        color: colors.onSurface,
        fontWeight: !wide && selected ? FontWeight.w600 : FontWeight.w400,
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Semantics(
        selected: selected,
        button: true,
        label: label,
        child: Tooltip(
          message: label,
          excludeFromSemantics: true,
          child: Material(
            color: selected
                ? colors.primaryContainer.withValues(alpha: .45)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Padding(
                padding: wide
                    ? const EdgeInsets.symmetric(horizontal: 8)
                    : const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: wide
                    ? Row(
                        children: [
                          avatar,
                          const SizedBox(width: 10),
                          Expanded(child: name),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [avatar, const SizedBox(height: 3), name],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
