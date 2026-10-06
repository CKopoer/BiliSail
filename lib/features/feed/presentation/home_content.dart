import '../../../domain/user.dart';
import '../../../domain/dynamic_post.dart';
import '../../../shared/ui/responsive_card_grid.dart';
import '../../../shared/ui/dynamic_post_card.dart';
import '../../../shared/ui/network_avatar.dart';
import '../../../shared/ui/app_cover_image.dart';
import '../../../shared/ui/paged_scroll_viewport.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/external_links.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/video.dart';
import '../../../core/presentation/workspace_activity.dart';
import '../../../shared/ui/video_card.dart';
import '../../../shared/ui/video_card_interaction_scope.dart';
import '../../video/domain/video_card_interactions.dart';
import '../../video/domain/video_actions_repository.dart';
import '../../../shared/ui/state_view.dart';
import '../../../shared/ui/app_notice.dart';
import 'home_feed_cards.dart';
import 'favorite_folder_edit_dialog.dart';
import '../application/home_controller.dart';
import '../application/watch_later_removal_controller.dart';
import '../domain/home_channel.dart';
import '../domain/home_repository.dart';

final class HomeContent extends ConsumerStatefulWidget {
  const HomeContent({
    super.key,
    required this.channel,
    required this.section,
    required this.isSignedIn,
    this.active = true,
    this.onLogin,
  });
  final HomeChannel channel;
  final String section;
  final bool isSignedIn;
  final bool active;
  final VoidCallback? onLogin;
  @override
  ConsumerState<HomeContent> createState() => _HomeContentState();
}

