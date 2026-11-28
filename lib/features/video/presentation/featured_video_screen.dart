import 'dart:async';

import 'package:bili_player/bili_player.dart'
    show VideoCompositionScope, VideoSurface;
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/input/input_stroke.dart';
import '../../../core/input/shortcut_dispatcher.dart';
import '../../../core/presentation/input_scope.dart';
import '../../../core/presentation/workspace_activity.dart';
import '../../../core/presentation/page_back_scope.dart';
import '../../../core/presentation/motion_preferences.dart';
import '../../../domain/content_link.dart';
import '../../../domain/recommendation_playback_context.dart';
import '../../../domain/shortcut_command.dart';
import '../../../shared/ui/recommendation_playback_scope.dart';
import '../../../domain/user.dart';
import '../../../domain/video.dart';
import '../../../shared/ui/bottom_navigation_scroll_region.dart';
import '../../../shared/ui/content_link_scope.dart';
import '../../../shared/ui/featured_paging_scope.dart';
import '../../../shared/ui/featured_selection_scope.dart';
import '../../../shared/ui/playback_navigation.dart';
import '../../../shared/ui/playback_page_commands.dart';
import '../../../shared/ui/player_picture.dart';
import '../../../shared/ui/playback_split_layout.dart';
import '../../../shared/ui/state_view.dart';
import '../../feed/application/featured_feed_controller.dart';
import '../../playback/application/playback_manager.dart';
import '../../playback/application/playback_session.dart';
import '../application/video_controller.dart';
import '../application/featured_video_preparation.dart';
import 'featured_video_overlay.dart';
import 'video_comments_panel.dart';
import 'video_screen.dart' show VideoPlayerBuilder;

enum _Info { description, comments }

class FeaturedVideoScreen extends ConsumerStatefulWidget {
  const FeaturedVideoScreen({
    super.key,
    required this.createController,
    required this.playerBuilder,
    required this.onLogin,
    required this.onOpenUser,
    required this.splitWidth,
    this.onReturnToVideo,
    this.seedAttribution,
    this.seedLink = const ContentLink(),
  });
  final FeaturedFeedController Function() createController;
  final VideoPlayerBuilder playerBuilder;
  final VoidCallback onLogin;
  final ValueChanged<UserId> onOpenUser;
  final int splitWidth;
  final VoidCallback? onReturnToVideo;
  final ContentLink seedLink;
  final RecommendationPlaybackContext? seedAttribution;
  @override
  ConsumerState<FeaturedVideoScreen> createState() =>
      _FeaturedVideoScreenState();
}

