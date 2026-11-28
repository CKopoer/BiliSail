import 'dart:async';

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
import '../../../shared/ui/content_link_scope.dart';
import '../../../shared/ui/featured_paging_scope.dart';
import '../../../shared/ui/featured_selection_scope.dart';
import '../../../shared/ui/playback_navigation.dart';
import '../../../shared/ui/playback_page_commands.dart';
import '../../../shared/ui/playback_split_layout.dart';
import '../../../shared/ui/app_network_image.dart';
import '../../../shared/ui/state_view.dart';
import '../../feed/application/featured_feed_controller.dart';
import '../application/video_controller.dart';
import 'video_actions_bar.dart';
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

class _FeaturedVideoScreenState extends ConsumerState<FeaturedVideoScreen> {
  late final feed = widget.createController()..addListener(_changed);
  final pages = PageController(keepPage: false);
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
      refreshRevision = feed.refreshRevision;
      seedPositionPending = false;
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
    wheelIdle?.cancel();
    pages.dispose();
    feed.dispose();
    super.dispose();
  }

  Future<void> _step(int direction, {bool loop = false}) async {
    if (!_canStep) return;
    final before = feed.selected;
    final revision = feed.refreshRevision;
    var target = before + direction;
    if (target >= feed.end && feed.hasMore) await feed.load();
    if (!mounted ||
        !_canStep ||
        before != feed.selected ||
        revision != feed.refreshRevision) {
      return;
    }
    if (target >= feed.end && loop && !feed.hasMore) target = feed.first;
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
    if (!active ||
        resettingPage ||
        index == feed.selected ||
        feed.at(index) == null) {
      return;
    }
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
    if (!presented || !WorkspaceMediaPermission.isAllowed(context)) {
      return const SizedBox.expand();
    }
    final current = feed.at(feed.selected);
    final detail = current == null
        ? null
        : ref.watch(videoDetailProvider(current.id));
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
                          child: NotificationListener<ScrollEndNotification>(
                            onNotification: _scrollEnded,
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
                            child: _infoPanel(info),
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
    final detail = result?.value;
    return Listener(
      onPointerSignal: _wheel,
      child: ColoredBox(
        color: Colors.black,
        child: index != feed.selected || item == null
            ? item != null && item.coverUrl.isNotEmpty
                  ? AppNetworkImage(url: item.coverUrl, fit: BoxFit.contain)
                  : const SizedBox.expand()
            : Stack(
                fit: StackFit.expand,
                children: [
                  _player(item, detail, failed: result?.hasError == true),
                  if (detail != null)
                    Positioned(
                      left: 12,
                      bottom: 74,
                      right: 70,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: TextButton(
                          onPressed: () => _toggle(_Info.description),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.black54,
                          ),
                          child: Text(
                            '${detail.summary.author}  ·  ${detail.summary.title}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  if (detail != null)
                    Positioned(right: 4, bottom: 62, child: _actions(detail)),
                ],
              ),
      ),
    );
  }

  Widget _player(
    VideoSummary item,
    VideoDetail? detail, {
    required bool failed,
  }) {
    final cid = item.previewCid;
    final seed =
        feed.refreshRevision == 0 && feed.selected == 0 && feed.seed != null;
    final defaultPart = seed || detail?.parts.length == 1
        ? detail?.parts.firstOrNull
        : null;
    final part = cid == null
        ? defaultPart
        : detail?.parts.where((part) => part.cid == cid).firstOrNull;
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
          child: PlaybackPageCommands(
            previousPart: () => _step(-1),
            nextPart: () => _step(1),
            toggleInfo: () => _toggle(_Info.description),
            toggleComments: () => _toggle(_Info.comments),
            hasNext: feed.hasMore || feed.selected + 1 < feed.end,
            onCompleted: () => _step(1),
            onLoopCompleted: () => _step(1, loop: true),
            child: Builder(
              builder: (context) => widget.playerBuilder(context, detail, part),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actions(VideoDetail detail) => VideoActionsScope(
    detail: detail,
    onLogin: widget.onLogin,
    child: Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const VideoActionsBar(featured: true),
          IconButton(
            tooltip: '评论',
            color: Colors.white,
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => _toggle(_Info.comments),
          ),
          const VideoActionsBar(menuOnly: true, featured: true),
        ],
      ),
    ),
  );

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