final class _HomeContentState extends ConsumerState<HomeContent> {
  HomeEntry? _folder;
  HomeEntry? _liveParent;
  bool _expandedAreas = false;
  final Set<HomeQuery> _visitedQueries = {};
  @override
  void didUpdateWidget(HomeContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel != widget.channel ||
        oldWidget.section != widget.section ||
        oldWidget.isSignedIn != widget.isSignedIn) {
      _folder = null;
      _liveParent = null;
      _visitedQueries.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final needsLogin =
        widget.channel.requiresAccount ||
        widget.section == '我的追番' ||
        widget.section == '我的关注' ||
        widget.section == '观看记录';
    if (needsLogin && !widget.isSignedIn) {
      return SingleChildScrollView(
        child: StateView.empty(
          message:
              '登录后可查看${widget.section == '我的追番' ? '我的追番' : widget.channel.label}',
          icon: Icons.person_outline,
          actionLabel: '登录账号',
          onAction: widget.onLogin,
        ),
      );
    }
    final scope = ref.read(homeRepositoryProvider).accountScope;
    final liveBrowse =
        widget.channel == HomeChannel.live &&
        (widget.section == '推荐直播' || widget.section == '全部分区');
    final areasQuery = (
      channel: HomeChannel.live,
      section: '全部分区',
      scope: scope,
      folderId: null,
    );
    final areas = liveBrowse
        ? ref.watch(homeControllerProvider(areasQuery))
        : null;
    final query = (
      channel: widget.channel,
      section: liveBrowse ? '推荐' : widget.section,
      scope: scope,
      folderId: _folder?.kind == HomeEntryKind.collection
          ? 'ugc:${_folder?.id}'
          : _folder?.id,
    );
    _visitedQueries.add(query);
    if (_visitedQueries.length > 20) {
      // Retain the parent plus at most 19 recently visited folders per subtab.
      final evicted = _visitedQueries.firstWhere(
        (entry) => entry.folderId != null && entry != query,
      );
      _visitedQueries.remove(evicted);
    }
    for (final visited in _visitedQueries) {
      ref.watch(homeControllerProvider(visited));
    }
    final feed = ref.watch(homeControllerProvider(query));
    final controller = ref.read(homeControllerProvider(query).notifier);
    final watchLaterActions = widget.channel == HomeChannel.watchLater
        ? ref.watch(watchLaterRemovalProvider(scope))
        : null;
    return PagedScrollViewport(
      key: ValueKey(query),
      active: widget.active,
      canLoadMore:
          feed.hasMore &&
          !feed.loadingMore &&
          feed.items.asData != null &&
          feed.pageError == null,
      contentVersion: feed,
      onLoadMore: controller.loadMore,
      onRefresh: controller.refresh,
      builder: (scrollController) => RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          key: PageStorageKey(
            'home-${widget.channel.name}-${widget.section}-$scope-${query.folderId}',
          ),
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            if (liveBrowse && areas != null)
              areas.items.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => StateView.error(
                  message: _message(error),
                  onAction: ref
                      .read(homeControllerProvider(areasQuery).notifier)
                      .refresh,
                ),
                data: (items) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _areaRow(items, parent: true),
                    if (_liveParent != null)
                      _areaRow(_liveParent!.children, parent: false),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            if (_folder != null && !liveBrowse)
              Row(
                children: [
                  IconButton(
                    tooltip: '返回列表',
                    onPressed: () => setState(() => _folder = null),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(child: Text(_folder!.title)),
                ],
              ),
            feed.items.when(
              loading: () =>
                  const SizedBox(height: 300, child: StateView.loading()),
              error: (error, _) => StateView.error(
                message: _message(error),
                onAction: controller.refresh,
              ),
              data: (items) => items.isEmpty
                  ? const StateView.empty(message: '这里暂时没有内容')
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        if (widget.channel == HomeChannel.dynamic) {
                          return Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 780),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final item in items)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 16,
                                      ),
                                      child: DynamicPostCard(
                                        key: ValueKey(item.id),
                                        post:
                                            item.dynamicPost ??
                                            DynamicPost(
                                              id: item.id,
                                              authorName: item.authorName,
                                              authorId: UserId.tryParse(
                                                item.authorMid,
                                              ),
                                              authorAvatarUrl:
                                                  item.authorAvatarUrl,
                                              publishText: item.publishText,
                                              publishedAt: item.publishedAt,
                                              text: item.description.isEmpty
                                                  ? item.title
                                                  : item.description,
                                            ),
                                        onOpenUser: (id) =>
                                            context.go('/user/${id.value}'),
                                        onOpenVideo: (video) => context.go(
                                          '/video/${video.id.value}',
                                        ),
                                        onOpenLink: _openLink,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }
                        if (widget.channel == HomeChannel.favorites ||
                            widget.channel == HomeChannel.watchLater) {
                          return ResponsiveCardGrid(
                            children: [
                              for (final item in items)
                                if (item.kind == HomeEntryKind.video &&
                                    (item.bvid != null ||
                                        widget.channel ==
                                            HomeChannel.watchLater))
                                  HomeVideoCard(
                                    key: ValueKey((item.kind, item.id)),
                                    entry: item,
                                    menu:
                                        widget.channel == HomeChannel.watchLater
                                        ? VideoCardMenu(
                                            actions: const [
                                              VideoCardMenuAction
                                                  .removeWatchLater,
                                            ],
                                            busy:
                                                watchLaterActions?.pending
                                                    .contains(item.id) ==
                                                true,
                                            onSelected: (_) =>
                                                _removeWatchLater(item, scope),
                                          )
                                        : null,
                                    onOpenUser: (id) =>
                                        context.go('/user/${id.value}'),
                                    onTap: () => _open(item),
                                  )
                                else if (item.kind == HomeEntryKind.folder ||
                                    item.kind == HomeEntryKind.collection)
                                  FavoriteFolderCard(
                                    key: ValueKey((item.kind, item.id)),
                                    entry: item,
                                    onTap: () => _open(item),
                                    showCreatedMetadata:
                                        widget.section == '我创建的收藏夹' &&
                                        item.kind == HomeEntryKind.folder,
                                    onEdit:
                                        widget.section == '我创建的收藏夹' &&
                                            item.kind == HomeEntryKind.folder
                                        ? () => _editFolder(item, scope)
                                        : null,
                                    unsubscribing: feed.unsubscribing.contains((
                                      item.kind,
                                      item.id,
                                    )),
                                    onUnsubscribe:
                                        widget.section == '我的收藏与订阅' &&
                                            query.folderId == null &&
                                            ref.read(homeRepositoryProvider)
                                                is HomeSubscriptionRepository
                                        ? () => _unsubscribe(controller, item)
                                        : null,
                                  )
                                else
                                  _EntryCard(
                                    entry: item,
                                    onTap: () => _open(item),
                                  ),
                            ],
                          );
                        }
                        if (widget.channel == HomeChannel.videoDynamic) {
                          return ResponsiveCardGrid(
                            children: [
                              for (final item in items)
                                if (item.kind == HomeEntryKind.video)
                                  VideoDynamicCard(
                                    entry: item,
                                    onOpenUser: (id) =>
                                        context.go('/user/${id.value}'),
                                    onTap: () => _open(item),
                                  )
                                else
                                  _EntryCard(
                                    entry: item,
                                    onTap: () => _open(item),
                                  ),
                            ],
                          );
                        }
                        final columns =
                            (constraints.maxWidth /
                                    (widget.channel == HomeChannel.live
                                        ? 340
                                        : 250))
                                .floor()
                                .clamp(1, 8);
                        final width =
                            (constraints.maxWidth - (columns - 1) * 16) /
                            columns;
                        return Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            for (final item in items)
                              SizedBox(
                                width: width,
                                child:
                                    widget.channel == HomeChannel.live &&
                                        item.kind == HomeEntryKind.live
                                    ? LiveRoomCard(
                                        entry: item,
                                        onTap: () => _open(item),
                                      )
                                    : _EntryCard(
                                        entry: item,
                                        onTap: () => _open(item),
                                      ),
                              ),
                          ],
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            if (feed.limitReached)
              Center(
                child: Text(
                  widget.channel == HomeChannel.favorites
                      ? '已显示 ${HomeController.maxFavoriteEntries} 条内容，可刷新重新加载'
                      : '已显示 ${HomeController.maxDynamicEntries} 条动态，可刷新查看最新内容',
                ),
              ),
            if (feed.loadingMore)
              const Center(child: CircularProgressIndicator())
            else if (feed.pageError != null)
              StateView.error(
                message: _message(feed.pageError),
                onAction: controller.loadMore,
              )
            else if (feed.hasMore)
              Center(
                child: OutlinedButton(
                  onPressed: controller.loadMore,
                  child: const Text('加载更多'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _areaRow(List<HomeEntry> items, {required bool parent}) {
    final choices = <Widget>[
      ChoiceChip(
        label: const Text('全部'),
        selected: parent ? _liveParent == null : _folder?.id == _liveParent?.id,
        onSelected: (_) => setState(() {
          if (parent) {
            _liveParent = null;
            _folder = null;
          } else {
            _folder = _liveParent;
          }
        }),
      ),
      for (final item in items)
        ChoiceChip(
          label: Text(item.title),
          selected: parent
              ? _liveParent?.id == item.id
              : _folder?.id == item.id,
          onSelected: (_) => setState(() {
            if (parent) _liveParent = item;
            _folder = item;
          }),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _expandedAreas
                ? Wrap(spacing: 8, runSpacing: 8, children: choices)
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(spacing: 8, children: choices),
                  ),
          ),
          if (parent)
            IconButton(
              tooltip: _expandedAreas ? '收起分区' : '展开分区',
              onPressed: () => setState(() => _expandedAreas = !_expandedAreas),
              icon: Icon(
                _expandedAreas ? Icons.expand_less : Icons.expand_more,
              ),
            ),
        ],
      ),
    );
  }

  String _message(Object? error) =>
      error is AppFailure ? error.message : '内容加载失败，请重试';

  Future<void> _removeWatchLater(HomeEntry entry, String scope) async {
    if (!mounted ||
        !widget.active ||
        !WorkspaceActivity.isActive(context) ||
        ref.read(homeRepositoryProvider).accountScope != scope) {
      return;
    }
    final operations = VideoCardInteractionScope.maybeOf(context)?.interactions;
    final synchronization =
        operations is VideoCardWatchLaterRemovalSync &&
            VideoId(entry.bvid ?? '').isValid
        ? operations as VideoCardWatchLaterRemovalSync
        : null;
    final id = VideoId(entry.bvid ?? entry.id);
    if (synchronization?.beginWatchLaterRemoval(id) == false) return;
    var removed = false, uncertain = false;
    try {
      removed = await ref
          .read(watchLaterRemovalProvider(scope).notifier)
          .remove(entry);
      if (removed &&
          mounted &&
          widget.active &&
          WorkspaceActivity.isActive(context) &&
          ref.read(homeRepositoryProvider).accountScope == scope) {
        showAppNotice(context, '已从稍后再看删除');
      }
    } on UnknownWriteOutcome {
      uncertain = true;
      if (mounted &&
          widget.active &&
          WorkspaceActivity.isActive(context) &&
          ref.read(homeRepositoryProvider).accountScope == scope) {
        showAppNotice(context, '删除结果暂时无法确认，请刷新稍后再看列表核对');
      }
    } on AppFailure catch (failure) {
      if (mounted &&
          widget.active &&
          WorkspaceActivity.isActive(context) &&
          failure.kind != AppFailureKind.cancelled &&
          ref.read(homeRepositoryProvider).accountScope == scope) {
        showAppNotice(context, failure.message);
      }
    } finally {
      synchronization?.finishWatchLaterRemoval(
        id,
        removed: removed,
        uncertain: uncertain,
      );
    }
  }

  Future<void> _unsubscribe(HomeController controller, HomeEntry entry) async {
    final scope = ref.read(homeRepositoryProvider).accountScope;
    bool current() =>
        mounted &&
        widget.active &&
        widget.isSignedIn &&
        ref.read(homeRepositoryProvider).accountScope == scope;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('取消订阅'),
        content: Text('确定取消订阅“${entry.title}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认取消'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !current()) return;
    try {
      final removed = await controller.unsubscribeFavorite(entry);
      if (removed && mounted && current()) showAppNotice(context, '已取消订阅');
    } catch (error) {
      if (!mounted ||
          !current() ||
          error is AppFailure && error.kind == AppFailureKind.cancelled) {
        return;
      }
      showAppNotice(
        context,
        error is AppFailure &&
                error.kind != AppFailureKind.network &&
                error.kind != AppFailureKind.timeout
            ? error.message
            : '取消订阅结果未确认，请刷新列表查看',
      );
    }
  }

  Future<void> _editFolder(HomeEntry entry, String scope) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          FavoriteFolderEditDialog(target: (id: entry.id, scope: scope)),
    );
    if (!mounted ||
        saved != true ||
        ref.read(homeRepositoryProvider).accountScope != scope) {
      return;
    }
    showAppNotice(context, '收藏夹已修改');
    await ref
        .read(
          homeControllerProvider((
            channel: HomeChannel.favorites,
            section: '我创建的收藏夹',
            scope: scope,
            folderId: null,
          )).notifier,
        )
        .refresh();
  }

  Future<void> _open(HomeEntry entry) async {
    if (entry.kind == HomeEntryKind.folder ||
        entry.kind == HomeEntryKind.collection) {
      setState(() => _folder = entry);
      return;
    }
    if (entry.kind == HomeEntryKind.season) {
      final ids = entry.id.split(':');
      final seasonId = ids.first;
      final episodeId = ids.length == 2 ? ids.last : null;
      if (RegExp(r'^[1-9][0-9]*$').hasMatch(seasonId)) {
        context.go(
          Uri(
            path: '/pgc/season/$seasonId',
            queryParameters:
                episodeId != null &&
                    RegExp(r'^[1-9][0-9]*$').hasMatch(episodeId)
                ? {'ep': episodeId}
                : null,
          ).toString(),
        );
      } else {
        showAppNotice(context, '影视地址无效');
      }
      return;
    }
    if (entry.kind == HomeEntryKind.live) {
      if (RegExp(r'^[1-9][0-9]*$').hasMatch(entry.id)) {
        context.go('/live/${entry.id}');
      } else {
        showAppNotice(context, '直播房间地址无效');
      }
      return;
    }
    if (entry.bvid != null) {
      context.go('/video/${entry.bvid}');
      return;
    }
    final uri = entry.url;
    if (uri == null) return;
    await _openLink(uri);
  }

  Future<void> _openLink(Uri uri) async {
    var opened = false;
    try {
      opened = await ref.read(externalLinkOpenerProvider)(uri);
    } on PlatformException {
      opened = false;
    }
    if (mounted && !opened) {
      showAppNotice(context, '无法打开浏览器，请稍后重试');
    }
  }
}

final class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.onTap});
  final HomeEntry entry;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: entry.kind == HomeEntryKind.video && entry.bvid == null
          ? null
          : onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.coverUrl != null)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: AppCoverImage(
                url: entry.coverUrl.toString(),
                fit: BoxFit.cover,
                frameBuilder: (_, child, frame, _) => frame != null
                    ? child
                    : const Center(child: Icon(Icons.image_outlined)),
                errorBuilder: (_, _, _) => const Center(
                  child: Icon(Icons.image_not_supported_outlined),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.authorName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: UserId.tryParse(entry.authorMid) == null
                          ? null
                          : () => context.go('/user/${entry.authorMid}'),
                      child: Row(
                        children: [
                          NetworkAvatar(
                            url: entry.authorAvatarUrl,
                            name: entry.authorName,
                            radius: 15,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              entry.authorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Text(
                  entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (entry.subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      entry.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (entry.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      entry.description,
                      maxLines: 8,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (entry.kind == HomeEntryKind.dynamic)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('外部打开 ↗', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
