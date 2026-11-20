import 'package:material_ui/material_ui.dart';

import '../../../shared/ui/catalog_card_cover.dart';
import '../../../shared/ui/live_room_tile.dart';
import '../../../shared/ui/responsive_card_grid.dart';
import '../../../shared/ui/bili_badges.dart';
import '../../../shared/ui/network_avatar.dart';
import '../../../shared/ui/video_card.dart';
import '../../../shared/ui/video_grid.dart';
import '../../../shared/ui/highlighted_text.dart';
import '../../../shared/ui/workspace_link.dart';
import '../domain/search_result.dart';

final class SearchResults extends StatelessWidget {
  const SearchResults({
    super.key,
    required this.items,
    required this.query,
    required this.category,
    required this.onCategory,
  });
  final List<SearchEntry> items;
  final String query;
  final SearchCategory category;
  final ValueChanged<SearchCategory> onCategory;

  @override
  Widget build(BuildContext context) {
    // Partition models once per result update; card creation stays in builders.
    final users = items.whereType<SearchUserEntry>().toList(growable: false);
    final videos = items.whereType<SearchVideoEntry>().toList(growable: false);
    final media = items.whereType<SearchMediaEntry>().toList(growable: false);
    final lives = items.whereType<SearchLiveEntry>().toList(growable: false);
    final articles = items.whereType<SearchArticleEntry>().toList(
      growable: false,
    );
    return SliverMainAxisGroup(
      slivers: [
        if (users.isNotEmpty)
          SliverList.builder(
            itemCount: users.length,
            itemBuilder: (context, index) => Padding(
              key: ValueKey(users[index].key),
              padding: const EdgeInsets.only(bottom: 24),
              child: _UserCard(
                user: users[index],
                query: query,
                featured: category == SearchCategory.all,
              ),
            ),
          ),
        for (final type in [SearchCategory.bangumi, SearchCategory.film])
          if (media.any((item) => item.category == type)) ...[
            if (category == SearchCategory.all)
              SliverToBoxAdapter(child: _section(context, type)),
            _SliverResultGrid(
              items: media
                  .where((item) => item.category == type)
                  .toList(growable: false),
              itemBuilder: (context, item) =>
                  _MediaCard(item: item, query: query),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],
        if (lives.isNotEmpty) ...[
          if (category == SearchCategory.all)
            SliverToBoxAdapter(child: _section(context, SearchCategory.live)),
          SliverResponsiveCardGrid(
            itemCount: lives.length,
            itemBuilder: (context, index) {
              final item = lives[index];
              final author = item.authorId;
              return LiveRoomTile(
                key: ValueKey(item.key),
                roomId: item.id,
                title: item.title,
                author: item.author,
                coverUrl: item.coverUrl,
                popularity: item.online?.toString() ?? '',
                area: item.area,
                isLive: item.isLive,
                highlightQuery: query,
                onOpen: () =>
                    context.openWorkspaceLink('/live/${item.id.value}'),
                onOpenAuthor: author == null
                    ? null
                    : () => context.openWorkspaceLink('/user/${author.value}'),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
        if (articles.isNotEmpty) ...[
          if (category == SearchCategory.all)
            SliverToBoxAdapter(
              child: _section(context, SearchCategory.article),
            ),
          _SliverResultGrid(
            items: articles,
            itemBuilder: (context, item) => _ArticleCard(
              item: item,
              query: query,
              onOpen: () =>
                  context.openWorkspaceLink(item.readAddress.location),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
        if (videos.isNotEmpty) ...[
          if (category == SearchCategory.all &&
              items.any((item) => item is! SearchVideoEntry))
            SliverToBoxAdapter(child: _section(context, SearchCategory.video)),
          SliverVideoGrid(
            items: videos.map((item) => item.video).toList(growable: false),
            highlightQuery: query,
            onOpen: (id) => context.openWorkspaceLink('/video/${id.value}'),
            onOpenUser: (id) => context.openWorkspaceLink('/user/${id.value}'),
          ),
        ],
      ],
    );
  }

  Widget _section(BuildContext context, SearchCategory type) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        Text(type.label, style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        TextButton(
          onPressed: () => onCategory(type),
          child: Text('查看更多${type.label} ›'),
        ),
      ],
    ),
  );
}

/// Rows of results with a cover beside the text need wider columns.
final class _SliverResultGrid<T extends SearchEntry> extends StatefulWidget {
  const _SliverResultGrid({required this.items, required this.itemBuilder});
  final List<T> items;
  final Widget Function(BuildContext, T) itemBuilder;
  @override
  State<_SliverResultGrid<T>> createState() => _SliverResultGridState<T>();
}

final class _SliverResultGridState<T extends SearchEntry>
    extends State<_SliverResultGrid<T>> {
  ({int columns, double width})? _previousLayout;
  Widget? _rows;

  @override
  void didUpdateWidget(_SliverResultGrid<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.items, widget.items) ||
        oldWidget.itemBuilder != widget.itemBuilder) {
      _rows = null;
    }
  }

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      const spacing = 20.0;
      const minWidth = 440.0;
      final minimum = MediaQuery.textScalerOf(context)
          .scale(minWidth)
          .clamp(minWidth, minWidth * 1.5);
      final columns =
          ((constraints.crossAxisExtent + spacing) / (minimum + spacing))
              .floor()
              .clamp(1, 6);
      final width =
          (constraints.crossAxisExtent - (columns - 1) * spacing) / columns;
      final layout = (columns: columns, width: width);
      if (_rows != null && _previousLayout == layout) return _rows!;
      _previousLayout = layout;
      return _rows = SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, row) => Padding(
            padding: EdgeInsets.only(
              bottom: (row + 1) * columns < widget.items.length ? 24 : 0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: spacing,
              children: [
                for (var column = 0; column < columns; column++)
                  if (row * columns + column < widget.items.length)
                    IndexedSemantics(
                      index: row * columns + column,
                      child: SizedBox(
                        key: ValueKey(widget.items[row * columns + column].key),
                        width: width,
                        child: widget.itemBuilder(
                          context,
                          widget.items[row * columns + column],
                        ),
                      ),
                    ),
              ],
            ),
          ),
          childCount: (widget.items.length / columns).ceil(),
          addSemanticIndexes: false,
        ),
      );
    },
  );
}

