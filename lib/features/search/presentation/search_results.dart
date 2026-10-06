import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/external_links.dart';
import '../../../domain/user.dart';
import '../../../shared/ui/app_cover_image.dart';
import '../../../shared/ui/bili_badges.dart';
import '../../../shared/ui/network_avatar.dart';
import '../../../shared/ui/video_card.dart';
import '../../../shared/ui/video_grid.dart';
import '../../../shared/ui/highlighted_text.dart';
import '../domain/search_result.dart';

final class SearchResults extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final users = items.whereType<SearchUserEntry>();
    final videos = items.whereType<SearchVideoEntry>();
    final media = items.whereType<SearchMediaEntry>();
    final lives = items.whereType<SearchLiveEntry>();
    final articles = items.whereType<SearchArticleEntry>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final user in users) ...[
          _UserCard(
            user: user,
            query: query,
            featured: category == SearchCategory.all,
          ),
          const SizedBox(height: 24),
        ],
        for (final type in [SearchCategory.bangumi, SearchCategory.film])
          if (media.any((item) => item.category == type)) ...[
            if (category == SearchCategory.all) _section(context, type),
            _ResultGrid(
              minWidth: 440,
              children: [
                for (final item in media.where((item) => item.category == type))
                  _MediaCard(item: item, query: query),
              ],
            ),
            const SizedBox(height: 28),
          ],
        if (lives.isNotEmpty) ...[
          if (category == SearchCategory.all)
            _section(context, SearchCategory.live),
          _ResultGrid(
            children: [
              for (final item in lives) _LiveCard(item: item, query: query),
            ],
          ),
          const SizedBox(height: 28),
        ],
        if (articles.isNotEmpty) ...[
          if (category == SearchCategory.all)
            _section(context, SearchCategory.article),
          for (final item in articles) ...[
            _ArticleCard(
              item: item,
              query: query,
              onOpen: () => _openArticle(context, ref, item),
            ),
            const SizedBox(height: 18),
          ],
        ],
        if (videos.isNotEmpty) ...[
          if (category == SearchCategory.all &&
              items.any((item) => item is! SearchVideoEntry))
            _section(context, SearchCategory.video),
          VideoGrid(
            items: videos.map((item) => item.video).toList(growable: false),
            showUpBadge: true,
            highlightQuery: query,
            onOpen: (id) => context.go('/video/${id.value}'),
            onOpenUser: (id) => context.go('/user/${id.value}'),
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

  Future<void> _openArticle(
    BuildContext context,
    WidgetRef ref,
    SearchArticleEntry item,
  ) async {
    final opened = await ref.read(externalLinkOpenerProvider)(item.id.url);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法打开专栏，请检查系统浏览器')));
    }
  }
}

final class _ResultGrid extends StatelessWidget {
  const _ResultGrid({required this.children, this.minWidth = 245});
  final List<Widget> children;
  final double minWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const spacing = 20.0;
      final minimum = MediaQuery.textScalerOf(context)
          .scale(minWidth)
          .clamp(minWidth, minWidth * 1.5);
      final columns = ((constraints.maxWidth + spacing) / (minimum + spacing))
          .floor()
          .clamp(1, 6);
      final width = (constraints.maxWidth - (columns - 1) * spacing) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: 24,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
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
    void open() => context.go('/user/${user.id.value}');
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
                showUpBadge: true,
                highlightQuery: query,
                onOpen: (id) => context.go('/video/${id.value}'),
                onOpenUser: (id) => context.go('/user/${id.value}'),
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
      onTap: () => context.go('/pgc/season/${item.id.value}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: _Cover(
              url: item.coverUrl,
              aspectRatio: 3 / 4,
              badge: item.badge,
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

final class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.item, required this.query});
  final SearchLiveEntry item;
  final String query;
  @override
  Widget build(BuildContext context) => _TapCard(
    onTap: () => context.go('/live/${item.id.value}'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Cover(
          url: item.coverUrl,
          left: '${compactCount(item.online)} 人气',
          right: item.area,
          badge: item.isLive == false
              ? '未开播'
              : item.isLive == true
              ? '直播中'
              : '直播',
        ),
        const SizedBox(height: 9),
        HighlightedText(item.title, query: query, maxLines: 2),
        const SizedBox(height: 6),
        InkWell(
          onTap: switch (item.authorId) {
            final UserId id => () => context.go('/user/${id.value}'),
            _ => null,
          },
          child: Text(
            item.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
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
                child: _Cover(url: item.coverUrl),
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
                    '在浏览器阅读 ↗',
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
  const _TapCard({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: child,
    ),
  );
}

final class _Cover extends StatelessWidget {
  const _Cover({
    this.url,
    this.left = '',
    this.right = '',
    this.badge = '',
    this.aspectRatio = 16 / 9,
  });
  final Uri? url;
  final String left, right, badge;
  final double aspectRatio;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = url;
    final fallback = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (source != null && source.host.isNotEmpty)
              AppCoverImage(
                url: source.toString(),
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => fallback,
              )
            else
              fallback,
            if (left.isNotEmpty || right.isNotEmpty) ...[
              const Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  height: 50,
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xB3000000)],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 6,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        left,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (right.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 100),
                        child: Text(
                          right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (badge.isNotEmpty)
              Positioned(
                top: 6,
                right: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _dateLabel(DateTime value) {
  final date = value.toLocal();
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
