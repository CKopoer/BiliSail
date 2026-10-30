import 'dart:async';

import 'package:bili_player/bili_player.dart';

import '../../../domain/user.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../core/network/api_requests.dart';

import '../../../shared/ui/playback_page_commands.dart';
import '../../../shared/ui/playback_layout_builder.dart';
import '../../../shared/ui/width_layout_builder.dart';
import '../../../domain/video.dart';
import '../../../shared/ui/state_view.dart';
import '../../../shared/ui/app_cover_image.dart';
import '../../../shared/ui/highlighted_text.dart';
import '../../../shared/ui/playback_sidebar_toggle.dart';
import '../../../shared/ui/playback_info_tabs.dart';
import '../../../shared/ui/comment_detail_builder.dart';
import '../../../domain/comment_target.dart';
import '../../../core/presentation/workspace_activity.dart';
import '../../../shared/ui/video_card.dart';
import '../../../shared/ui/video_card_cover.dart';
import '../../../shared/ui/scroll_aware_hover_region.dart';
import '../../../shared/ui/video_card_interaction_scope.dart';
import '../../feed/application/home_repository_provider.dart';
import '../../feed/application/watch_later_removal_controller.dart';
import '../../feed/domain/home_repository.dart';
import '../application/playback_queue_controller.dart';
import '../domain/video_actions_repository.dart';
import '../domain/video_card_interactions.dart';
import 'video_author_header.dart';
import 'video_collection_panel.dart';
import '../application/video_controller.dart';
import '../application/video_extras_controller.dart';
import 'video_comments_panel.dart';
import 'video_tags_panel.dart';
import 'video_access_notice.dart';
import 'watch_later_queue_panel.dart';
import '../domain/watch_later_queue.dart';
import '../domain/video_playback_sequence.dart';
import '../application/watch_later_queue_registry.dart';
import '../application/watch_later_queue_playback.dart';
import '../../playback/application/playback_session.dart';
import '../../../shared/ui/bili_icons.dart';

typedef VideoPlayerBuilder = Widget Function(
  BuildContext context,
  VideoDetail detail,
  VideoPart part,
);

const _descriptionTransitionDuration = Duration(milliseconds: 220);

final class VideoScreen extends ConsumerStatefulWidget {
  const VideoScreen({
    super.key,
    required this.id,
    this.initialCid,
    this.defaultShowComments = false,
    this.onPartChanged,
    this.onOpenVideo,
    required this.playerBuilder,
    this.actionsBuilder,
    this.menuBuilder,
    this.onLogin,
    this.onOpenUser,
    this.onOpenVideoPart,
    this.onSearchTag,
    this.queue,
    this.onOpenQueueVideo,
    this.onAdvanceVideo,
  });
  final VideoId id;
  final String? initialCid;
  final bool? defaultShowComments;
  final ValueChanged<VideoPart>? onPartChanged;
  final ValueChanged<VideoSummary>? onOpenVideo;
  final VideoPlayerBuilder playerBuilder;
  final VideoPlayerBuilder? actionsBuilder;
  final VideoPlayerBuilder? menuBuilder;
  final VoidCallback? onLogin;
  final ValueChanged<UserId>? onOpenUser;
  final void Function(VideoId, String?)? onOpenVideoPart;
  final ValueChanged<String>? onSearchTag;
  final WatchLaterQueue? queue;
  final ValueChanged<VideoId>? onOpenQueueVideo;
  final void Function(VideoId, String?)? onAdvanceVideo;
  @override
  ConsumerState<VideoScreen> createState() => _VideoScreenState();
}