final class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.query,
    required this.featured,
  });
  final SearchUserEntry user;
  final String query;
  final bool featured;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void open() => context.openWorkspaceLink('/user/${user.id.value}');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: featured
            ? theme.colorScheme.primary.withValues(alpha: .035)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: .45),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: open,
                  onTertiaryTapUp: WorkspaceLinkScope.middleClick(
                    context,
                    open,
                  ),
                  customBorder: const CircleBorder(),
                  child: NetworkAvatar(
                    url: user.avatarUrl,
                    name: user.name,
                    radius: 32,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          InkWell(
                            onTap: open,
                            onTertiaryTapUp: WorkspaceLinkScope.middleClick(
                              context,
                              open,
                            ),
                            child: HighlightedText(
                              user.name,
                              query: query,
                              style: theme.textTheme.titleMedium,
                              maxLines: 2,
                            ),
                          ),
                          if (user.level case final int level)
                            BiliLevelBadge(level: level),
                          if (user.verifyType case final int type)
                            BiliVerifyBadge(type: type),
                          TextButton(
                            onPressed: open,
                            child: const Text('进入主页 ›'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '粉丝：${compactCount(user.fans)}  ·  视频：${compactCount(user.videoCount)}',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (user.signature.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          user.signature,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (featured && user.videos.isNotEmpty) ...[
              const SizedBox(height: 20),
              VideoGrid(
                items: user.videos,
                highlightQuery: query,
                onOpen: (id) => context.openWorkspaceLink('/video/${id.value}'),
                onOpenUser: (id) =>
                    context.openWorkspaceLink('/user/${id.value}'),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: open,
                  child: const Text('查看TA的所有稿件 ›'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _MediaCard extends StatelessWidget {
  const _MediaCard({required this.item, required this.query});
  final SearchMediaEntry item;
  final String query;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _TapCard(
      onTap: () => context.openWorkspaceLink('/pgc/season/${item.id.value}'),
      opensWorkspaceLink: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: CatalogCardCover(url: item.coverUrl, badge: item.badge),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HighlightedText(
                  item.title,
                  query: query,
                  style: theme.textTheme.titleMedium,
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                if (item.score case final double score)
                  Text(
                    '${score.toStringAsFixed(1)} 分',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Text(
                  [
                    item.areas,
                    item.styles,
                  ].where((v) => v.isNotEmpty).join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                if (item.updateText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      item.updateText,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if (item.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      item.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _ArticleCard extends StatelessWidget {
  const _ArticleCard({
    required this.item,
    required this.query,
    required this.onOpen,
  });
  final SearchArticleEntry item;
  final String query;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => _TapCard(
    onTap: onOpen,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.coverUrl != null) ...[
              SizedBox(
                width: constraints.maxWidth < 500 ? 100 : 180,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: CatalogCardCover(url: item.coverUrl),
                ),
              ),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HighlightedText(
                    item.title,
                    query: query,
                    maxLines: 2,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 7),
                  if (item.description.isNotEmpty)
                    Text(
                      item.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  const SizedBox(height: 10),
                  Text(
                    [
                      item.author,
                      item.section,
                      if (item.publishedAt case final DateTime date)
                        _dateLabel(date),
                    ].where((v) => v.isNotEmpty).join(' · '),
                    maxLines: 2,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${compactCount(item.views)}阅读 · ${compactCount(item.likes)}喜欢 · ${compactCount(item.replies)}评论',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '阅读专栏',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

final class _TapCard extends StatelessWidget {
  const _TapCard({
    required this.onTap,
    required this.child,
    this.opensWorkspaceLink = false,
  });
  final bool opensWorkspaceLink;
  final VoidCallback onTap;
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      onTertiaryTapUp: opensWorkspaceLink
          ? WorkspaceLinkScope.middleClick(context, onTap)
          : null,
      borderRadius: BorderRadius.circular(6),
      child: child,
    ),
  );
}

String _dateLabel(DateTime value) {
  final date = value.toLocal();
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
