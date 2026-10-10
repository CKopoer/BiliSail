import 'dart:async';

import 'package:bili_player/bili_player.dart';

import '../../../domain/user.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../core/network/api_requests.dart';

import '../../../shared/ui/playback_page_commands.dart';
import '../../../shared/ui/width_layout_builder.dart';
import '../../../domain/video.dart';
import '../../../shared/ui/state_view.dart';
import '../../../shared/ui/app_cover_image.dart';
import '../../../shared/ui/highlighted_text.dart';
import '../../../shared/ui/playback_sidebar_toggle.dart';
import '../../../shared/ui/playback_info_tabs.dart';
import '../../../core/presentation/workspace_activity.dart';
import '../../../shared/ui/video_card.dart';
import '../../../shared/ui/video_card_cover.dart';
import 'video_author_header.dart';
import 'video_collection_panel.dart';
import '../application/video_controller.dart';
import '../application/video_extras_controller.dart';
import 'video_comments_panel.dart';
import 'video_tags_panel.dart';
import 'video_access_notice.dart';
import 'watch_later_queue_panel.dart';
import '../domain/watch_later_queue.dart';
import '../application/watch_later_queue_registry.dart';
import '../application/watch_later_queue_playback.dart';
import '../../playback/application/playback_session.dart';
import '../../../shared/ui/bili_icons.dart';

typedef VideoPlayerBuilder = Widget Function(
  BuildContext context,
  VideoDetail detail,
  VideoPart part,
);

final class VideoScreen extends ConsumerStatefulWidget {
  const VideoScreen({
    super.key,
    required this.id,
    this.initialCid,
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
  });
  final VideoId id;
  final String? initialCid;
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
  @override
  ConsumerState<VideoScreen> createState() => _VideoScreenState();
}