class _FeaturedVideoScreenState extends ConsumerState<FeaturedVideoScreen>
    with WidgetsBindingObserver {
  PlaybackSession? _preparingSession;
  int _direction = 1;
  bool _dragAimed = false;
  bool _appVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appVisible = _mayPrepare(WidgetsBinding.instance.lifecycleState);
  }

  static bool _mayPrepare(AppLifecycleState? state) =>
      state == null || state == AppLifecycleState.resumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = _mayPrepare(state);
    if (visible == _appVisible) return;
    if (!visible) _preparingSession?.leaveFeatured(this);
    setState(() => _appVisible = visible);
  }

  void _aim(int direction, {bool renew = false}) {
    if (direction == 0 || (!renew && direction == _direction)) return;
    _direction = direction;
    // Scroll updates arrive after layout. Direction only matters once per
    // reversal, before the page settles.
    final selected = feed.at(feed.selected);
    if (_appVisible && active && selected != null) _nominate(selected);
  }

  void _nominate(VideoSummary selected) {
    if (_preparingSession == null) return;
    final candidate =
        feed.at(feed.selected + _direction) ??
        feed.at(feed.selected - _direction);
    final cid = candidate == null
        ? null
        : candidate.previewCid ??
              ref
                  .read(videoDetailProvider(candidate.id))
                  .value
                  ?.parts
                  .singleOrNull
                  ?.cid;
    _preparingSession?.setFeaturedNeighbor(this, (
      selected.id,
      selected.previewCid,
    ), candidate == null || cid == null ? null : (candidate.id, cid));
  }

  late final feed = widget.createController()..addListener(_changed);
  late final PageController pages = PageController(
    keepPage: false,
    // Media permission can detach the viewport while the feed stays mounted.
    onAttach: (position) {
      if (!position.hasViewportDimension) pages.jumpToPage(feed.selected);
    },
  );
  final _visitedParts = <(VideoId, String?)>{};
  final controlsInset = ValueNotifier(0.0);
  bool _showVideoOverlays = true;
  double? pendingControlsInset;
  _Info? panel;
  Timer? wheelIdle;
  double wheelDelta = 0;
  bool wheelConsumed = false, moving = false, active = false;
  bool presented = false;
  bool resettingPage = false;
  int? selectionRevision;
  int refreshRevision = 0;
  late bool seedPositionPending = widget.seedLink.position != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    active =
        WorkspaceActivity.isActive(context) &&
        WorkspaceMediaPermission.isAllowed(context);
    if (!active) _preparingSession?.leaveFeatured(this);
    final revision = feed.seed == null
        ? FeaturedSelectionScope.revisionOf(context)
        : null;
    final reload =
        active &&
        presented &&
        selectionRevision != null &&
        revision != null &&
        selectionRevision != revision;
    if (active || selectionRevision == null) selectionRevision = revision;
    if (active) presented = true;
    feed.setActive(active, reload: reload);
  }

  void _changed() {
    if (!mounted) return;
    if (refreshRevision != feed.refreshRevision) {
      _preparingSession?.clearFeaturedVisits(this);
      _visitedParts.clear();
      refreshRevision = feed.refreshRevision;
      seedPositionPending = false;
      _direction = 1;
      panel = null;
      resettingPage = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (pages.hasClients) pages.jumpToPage(feed.selected);
        resettingPage = false;
      });
    }
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _preparingSession?.clearFeaturedVisits(this);
    _preparingSession?.leaveFeatured(this);
    wheelIdle?.cancel();
    pages.dispose();
    controlsInset.dispose();
    feed.dispose();
    super.dispose();
  }

  Future<void> _step(int direction) async {
    if (!_canStep) return;
    _aim(direction, renew: true);
    final before = feed.selected;
    final revision = feed.refreshRevision;
    final target = before + direction;
    if (target >= feed.end && feed.hasMore) await feed.load();
    if (!mounted ||
        !_canStep ||
        before != feed.selected ||
        revision != feed.refreshRevision) {
      return;
    }
    if (feed.at(target) == null || !pages.hasClients) return;
    if (shouldReduceMotion(context)) {
      pages.jumpToPage(target);
      _settle(target);
    } else {
      moving = true;
      try {
        await pages.animateToPage(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } finally {
        moving = false;
      }
    }
  }

  bool get _canStep =>
      active &&
      !moving &&
      !resettingPage &&
      panel == null &&
      ModalRoute.of(context)?.isCurrent != false;

  void _settle(int index) {
    final selected = feed.at(index);
    if (!active ||
        resettingPage ||
        index == feed.selected ||
        selected == null) {
      return;
    }
    final detail = videoDetailProvider(selected.id);
    if (ref.exists(detail) && ref.read(detail).hasError) ref.invalidate(detail);
    _direction = (index - feed.selected).sign;
    seedPositionPending = false;
    feed.select(index);
  }

  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.scrollDelta.dy.abs() <= event.scrollDelta.dx.abs() ||
        !active ||
        panel != null ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      wheelIdle?.cancel();
      wheelDelta += event.scrollDelta.dy;
      if (!wheelConsumed && wheelDelta.abs() >= 24) {
        wheelConsumed = true;
        unawaited(_step(wheelDelta.sign.toInt()));
      }
      wheelIdle = Timer(const Duration(milliseconds: 180), () {
        wheelDelta = 0;
        wheelConsumed = false;
      });
    });
  }

  void _toggle(_Info kind) =>
      setState(() => panel = panel == kind ? null : kind);

  CommandOutcome _pageWithKey(InputStroke stroke, int direction) {
    if (stroke.phase != InputPhase.down || !_canStep) {
      return CommandOutcome.noOp;
    }
    unawaited(_step(direction));
    return CommandOutcome.completed;
  }

  bool _scrollEnded(ScrollEndNotification notification) {
    if (notification.depth == 0 && pages.hasClients) {
      final index = pages.page?.round();
      if (index != null) {
        scheduleMicrotask(() {
          if (mounted && pages.hasClients && pages.page?.round() == index) {
            _settle(index);
          }
        });
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final permitted = presented && WorkspaceMediaPermission.isAllowed(context);
    final current = permitted ? feed.at(feed.selected) : null;
    final detail = current == null
        ? null
        : ref.watch(videoDetailProvider(current.id));
    if (active && current != null && detail?.value != null) {
      final key = (current.id, current.previewCid);
      _visitedParts
        ..remove(key)
        ..add(key);
      if (_visitedParts.length > featuredPlaybackHistoryLimit) {
        _visitedParts.remove(_visitedParts.first);
      }
    }
    // Keep completed detail providers alive with the feed, including a visit
    // to another workspace page. Adjacent, unvisited reads remain speculative.
    for (final (id, _) in _visitedParts) {
      if (id != current?.id) ref.watch(videoDetailProvider(id));
    }
    if (!permitted) return const SizedBox.expand();
    if (active && _appVisible) {
      if (current != null &&
          detail?.value != null &&
          ref.watch(featuredPlayInfoPreparationProvider) != null &&
          ref.watch(playbackManagerProvider) != null) {
        final session = ref.read(playbackSessionProvider);
        if (!identical(_preparingSession, session)) {
          _preparingSession?.clearFeaturedVisits(this);
          _preparingSession?.leaveFeatured(this);
          _preparingSession = session;
        }
      }
      watchFeaturedVideoPreparation(
        ref,
        current: current,
        previous: feed.at(feed.selected - 1),
        next: feed.at(feed.selected + 1),
        hasReusableMedia: _preparingSession?.hasFeaturedVisit,
      );
      if (current != null && detail?.value != null) _nominate(current);
    }
    return CommandTargetScope<Object>(
      scope: CommandScope.page,
      active: active && panel == null,
      commands: {
        FeaturedPagingShortcut.previous: (stroke) => _pageWithKey(stroke, -1),
        FeaturedPagingShortcut.next: (stroke) => _pageWithKey(stroke, 1),
      },
      child: _viewer(current, detail),
    );
  }

  Widget _viewer(VideoSummary? current, AsyncValue<VideoDetail>? detail) {
    return PageBackHandler(
      enabled: active && (panel != null || widget.onReturnToVideo != null),
      onBack: () {
        if (panel != null) {
          setState(() => panel = null);
        } else {
          widget.onReturnToVideo?.call();
        }
        return true;
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          current == null
              ? feed.busy
                    ? const StateView.loading(message: '正在加载精选…')
                    : StateView.empty(
                        message: feed.error ?? '暂无精选视频',
                        actionLabel: '重新加载',
                        onAction: feed.hasMore ? feed.load : feed.refresh,
                      )
              : LayoutBuilder(
                  builder: (context, bounds) {
                    final wide = bounds.maxWidth >= widget.splitWidth;
                    final info = detail?.value;
                    final show = panel != null && info != null;
                    return Stack(
                      children: [
                        Positioned.fill(
                          right: wide && show
                              ? PlaybackSplitLayout.sidebarWidth
                              : 0,
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (event) {
                              if (event is ScrollStartNotification &&
                                  event.depth == 0) {
                                _dragAimed = false;
                              }
                              if (event is ScrollEndNotification) {
                                return _scrollEnded(event);
                              }
                              if (event is ScrollUpdateNotification &&
                                  event.depth == 0 &&
                                  event.dragDetails != null) {
                                final offset =
                                    (pages.page ?? feed.selected.toDouble()) -
                                    feed.selected;
                                if (offset.abs() > .04) {
                                  _aim(offset.sign.toInt(), renew: !_dragAimed);
                                  _dragAimed = true;
                                }
                              }
                              return false;
                            },
                            child: PageView.builder(
                              controller: pages,
                              scrollDirection: Axis.vertical,
                              physics: show
                                  ? const NeverScrollableScrollPhysics()
                                  : _FeaturedScrollPhysics(feed.first),
                              itemCount: feed.end,
                              itemBuilder: (context, index) =>
                                  _page(index, detail),
                            ),
                          ),
                        ),
                        if (show && !wide)
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => setState(() => panel = null),
                            ),
                          ),
                        if (show)
                          Positioned(
                            right: 0,
                            left: wide ? null : 0,
                            top: wide ? 0 : null,
                            bottom: 0,
                            width: wide
                                ? PlaybackSplitLayout.sidebarWidth
                                : null,
                            height: wide ? null : bounds.maxHeight * .62,
                            child: BottomNavigationScrollExclusion(
                              child: _infoPanel(info),
                            ),
                          ),
                      ],
                    );
                  },
                ),
          if (feed.error case final message?
              when current != null && panel == null)
            PositionedDirectional(
              start: feed.seed == null ? 8 : 64,
              end: 8,
              top: 8,
              child: Align(
                alignment: AlignmentDirectional.topStart,
                child: TextButton(
                  onPressed: feed.load,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.black54,
                  ),
                  child: Text('$message · 重试', overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
          if (feed.seed != null)
            PositionedDirectional(
              start: 8,
              top: 8,
              child: BackButton(
                style: IconButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.black54,
                ),
                onPressed: () {
                  if (panel != null) {
                    setState(() => panel = null);
                  } else {
                    (widget.onReturnToVideo ??
                            PlaybackNavigation.maybeOf(context)?.onBack)
                        ?.call();
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _page(int index, AsyncValue<VideoDetail>? result) {
    final item = feed.at(index);
    if (item == null) return const ColoredBox(color: Colors.black);
    final selected = index == feed.selected;
    final seed = refreshRevision == 0 && index == 0 && feed.seed != null;
    final provider = videoDetailProvider(item.id);
    final detail = selected
        ? result?.value
        : item.previewCid == null && ref.exists(provider)
        ? ref.read(provider).value
        : null;
    final part = _partFor(item, detail, seed: seed);
    final pictureCid = item.previewCid ?? part?.cid;
    return Listener(
      onPointerSignal: _wheel,
      child: _FeaturedSlot(
        key: ValueKey((index, item.id, item.previewCid)),
        picture: (inline) => _slotPicture(item.id, pictureCid, inline),
        foreground: !selected
            ? null
            : (inline) => Stack(
                fit: StackFit.expand,
                children: [
                  _player(
                    item,
                    detail,
                    part,
                    inline,
                    seed: seed,
                    failed: result?.hasError == true,
                  ),
                  if (active && _showVideoOverlays && detail != null)
                    FeaturedVideoOverlay(
                      key: ValueKey(detail.summary.id),
                      detail: detail,
                      controlsInset: controlsInset,
                      onLogin: widget.onLogin,
                      onOpenUser: widget.onOpenUser,
                      onShowDescription: () => _toggle(_Info.description),
                      onShowComments: () => _toggle(_Info.comments),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _slotPicture(
    VideoId video,
    String? cid,
    FeaturedInlinePicture inline,
  ) {
    final session = _preparingSession;
    if (session == null || !active) {
      return const SizedBox.expand();
    }
    return AnimatedBuilder(
      animation: Listenable.merge([
        session,
        session.featuredStandby?.previewChanges,
        inline.suspended,
      ]),
      builder: (_, _) {
        final engine = inline.suspended.value
            ? null
            : session.featuredSlotEngine(
                this,
                video,
                cid,
                allowPreview: _appVisible,
              );
        return engine == null
            ? const SizedBox.expand()
            : IgnorePointer(
                child: PlayerPicture(
                  controller: inline.controller,
                  child: VideoSurface(engine: engine),
                ),
              );
      },
    );
  }

  Widget _player(
    VideoSummary item,
    VideoDetail? detail,
    VideoPart? part,
    FeaturedInlinePicture inline, {
    required bool seed,
    required bool failed,
  }) {
    if (detail == null && !failed) {
      return const Center(child: CircularProgressIndicator());
    }
    if (detail == null || part == null) {
      return StateView.error(
        message: detail == null ? '视频详情加载失败' : '找不到此视频分 P',
        onAction: () => ref.invalidate(videoDetailProvider(item.id)),
      );
    }
    return RecommendationPlaybackScope(
      value: seed ? widget.seedAttribution : item.recommendationPlayback,
      child: ContentLinkScope(
        link: seed && seedPositionPending
            ? widget.seedLink
            : const ContentLink(),
        child: FeaturedPagingScope(
          inlinePicture: _preparingSession == null ? null : inline,
          onControlsInsetChanged: _updateControlsInset,
          showVideoOverlays: _showVideoOverlays,
          onToggleVideoOverlays: _toggleVideoOverlays,
          child: PlaybackPageCommands(
            previousPart: () => _step(-1),
            nextPart: () => _step(1),
            toggleInfo: () => _toggle(_Info.description),
            toggleComments: () => _toggle(_Info.comments),
            hasNext: feed.hasMore || feed.selected + 1 < feed.end,
            child: Builder(
              builder: (context) => widget.playerBuilder(context, detail, part),
            ),
          ),
        ),
      ),
    );
  }

  VideoPart? _partFor(
    VideoSummary item,
    VideoDetail? detail, {
    required bool seed,
  }) {
    final parts = detail?.parts;
    if (parts == null) return null;
    if (item.previewCid case final cid?) {
      return parts.where((part) => part.cid == cid).firstOrNull;
    }
    return seed ? parts.firstOrNull : parts.singleOrNull;
  }

  void _toggleVideoOverlays() =>
      setState(() => _showVideoOverlays = !_showVideoOverlays);

  void _updateControlsInset(double height) {
    if (pendingControlsInset != null) {
      pendingControlsInset = height;
      return;
    }
    if (controlsInset.value == height) return;
    // The player measures during layout. Reposition the sibling next frame.
    pendingControlsInset = height;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final inset = pendingControlsInset;
      pendingControlsInset = null;
      if (mounted && inset != null) controlsInset.value = inset;
    });
  }

  Widget _infoPanel(VideoDetail detail) => Material(
    color: Theme.of(context).colorScheme.surface,
    elevation: 8,
    child: Column(
      children: [
        ListTile(
          title: Text(panel == _Info.comments ? '评论' : '视频信息'),
          trailing: CloseButton(onPressed: () => setState(() => panel = null)),
        ),
        Expanded(
          child: panel == _Info.comments
              ? VideoCommentsPanel(
                  key: ValueKey(detail.summary.id),
                  detail: detail,
                  onLogin: widget.onLogin,
                  onOpenUser: widget.onOpenUser,
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      detail.summary.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(detail.summary.author),
                    const SizedBox(height: 12),
                    SelectableText(detail.description),
                  ],
                ),
        ),
      ],
    ),
  );
}

final class _FeaturedSlot extends StatefulWidget {
  const _FeaturedSlot({super.key, required this.picture, this.foreground});

  final Widget Function(FeaturedInlinePicture) picture;
  final Widget Function(FeaturedInlinePicture)? foreground;

  @override
  State<_FeaturedSlot> createState() => _FeaturedSlotState();
}

final class _FeaturedSlotState extends State<_FeaturedSlot> {
  final _inline = FeaturedInlinePicture();

  @override
  void dispose() {
    _inline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: VideoCompositionScope.of(context).compose(
      context,
      layers: [widget.picture(_inline), ?widget.foreground?.call(_inline)],
    ),
  );
}

/// Earlier pages may have been evicted while absolute pager positions stay stable.
class _FeaturedScrollPhysics extends ScrollPhysics {
  const _FeaturedScrollPhysics(this.first, {super.parent});
  final int first;
  @override
  _FeaturedScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _FeaturedScrollPhysics(first, parent: buildParent(ancestor));
  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    final floor = first * position.viewportDimension;
    if (first > 0 && value < floor && value < position.pixels) {
      return value - (position.pixels < floor ? position.pixels : floor);
    }
    return super.applyBoundaryConditions(position, value);
  }
}