final class _VideoScreenState extends ConsumerState<VideoScreen> {
  String? _selectedCid;
  int? _tab;
  bool _infoVisible = true;
  bool _descriptionExpanded = false;
  bool _queueExpanded = true;
  VideoDetail? _lastVideo;
  String? _lastCid;
  ({VideoId id, String scope, int epoch})? _pendingAdvance;
  String? _retainedQueueId;
  WatchLaterQueueRegistry? _retainedRegistry;
  PlaybackSession? _queueSession;
  final WatchLaterQueuePlayback _queuePlayback = WatchLaterQueuePlayback();
  ({VideoId id, int generation})? _completionWaiting;
  bool _loadingNextQueue = false;
  final ScrollController _introScroll = ScrollController();
  final GlobalKey _infoKey = GlobalKey();
  final GlobalKey _playerKey = GlobalKey();
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncQueue();
  }

  void _syncQueue() {
    final queue = widget.queue;
    final registry = queue == null
        ? null
        : ref.read(watchLaterQueueRegistryProvider);
    if (_retainedQueueId != queue?.id ||
        !identical(_retainedRegistry, registry)) {
      if (_retainedQueueId case final String id) {
        _retainedRegistry?.release(id);
      }
      _retainedQueueId = queue?.id;
      _retainedRegistry = registry;
      if (queue != null) {
        registry?.retain(queue.id);
      }
    }
    if (queue == null && _queueSession != null) {
      _queueSession = null;
    } else if (queue != null && _queueSession == null) {
      _queueSession = ref.read(playbackSessionProvider);
    }
  }

  @override
  void dispose() {
    if (_retainedQueueId case final String id) {
      _retainedRegistry?.release(id);
    }
    _introScroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant VideoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.queue?.id != widget.queue?.id) {
      _completionWaiting = null;
      _queueExpanded = true;
      _queuePlayback.reset();
      _lastVideo = null;
      _lastCid = null;
      _pendingAdvance = null;
      if (widget.queue == null) _queueSession?.discardNextVideo();
    }
    _syncQueue();
    if (oldWidget.id != widget.id) {
      _selectedCid = widget.initialCid;
      _tab = null;
      _descriptionExpanded = false;
    }
    if (oldWidget.initialCid != widget.initialCid) {
      _selectedCid = widget.initialCid;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Null waits for async settings; an explicit selection always takes priority.
    final defaultShowComments = widget.defaultShowComments;
    if (_tab == null && defaultShowComments != null) {
      _tab = defaultShowComments ? 1 : 0;
    }
    final tab = _tab ?? 0;
    final profileQueue = switch (widget.queue) {
      final original? when original.isPaged => ref.watch(
        playbackQueueProvider(original.id),
      ),
      _ => null,
    };
    final originalQueue = _validQueue;
    final removals = originalQueue == null || !originalQueue.isWatchLater
        ? null
        : ref.watch(watchLaterRemovalProvider(originalQueue.scope));
    final queue = originalQueue?.withoutRemoved(
      removals?.removed ?? const {},
      current: widget.id,
    );
    // Start the related read alongside detail without rebuilding the player
    // and intro header when only that read changes.
    ref.listen(relatedVideosProvider(widget.id), (_, _) {});
    final detail = ref.watch(videoDetailProvider(widget.id));
    final loaded = detail.asData?.value;
    final pending = _pendingAdvance;
    final session = ref.exists(playbackSessionProvider)
        ? ref.read(playbackSessionProvider)
        : null;
    final transitioning =
        loaded == null &&
        detail.isLoading &&
        _lastVideo != null &&
        pending?.id == widget.id &&
        pending?.scope == session?.accountScope() &&
        pending?.epoch == session?.sessionEpoch();
    final video = loaded ?? (transitioning ? _lastVideo : null);
    if (video == null) {
      return detail.when(
        loading: () => const StateView.loading(message: '正在加载视频详情…'),
        error: (error, _) => StateView.error(
          message: _failure(error, '视频详情加载失败'),
          onAction: () => ref.invalidate(videoDetailProvider(widget.id)),
        ),
        data: (_) => const StateView.empty(message: '视频详情不可用'),
      );
    }
    if (video.parts.isEmpty) {
      return const StateView.empty(
        message: '这个视频没有可播放的分 P',
        icon: Icons.videocam_off_outlined,
      );
    }
    final selected =
        video.parts
            .where(
              (part) =>
                  part.cid ==
                  (transitioning
                      ? _lastCid
                      : _selectedCid ?? widget.initialCid),
            )
            .firstOrNull ??
        video.parts.first;
    if (!transitioning) {
      _lastVideo = video;
      _lastCid = selected.cid;
      _pendingAdvance = null;
    }
    return Stack(
      children: [
        WidthLayoutBuilder(
          builder: (context, width) {
            final wide = width >= 1000;
            final showInfo = _infoVisible;
            void toggleInfo() => setState(() => _infoVisible = !_infoVisible);
            return PlaybackPageCommands(
              previousPart: () => _changePart(video, selected, -1),
              nextPart: () => _changePart(video, selected, 1),
              hasNext:
                  !transitioning &&
                  (_adjacentSource(video, selected, 1) != null ||
                      _canPageQueue(1)),
              onCompleted: () =>
                  _changePart(video, selected, 1, completed: true),
              onRelatedCompleted: widget.queue == null
                  ? () => _playRelated(video, selected)
                  : null,
              toggleInfo: toggleInfo,
              child: Focus(
                child: Builder(
                  builder: (context) {
                    final playerContent = ColoredBox(
                      color: Colors.black,
                      child: widget.playerBuilder(context, video, selected),
                    );
                    final content = Padding(
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          VideoAuthorHeader(
                            video: video,
                            onLogin: widget.onLogin,
                            onOpenUser: widget.onOpenUser,
                          ),
                          const SizedBox(height: 18),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: SelectionArea(
                                  child: Text(
                                    video.summary.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(height: 1.4),
                                  ),
                                ),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  minimumSize: const Size(0, 30),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () => setState(
                                  () => _descriptionExpanded =
                                      !_descriptionExpanded,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(_descriptionExpanded ? '收起' : '展开'),
                                    AnimatedRotation(
                                      turns: _descriptionExpanded ? .5 : 0,
                                      duration:
                                          MediaQuery.disableAnimationsOf(
                                            context,
                                          )
                                          ? Duration.zero
                                          : _descriptionTransitionDuration,
                                      curve: Curves.easeInOutCubic,
                                      child: const Icon(
                                        Icons.expand_more,
                                        size: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 6,
                            children: [
                              _Meta(
                                icon: BiliIcons.playCount,
                                label: compactCount(video.summary.playCount),
                              ),
                              _Meta(
                                icon: BiliIcons.comment,
                                label: compactCount(video.summary.danmakuCount),
                              ),
                              if (video.summary.publishedAt
                                  case final DateTime date)
                                _Meta(
                                  icon: Icons.schedule_outlined,
                                  label: _publicationTime(date),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (video.summary.access.kind !=
                              VideoAccessKind.normal) ...[
                            VideoAccessNotice(video: video.summary),
                            const SizedBox(height: 12),
                          ],
                          if (widget.actionsBuilder != null)
                            widget.actionsBuilder!(context, video, selected),
                          _VideoDescriptionTransition(
                            key: ValueKey(('description', widget.id)),
                            expanded: _descriptionExpanded,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 12),
                                SelectionArea(
                                  child: Text(
                                    video.description.isEmpty
                                        ? 'UP 主还没有填写简介'
                                        : video.description,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(height: 1.6),
                                  ),
                                ),
                                VideoTagsPanel(
                                  id: widget.id,
                                  onSearch: widget.onSearchTag,
                                ),
                              ],
                            ),
                          ),
                          _separator('intro'),
                          if (video.parts.length > 1 ||
                              video.collection != null) ...[
                            VideoCollectionPanel(
                              key: ValueKey(video.summary.id),
                              video: video,
                              selected: selected,
                              onLogin: widget.onLogin,
                              onSelectPart: (part) {
                                setState(() => _selectedCid = part.cid);
                                widget.onPartChanged?.call(part);
                              },
                              onOpenVideoPart: widget.onOpenVideoPart,
                            ),
                            _separator('collection'),
                          ],
                        ],
                      ),
                    );
                    final detailsVisible =
                        showInfo && (queue == null || !_queueExpanded);
                    final infoTabs = WorkspaceActivity(
                      active:
                          detailsVisible && WorkspaceActivity.isActive(context),
                      previewing:
                          detailsVisible &&
                          WorkspaceActivity.isVisible(context) &&
                          !WorkspaceActivity.isActive(context),
                      child: CommentDetailBuilder(
                        target: switch (video.aid) {
                          final String aid => CommentTarget(
                            aid,
                            CommentTargetType.video,
                          ),
                          null => null,
                        },
                        enabled: tab == 1,
                        builder: (context, detailOpen) => PlaybackInfoTabs(
                          key: ValueKey(video.summary.id),
                          showNavigation: !detailOpen,
                          value: tab,
                          onChanged: (tab) => setState(() => _tab = tab),
                          viewKey: const ValueKey('video-info-swipe'),
                          labels: [
                            const Text('简介'),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('评论'),
                                const SizedBox(width: 4),
                                Text(
                                  compactCount(video.replyCount),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ],
                          trailing: widget.menuBuilder?.call(
                            context,
                            video,
                            selected,
                          ),
                          pageBuilder: (context, tab, active) => TickerMode(
                            enabled: detailsVisible && active,
                            child: tab == 0
                                ? CustomScrollView(
                                    key: const ValueKey('video-intro-scroll'),
                                    controller: _introScroll,
                                    slivers: [
                                      SliverToBoxAdapter(child: content),
                                      SliverPadding(
                                        padding: const EdgeInsets.fromLTRB(
                                          12,
                                          0,
                                          12,
                                          12,
                                        ),
                                        sliver: _RelatedVideosSliver(
                                          id: widget.id,
                                          onOpenVideo: widget.onOpenVideo,
                                          onOpenUser: widget.onOpenUser,
                                        ),
                                      ),
                                    ],
                                  )
                                : VideoCommentsPanel(
                                    detail: video,
                                    onLogin: widget.onLogin,
                                    onOpenUser: widget.onOpenUser,
                                  ),
                          ),
                        ),
                      ),
                    );
                    final info = Material(
                      key: _infoKey,
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(6),
                      clipBehavior: Clip.antiAlias,
                      child: queue == null
                          ? infoTabs
                          : WatchLaterQueuePanel(
                              queue: queue,
                              current: widget.id,
                              expanded: _queueExpanded,
                              onToggle: () => setState(
                                () => _queueExpanded = !_queueExpanded,
                              ),
                              onSelect: _openQueueVideo,
                              onRemove: queue.isWatchLater
                                  ? _removeQueueItem
                                  : null,
                              pendingRemovals: removals?.pending ?? const {},
                              onLoadMore: queue.hasMore ? _loadMoreQueue : null,
                              onLoadPrevious: queue.hasPrevious
                                  ? () => _loadMoreQueue(previous: true)
                                  : null,
                              loadingMore:
                                  profileQueue != null &&
                                  profileQueue.loading &&
                                  profileQueue.direction > 0,
                              loadingPrevious:
                                  profileQueue != null &&
                                  profileQueue.loading &&
                                  profileQueue.direction < 0,
                              loadMoreMessage: profileQueue?.nextMessage,
                              loadPreviousMessage:
                                  profileQueue?.previousMessage,
                              collapsedChild: infoTabs,
                            ),
                    );
                    return PlaybackLayoutBuilder(
                      builder: (context, constraints, listening) {
                        final playerHeight = wide || !showInfo
                            ? constraints.maxHeight
                            : listening && constraints.maxHeight.isFinite
                            ? PlaybackLayoutBuilder.listeningHeight(
                                constraints.maxHeight,
                              )
                            : constraints.maxWidth * 9 / 16;
                        final player = Column(
                          key: _playerKey,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: playerHeight,
                              width: double.infinity,
                              child: playerContent,
                            ),
                          ],
                        );
                        final playerWithToggle = Stack(
                          children: [
                            player,
                            if (wide)
                              Positioned(
                                right: 0,
                                top:
                                    constraints.maxHeight / 2 -
                                    PlaybackSidebarToggle.size.height / 2,
                                child: PlaybackSidebarToggle(
                                  tooltip: showInfo ? '收起视频信息' : '展开视频信息',
                                  icon: showInfo
                                      ? Icons.chevron_right
                                      : Icons.chevron_left,
                                  onPressed: toggleInfo,
                                ),
                              ),
                          ],
                        );
                        if (wide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: playerWithToggle),
                              ExcludeFocus(
                                excluding: !showInfo,
                                child: Offstage(
                                  offstage: !showInfo,
                                  child: SizedBox(
                                    width: 380,
                                    height: constraints.maxHeight,
                                    child: info,
                                  ),
                                ),
                              ),
                            ],
                          );
                        }
                        return SingleChildScrollView(
                          padding: EdgeInsets.zero,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              playerWithToggle,
                              ExcludeFocus(
                                excluding: !showInfo,
                                child: Offstage(
                                  offstage: !showInfo,
                                  child: SizedBox(
                                    height: constraints.maxHeight.isFinite
                                        ? (constraints.maxHeight - playerHeight)
                                              .clamp(480.0, double.infinity)
                                        : 600,
                                    child: info,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            );
          },
        ),
        if (transitioning)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0xB8000000),
              child: StateView.loading(message: '正在加载下一个视频…'),
            ),
          ),
      ],
    );
  }

  Future<void> _playRelated(VideoDetail video, VideoPart selected) async {
    if (widget.id != video.summary.id || widget.onAdvanceVideo == null) return;
    final session = ref.read(playbackSessionProvider);
    final generation = session.sourceGeneration;
    List<VideoSummary> related;
    // The page retains this provider until navigation/disposal; its transport
    // owns cancellation. A completion can arrive before recommendations load.
    final subscription = ref.listenManual(
      filteredRelatedVideosProvider(video.summary.id),
      (_, _) {},
    );
    try {
      related = await ref
          .read(filteredRelatedVideosProvider(video.summary.id).future)
          .timeout(const Duration(seconds: 25));
    } catch (error) {
      if (mounted &&
          session.sourceGeneration == generation &&
          session.sourceMatchesAccount) {
        showAppNotice(context, _failure(error, '相关视频加载失败，已停止连续播放'));
      }
      return;
    } finally {
      subscription.close();
    }
    if (!mounted ||
        !session.continuousRelatedPlaybackEnabled ||
        !session.sourceMatchesAccount ||
        session.sourceGeneration != generation ||
        session.snapshots.value.phase != PlaybackPhase.ended ||
        widget.id != video.summary.id ||
        widget.queue != null) {
      return;
    }
    final next = related
        .where((item) => item.id != video.summary.id)
        .firstOrNull;
    if (next == null ||
        !session.prepareNextVideo(
          video.summary.id,
          selected.cid,
          nextId: next.id,
          completed: true,
        )) {
      return;
    }
    _pendingAdvance = (
      id: next.id,
      scope: session.accountScope(),
      epoch: session.sessionEpoch(),
    );
    widget.onAdvanceVideo?.call(next.id, null);
  }

  VideoSequenceTarget? _adjacentSource(
    VideoDetail video,
    VideoPart selected,
    int direction,
  ) {
    final queue = _effectiveQueue;
    if (widget.queue != null && queue == null) {
      return null;
    }
    final next = adjacentVideoSource(
      video,
      selected.cid,
      direction,
      queue: queue,
    );
    if (next != null &&
        next.id != video.summary.id &&
        (queue != null
            ? widget.onOpenQueueVideo == null
            : widget.onAdvanceVideo == null)) {
      return null;
    }
    return next;
  }

  Future<void> _changePart(
    VideoDetail video,
    VideoPart selected,
    int direction, {
    bool completed = false,
  }) async {
    if (widget.id != video.summary.id) return;
    // The fullscreen route retains these callbacks across page rebuilds.
    final current =
        video.parts
            .where((part) => part.cid == (_selectedCid ?? widget.initialCid))
            .firstOrNull ??
        selected;
    var next = _adjacentSource(video, current, direction);
    if (next == null && _canPageQueue(direction)) {
      if (_loadingNextQueue) return;
      final queue = _effectiveQueue;
      if (queue == null) return;
      final session = _queueSession;
      final generation = session?.sourceGeneration;
      if (completed && generation != null) {
        _completionWaiting = (id: widget.id, generation: generation);
      }
      _loadingNextQueue = true;
      try {
        await ref
            .read(playbackQueueProvider(queue.id).notifier)
            .prepareAdjacent(widget.id, direction);
      } finally {
        _loadingNextQueue = false;
      }
      if (!mounted ||
          widget.id != video.summary.id ||
          _validQueue?.id != queue.id ||
          session?.sourceGeneration != generation) {
        return;
      }
      next = _adjacentSource(video, current, direction);
    }
    if (next == null) return;
    _completionWaiting = null;
    final target = next;
    final session = ref.exists(playbackSessionProvider)
        ? ref.read(playbackSessionProvider)
        : null;
    if (session != null &&
        !session.prepareNextVideo(
          video.summary.id,
          current.cid,
          nextId: next.id,
          nextCid: next.cid,
          completed:
              completed || session.snapshots.value.phase == PlaybackPhase.ended,
        )) {
      return;
    }
    if (next.id != video.summary.id) {
      if (session != null) {
        _pendingAdvance = (
          id: next.id,
          scope: session.accountScope(),
          epoch: session.sessionEpoch(),
        );
      }
      if (widget.queue != null) {
        widget.onOpenQueueVideo?.call(next.id);
      } else {
        widget.onAdvanceVideo?.call(next.id, next.cid);
      }
      return;
    }
    final part = video.parts.firstWhere((part) => part.cid == target.cid);
    setState(() => _selectedCid = part.cid);
    widget.onPartChanged?.call(part);
  }

  void _openQueueVideo(VideoId id) {
    final queue = _effectiveQueue;
    final session = _queueSession;
    if (id == widget.id ||
        queue == null ||
        session == null ||
        !_queuePlayback.select(queue, session, id)) {
      return;
    }
    _pendingAdvance = (
      id: id,
      scope: session.accountScope(),
      epoch: session.sessionEpoch(),
    );
    if (queue.isPaged) {
      ref.read(playbackQueueProvider(queue.id).notifier).rememberCurrent(id);
    }
    widget.onOpenQueueVideo?.call(id);
  }

  bool _canPageQueue(int direction) {
    final queue = _effectiveQueue;
    if (queue == null || !queue.isPaged) return false;
    if (queue.indexOf(widget.id) < 0) return queue.pageOf(widget.id) != null;
    return direction > 0 ? queue.hasMore : queue.hasPrevious;
  }

  WatchLaterQueue? get _validQueue {
    final queue = switch (widget.queue) {
      final original? when original.isPaged =>
        ref.read(playbackQueueProvider(original.id)).queue,
      final original => original,
    };
    return queue != null &&
            queue.sessionEpoch == ref.read(sessionEpochProvider)() &&
            queue.sessionEpoch == _queueSession?.sessionEpoch() &&
            queue.scope == _queueSession?.accountScope()
        ? queue
        : null;
  }

  WatchLaterQueue? get _effectiveQueue {
    final queue = _validQueue;
    if (queue == null || !queue.isWatchLater) return queue;
    return queue.withoutRemoved(
      ref.read(watchLaterRemovalProvider(queue.scope)).removed,
      current: widget.id,
    );
  }

  Future<void> _loadMoreQueue({bool previous = false}) async {
    final queue = _validQueue;
    if (queue == null || !queue.isPaged) return;
    final controller = ref.read(playbackQueueProvider(queue.id).notifier);
    await (previous
        ? controller.loadPrevious(widget.id)
        : controller.loadMore(widget.id));
    if (!mounted || _validQueue?.id != queue.id) return;
    final video = _lastVideo;
    final selected = video?.parts
        .where((part) => part.cid == _lastCid)
        .firstOrNull;
    if (!_loadingNextQueue &&
        ref.read(playbackQueueProvider(queue.id)).nextMessage == null &&
        _completionWaiting?.id == widget.id &&
        _completionWaiting?.generation == _queueSession?.sourceGeneration &&
        video != null &&
        selected != null &&
        _queueSession?.snapshots.value.phase == PlaybackPhase.ended) {
      _changePart(video, selected, 1, completed: true);
    }
  }

  Future<void> _removeQueueItem(WatchLaterQueueItem item) async {
    final queue = _effectiveQueue;
    if (!mounted ||
        !WorkspaceActivity.isActive(context) ||
        queue == null ||
        !queue.isWatchLater ||
        item.video.id == widget.id ||
        queue.indexOf(item.video.id) < 0 ||
        ref.read(homeRepositoryProvider).accountScope != queue.scope) {
      return;
    }
    final operations = VideoCardInteractionScope.maybeOf(context)?.interactions;
    final synchronization = operations is VideoCardWatchLaterRemovalSync
        ? operations as VideoCardWatchLaterRemovalSync
        : null;
    final id = item.video.id;
    if (synchronization?.beginWatchLaterRemoval(id) == false) return;
    bool current() =>
        mounted &&
        WorkspaceActivity.isActive(context) &&
        _validQueue?.id == queue.id &&
        _validQueue?.scope == queue.scope &&
        _validQueue?.sessionEpoch == queue.sessionEpoch;
    var removed = false, uncertain = false;
    try {
      removed = await ref
          .read(watchLaterRemovalProvider(queue.scope).notifier)
          .remove(
            HomeEntry(
              id: item.removalId,
              aid: item.aid,
              bvid: id.value,
              title: item.video.title,
              kind: HomeEntryKind.video,
            ),
          );
      if (removed && mounted && current()) {
        showAppNotice(context, '已从稍后再看删除');
      }
    } on UnknownWriteOutcome {
      uncertain = true;
      if (mounted && current()) {
        showAppNotice(context, '删除结果暂时无法确认，请刷新稍后再看列表核对');
      }
    } on AppFailure catch (failure) {
      if (mounted && current() && failure.kind != AppFailureKind.cancelled) {
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

  Widget _separator(String section) => Divider(
    key: ValueKey('video-info-separator-$section'),
    height: 36,
    thickness: 0.7,
    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.55),
  );
}

final class _VideoDescriptionTransition extends StatefulWidget {
  const _VideoDescriptionTransition({
    super.key,
    required this.expanded,
    required this.child,
  });

  final bool expanded;
  final Widget child;

  @override
  State<_VideoDescriptionTransition> createState() =>
      _VideoDescriptionTransitionState();
}

final class _VideoDescriptionTransitionState
    extends State<_VideoDescriptionTransition>
    with SingleTickerProviderStateMixin {
  late final _controller =
      AnimationController(vsync: this, value: widget.expanded ? 1 : 0)
        ..addStatusListener((status) {
          if (status == AnimationStatus.dismissed) setState(() {});
        });
  late final _animation = _controller.drive(
    CurveTween(curve: Curves.easeInOutCubic),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _descriptionTransitionDuration;
    if (_controller.duration == Duration.zero) {
      _controller.value = widget.expanded ? 1 : 0;
    }
  }

  @override
  void didUpdateWidget(covariant _VideoDescriptionTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expanded != widget.expanded) {
      widget.expanded ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mount tags on expansion and release them only after the exit completes.
    if (!widget.expanded && _controller.isDismissed) {
      return const SizedBox.shrink();
    }
    return ExcludeFocus(
      excluding: !widget.expanded,
      child: ExcludeSemantics(
        excluding: !widget.expanded,
        child: IgnorePointer(
          ignoring: !widget.expanded,
          child: SizeTransition(
            sizeFactor: _animation,
            alignment: Alignment.topCenter,
            child: FadeTransition(opacity: _animation, child: widget.child),
          ),
        ),
      ),
    );
  }
}

final class _RelatedVideosSliver extends ConsumerStatefulWidget {
  const _RelatedVideosSliver({
    required this.id,
    this.onOpenVideo,
    this.onOpenUser,
  });
  final VideoId id;
  final ValueChanged<VideoSummary>? onOpenVideo;
  final ValueChanged<UserId>? onOpenUser;

  @override
  ConsumerState<_RelatedVideosSliver> createState() =>
      _RelatedVideosSliverState();
}

final class _RelatedVideosSliverState
    extends ConsumerState<_RelatedVideosSliver> {
  ({
    List<VideoSummary> videos,
    ValueChanged<VideoSummary>? onOpen,
    ValueChanged<UserId>? onOpenUser,
    SliverList sliver,
  })?
  _cached;

  Widget _state(Widget child) {
    _cached = null;
    return SliverToBoxAdapter(child: child);
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(filteredRelatedVideosProvider(widget.id))
      .when(
        loading: () => _state(const StateView.loading(message: '正在加载相关推荐…')),
        error: (error, _) => _state(
          StateView.error(
            message: _failure(error, '相关推荐加载失败'),
            onAction: () => ref.invalidate(relatedVideosProvider(widget.id)),
          ),
        ),
        data: (videos) {
          if (videos.isEmpty) {
            return _state(const StateView.empty(message: '暂无相关推荐'));
          }
          final cached = _cached;
          final onOpen = widget.onOpenVideo;
          final onOpenUser = widget.onOpenUser;
          if (cached != null &&
              identical(cached.videos, videos) &&
              cached.onOpen == onOpen &&
              cached.onOpenUser == onOpenUser) {
            return cached.sliver;
          }
          final indexes = {
            for (final (index, video) in videos.indexed) video.id: index,
          };
          final sliver = SliverList.builder(
            itemCount: videos.length,
            findChildIndexCallback: (key) =>
                key is ValueKey<VideoId> ? indexes[key.value] : null,
            itemBuilder: (_, index) {
              final video = videos[index];
              return Padding(
                key: ValueKey(video.id),
                padding: const EdgeInsets.only(bottom: 10),
                child: _RelatedVideoCard(
                  video: video,
                  onTap: onOpen == null ? null : () => onOpen(video),
                  onOpenUser: onOpenUser,
                ),
              );
            },
          );
          // Keep the delegate and per-row repaint boundaries through intro
          // toggles. Scrolling only creates rows in the viewport/cache extent.
          _cached = (
            videos: videos,
            onOpen: onOpen,
            onOpenUser: onOpenUser,
            sliver: sliver,
          );
          return sliver;
        },
      );
}

final class _RelatedVideoCard extends StatefulWidget {
  const _RelatedVideoCard({required this.video, this.onTap, this.onOpenUser});

  final VideoSummary video;
  final VoidCallback? onTap;
  final ValueChanged<UserId>? onOpenUser;

  @override
  State<_RelatedVideoCard> createState() => _RelatedVideoCardState();
}

final class _RelatedVideoCardState extends State<_RelatedVideoCard> {
  bool _hovered = false;
  bool _focused = false;
  bool _authorHovered = false;
  bool _authorFocused = false;

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    final theme = Theme.of(context);
    final authorId = video.authorId;
    final onOpenUser = widget.onOpenUser;
    final canOpenAuthor =
        authorId != null && authorId.isValid && onOpenUser != null;
    return ScrollAwareHoverRegion(
      onHover: (hovered) => setState(() => _hovered = hovered),
      child: InkWell(
        onTap: widget.onTap,
        onFocusChange: (focused) => setState(() => _focused = focused),
        hoverColor: Colors.transparent,
        hoverDuration: Duration.zero,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              height: 79,
              child: VideoCardCover(
                video: video,
                hovered: _hovered,
                focused: _focused,
                borderRadius: 5,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (video.coverUrl.isEmpty)
                      const ColoredBox(
                        color: Colors.black12,
                        child: Icon(Icons.video_library_outlined),
                      )
                    else
                      AppCoverImage(
                        url: video.coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.video_library_outlined),
                      ),
                    Positioned(
                      right: 4,
                      bottom: 3,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Text(
                            durationLabel(video.duration),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 79),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HighlightedText(
                      video.title,
                      query: '',
                      maxLines: 2,
                      showOverflowTooltip: true,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                BiliIcons.up,
                                size: 13,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: ScrollAwareHoverRegion(
                                  onHover: (hovered) =>
                                      setState(() => _authorHovered = hovered),
                                  child: InkWell(
                                    onTap: canOpenAuthor
                                        ? () => onOpenUser(authorId)
                                        : null,
                                    onFocusChange: (focused) => setState(
                                      () => _authorFocused = focused,
                                    ),
                                    hoverColor: Colors.transparent,
                                    hoverDuration: Duration.zero,
                                    child: Text(
                                      video.author,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color:
                                                canOpenAuthor &&
                                                    (_authorHovered ||
                                                        _authorFocused)
                                                ? theme.colorScheme.primary
                                                : null,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 3,
                            children: [
                              _Meta(
                                icon: BiliIcons.playCount,
                                label: compactCount(video.playCount),
                              ),
                              _Meta(
                                icon: BiliIcons.danmaku,
                                label: compactCount(video.danmakuCount),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 5),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

String _failure(Object error, String fallback) =>
    error is AppFailure ? error.message : fallback;
String _publicationTime(DateTime date) =>
    date.toLocal().toString().split('.').first;