final class _VideoScreenState extends ConsumerState<VideoScreen> {
  String? _selectedCid;
  int _tab = 0;
  bool _infoVisible = true;
  bool _descriptionExpanded = false;
  bool _queueExpanded = true;
  VideoDetail? _lastQueueVideo;
  String? _lastQueueCid;
  String? _retainedQueueId;
  WatchLaterQueueRegistry? _retainedRegistry;
  PlaybackSession? _queueSession;
  final WatchLaterQueuePlayback _queuePlayback = WatchLaterQueuePlayback();
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
      _queueSession!.snapshots.removeListener(_onQueueSnapshot);
      _queueSession = null;
    } else if (queue != null && _queueSession == null) {
      _queueSession = ref.read(playbackSessionProvider);
      _queueSession!.snapshots.addListener(_onQueueSnapshot);
    }
  }

  void _onQueueSnapshot() {
    final session = _queueSession;
    final queue = widget.queue;
    if (session != null &&
        session.snapshots.value.phase != PlaybackPhase.ended) {
      _queuePlayback.reset();
    }
    if (session == null ||
        queue == null ||
        session.snapshots.value.phase != PlaybackPhase.ended) {
      return;
    }
    final generation = session.sourceGeneration;
    scheduleMicrotask(() {
      if (!mounted ||
          widget.queue?.id != queue.id ||
          session.sourceGeneration != generation) {
        return;
      }
      final next = _queuePlayback.completed(queue, session, widget.id);
      if (next?.part case final VideoPart part) {
        setState(() => _selectedCid = part.cid);
        widget.onPartChanged?.call(part);
      } else if (next?.video case final VideoId video) {
        widget.onOpenQueueVideo?.call(video);
      }
    });
  }

  @override
  void dispose() {
    _queueSession?.snapshots.removeListener(_onQueueSnapshot);
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
      _queueExpanded = true;
      _queuePlayback.reset();
      _lastQueueVideo = null;
      _lastQueueCid = null;
      if (widget.queue == null) _queueSession?.discardNextVideo();
    }
    _syncQueue();
    if (oldWidget.id != widget.id) {
      _selectedCid = widget.initialCid;
    }
    if (oldWidget.initialCid != widget.initialCid) {
      _selectedCid = widget.initialCid;
    }
  }

  @override
  Widget build(BuildContext context) {
    final queue =
        widget.queue?.sessionEpoch == ref.read(sessionEpochProvider)() &&
            widget.queue?.scope == _queueSession?.accountScope()
        ? widget.queue
        : null;
    // Start the related read alongside detail without rebuilding the player
    // and intro header when only that read changes.
    ref.listen(relatedVideosProvider(widget.id), (_, _) {});
    final detail = ref.watch(videoDetailProvider(widget.id));
    final loaded = detail.asData?.value;
    final transitioning =
        queue != null &&
        loaded == null &&
        detail.isLoading &&
        _lastQueueVideo != null;
    final video = loaded ?? (transitioning ? _lastQueueVideo : null);
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
                      ? _lastQueueCid
                      : _selectedCid ?? widget.initialCid),
            )
            .firstOrNull ??
        video.parts.first;
    if (!transitioning && queue != null) {
      _lastQueueVideo = video;
      _lastQueueCid = selected.cid;
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
                                    Icon(
                                      _descriptionExpanded
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                      size: 16,
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
                          if (_descriptionExpanded) ...[
                            const SizedBox(height: 12),
                            SelectionArea(
                              child: Text(
                                video.description.isEmpty
                                    ? 'UP 主还没有填写简介'
                                    : video.description,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(height: 1.6),
                              ),
                            ),
                          ],
                          VideoTagsPanel(
                            id: widget.id,
                            onSearch: widget.onSearchTag,
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
                    final info = Material(
                      key: _infoKey,
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(6),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (queue != null)
                            if (_queueExpanded)
                              Expanded(
                                child: WatchLaterQueuePanel(
                                  queue: queue,
                                  current: widget.id,
                                  expanded: true,
                                  onToggle: () =>
                                      setState(() => _queueExpanded = false),
                                  onSelect: _openQueueVideo,
                                ),
                              )
                            else
                              WatchLaterQueuePanel(
                                queue: queue,
                                current: widget.id,
                                expanded: false,
                                onToggle: () =>
                                    setState(() => _queueExpanded = true),
                                onSelect: _openQueueVideo,
                              ),
                          if (queue == null || !_queueExpanded) ...[
                            Expanded(
                              child: WorkspaceActivity(
                                active:
                                    showInfo &&
                                    WorkspaceActivity.isActive(context),
                                child: PlaybackInfoTabs(
                                  value: _tab,
                                  onChanged: (tab) =>
                                      setState(() => _tab = tab),
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
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall,
                                        ),
                                      ],
                                    ),
                                  ],
                                  trailing: widget.menuBuilder?.call(
                                    context,
                                    video,
                                    selected,
                                  ),
                                  pageBuilder: (context, tab, active) =>
                                      TickerMode(
                                        enabled: showInfo && active,
                                        child: tab == 0
                                            ? CustomScrollView(
                                                key: const ValueKey(
                                                  'video-intro-scroll',
                                                ),
                                                controller: _introScroll,
                                                slivers: [
                                                  SliverToBoxAdapter(
                                                    child: content,
                                                  ),
                                                  SliverPadding(
                                                    padding:
                                                        const EdgeInsets.fromLTRB(
                                                          12,
                                                          0,
                                                          12,
                                                          12,
                                                        ),
                                                    sliver:
                                                        _RelatedVideosSliver(
                                                          id: widget.id,
                                                          onOpenVideo: widget
                                                              .onOpenVideo,
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
                            ),
                          ],
                        ],
                      ),
                    );
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final player = Column(
                          key: _playerKey,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: wide || !showInfo
                                  ? constraints.maxHeight
                                  : constraints.maxWidth * 9 / 16,
                              width: double.infinity,
                              child: playerContent,
                            ),
                          ],
                        );
                        final playerWithToggle = Stack(
                          children: [
                            player,
                            Positioned(
                              right: 0,
                              top:
                                  (wide || !showInfo
                                          ? constraints.maxHeight
                                          : constraints.maxWidth * 9 / 16) /
                                      2 -
                                  PlaybackSidebarToggle.size.height / 2,
                              child: PlaybackSidebarToggle(
                                tooltip: showInfo ? '收起视频信息' : '展开视频信息',
                                icon: wide
                                    ? (showInfo
                                          ? Icons.chevron_right
                                          : Icons.chevron_left)
                                    : (showInfo
                                          ? Icons.expand_less
                                          : Icons.expand_more),
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
                                        ? (constraints.maxHeight -
                                                  constraints.maxWidth * 9 / 16)
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

  void _changePart(VideoDetail video, VideoPart selected, int direction) {
    // The fullscreen route retains these callbacks across page rebuilds.
    final current =
        video.parts
            .where((part) => part.cid == (_selectedCid ?? widget.initialCid))
            .firstOrNull ??
        selected;
    final next = video.parts.indexOf(current) + direction;
    if (next < 0 || next >= video.parts.length) {
      _openAdjacentQueueVideo(video.summary.id, direction);
      return;
    }
    final part = video.parts[next];
    setState(() => _selectedCid = part.cid);
    widget.onPartChanged?.call(part);
  }

  void _openAdjacentQueueVideo(VideoId id, int direction) {
    final queue = widget.queue;
    final session = _queueSession;
    if (queue == null || session == null) return;
    final adjacent = _queuePlayback.adjacent(queue, session, id, direction);
    if (adjacent != null) _openQueueVideo(adjacent);
  }

  void _openQueueVideo(VideoId id) {
    final queue = widget.queue;
    final session = _queueSession;
    if (id == widget.id ||
        queue == null ||
        session == null ||
        !_queuePlayback.select(queue, session, id)) {
      return;
    }
    widget.onOpenQueueVideo?.call(id);
  }

  Widget _separator(String section) => Divider(
    key: ValueKey('video-info-separator-$section'),
    height: 36,
    thickness: 0.7,
    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.55),
  );
}

final class _RelatedVideosSliver extends ConsumerStatefulWidget {
  const _RelatedVideosSliver({required this.id, this.onOpenVideo});
  final VideoId id;
  final ValueChanged<VideoSummary>? onOpenVideo;

  @override
  ConsumerState<_RelatedVideosSliver> createState() =>
      _RelatedVideosSliverState();
}

final class _RelatedVideosSliverState
    extends ConsumerState<_RelatedVideosSliver> {
  ({
    List<VideoSummary> videos,
    ValueChanged<VideoSummary>? onOpen,
    SliverList sliver,
  })?
  _cached;

  Widget _state(Widget child) {
    _cached = null;
    return SliverToBoxAdapter(child: child);
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(relatedVideosProvider(widget.id))
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
          if (cached != null &&
              identical(cached.videos, videos) &&
              cached.onOpen == onOpen) {
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
                ),
              );
            },
          );
          // Keep the delegate and per-row repaint boundaries through intro
          // toggles. Scrolling only creates rows in the viewport/cache extent.
          _cached = (videos: videos, onOpen: onOpen, sliver: sliver);
          return sliver;
        },
      );
}

final class _RelatedVideoCard extends StatefulWidget {
  const _RelatedVideoCard({required this.video, this.onTap});

  final VideoSummary video;
  final VoidCallback? onTap;

  @override
  State<_RelatedVideoCard> createState() => _RelatedVideoCardState();
}

final class _RelatedVideoCardState extends State<_RelatedVideoCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    return InkWell(
      onTap: widget.onTap,
      onHover: (hovered) => setState(() => _hovered = hovered),
      onFocusChange: (focused) => setState(() => _focused = focused),
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
                            Expanded(
                              child: Text(
                                video.author,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
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
