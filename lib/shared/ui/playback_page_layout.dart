import 'dart:math' as math;

import 'package:bili_player/bili_player.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/presentation/workspace_activity.dart';
import '../../domain/responsive_layout_settings.dart';
import 'collapsed_playback_header.dart';
import 'playback_sidebar_toggle.dart';
import 'playback_split_layout.dart';
import 'scroll_collapsing_header.dart';

/// Keeps the player mounted while the information lists collapse its extra
/// square or portrait height before consuming their own scroll distance.
class PlaybackPageLayout extends StatefulWidget {
  const PlaybackPageLayout({
    super.key,
    required this.splitPage,
    required this.wide,
    required this.showInfo,
    required this.listening,
    required this.dimensions,
    required this.collapsedHeight,
    required this.contentKey,
    required this.player,
    required this.info,
    required this.toggleInfo,
    required this.toggleTooltip,
    this.minimumInfoHeight = 0,
    this.collapsedAction,
    this.summaryBuilder,
    this.summaryIdentity,
  });

  final PlaybackSplitPage splitPage;
  final bool wide;
  final bool showInfo;
  final bool listening;
  final VideoDimensions? dimensions;
  final double collapsedHeight;
  final Object contentKey;
  final Widget player;
  final Widget info;
  final VoidCallback toggleInfo;
  final String toggleTooltip;
  final double minimumInfoHeight;
  final CollapsedPlaybackAction? collapsedAction;
  final Widget Function(BuildContext context, {required bool measuring})?
  summaryBuilder;
  final Object? summaryIdentity;

  @override
  State<PlaybackPageLayout> createState() => _PlaybackPageLayoutState();
}

class _PlaybackPageLayoutState extends State<PlaybackPageLayout> {
  final _scroll = ScrollController();
  // Keep the action label stable while the toolbar fades out after a tap.
  CollapsedPlaybackAction _lastAction = CollapsedPlaybackAction.play;

  @override
  void didUpdateWidget(PlaybackPageLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentKey != widget.contentKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => TweenAnimationBuilder<double>(
      tween: Tween(end: widget.collapsedAction == null ? 0 : 1),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, collapse, _) => _layout(context, bounds, collapse),
    ),
  );

  Widget _layout(BuildContext context, BoxConstraints bounds, double collapse) {
    _lastAction = widget.collapsedAction ?? _lastAction;
    // Scaffold already consumes the keyboard inset from the body constraints
    // and clears MediaQuery.viewInsets there. Read the view only to switch
    // layout policy; never subtract the inset a second time.
    final keyboardVisible = View.of(context).viewInsets.bottom > 0;
    final editingInfo = keyboardVisible && widget.showInfo && !widget.wide;
    const infoReserve = 240.0;
    final availablePlayerHeight = math.min(
      widget.collapsedHeight,
      editingInfo
          ? math.max(0.0, bounds.maxHeight - infoReserve)
          : bounds.maxHeight,
    );
    // A short window can otherwise be entirely covered by the paused player.
    // Leave the tab strip and a draggable row accessible in stacked layout.
    final collapsed = widget.wide || !widget.showInfo || widget.listening
        ? availablePlayerHeight
        : math.min(
            availablePlayerHeight,
            math.max(kToolbarHeight, bounds.maxHeight - collapse * infoReserve),
          );
    final dimensions = widget.dimensions;
    var expanded = collapsed;
    if (!widget.wide &&
        !editingInfo &&
        !widget.listening &&
        dimensions != null &&
        dimensions.width > 0 &&
        dimensions.height >= dimensions.width &&
        bounds.maxHeight.isFinite) {
      // Reserve 240 logical pixels for the information tabs and keep the
      // picture within 65% of the page when expanding a portrait source.
      expanded = math.max(
        collapsed,
        math.min(
          bounds.maxWidth * dimensions.height / dimensions.width,
          math.min(bounds.maxHeight * .65, bounds.maxHeight - infoReserve),
        ),
      );
    }
    final infoWidth = widget.wide
        ? PlaybackSplitLayout.sidebarWidth
        : bounds.maxWidth;
    final playerWidth = widget.wide && widget.showInfo
        ? math.max(0.0, bounds.maxWidth - infoWidth)
        : bounds.maxWidth;
    final toolbarRange = math.max(0.0, collapsed - kToolbarHeight);
    final minimum = widget.wide || !widget.showInfo || widget.listening
        ? collapsed
        : collapsed - toolbarRange * collapse;
    final scrollRange = expanded - minimum;
    final infoTop = widget.wide ? 0.0 : minimum;
    final pageHeight =
        widget.wide || !widget.showInfo || scrollRange > 0 || editingInfo
        ? bounds.maxHeight
        : math.max(bounds.maxHeight, infoTop + widget.minimumInfoHeight);
    return PlaybackSplitLayout(
      page: widget.splitPage,
      enabled: widget.wide && !widget.listening,
      showInfo: widget.showInfo,
      dimensions: dimensions,
      contentKey: widget.contentKey,
      summaryIdentity: widget.summaryIdentity ?? widget.contentKey,
      summaryBuilder: widget.summaryBuilder,
      builder: (context, bottomHeight, bottomSummary) => AnimatedBuilder(
        animation: _scroll,
        builder: (context, _) {
          final offset = _scroll.hasClients ? _scroll.offset : 0.0;
          final playerAreaHeight = widget.wide || !widget.showInfo
              ? bounds.maxHeight - bottomHeight
              : expanded - offset.clamp(0.0, scrollRange);
          // Slide the regular player out at its landscape height. Its controls
          // and native surface never have to lay out inside a toolbar.
          final hiddenHeight = minimum < collapsed
              ? math.max(0.0, collapsed - playerAreaHeight)
              : 0.0;
          final content = SingleChildScrollView(
            padding: EdgeInsets.zero,
            child: SizedBox(
              width: bounds.maxWidth,
              height: pageHeight,
              child: Stack(
                children: [
                  Positioned(
                    right: 0,
                    top: infoTop,
                    width: infoWidth,
                    height: math.max(1.0, pageHeight - infoTop),
                    child: ExcludeFocus(
                      excluding: !widget.showInfo,
                      child: Offstage(
                        offstage: !widget.showInfo,
                        // Offstage retains layout and State, but does not
                        // stop tickers or visibility-driven image/preview work.
                        child: WorkspaceActivity(
                          active:
                              widget.showInfo &&
                              WorkspaceActivity.isActive(context),
                          previewing:
                              widget.showInfo &&
                              WorkspaceActivity.isVisible(context) &&
                              !WorkspaceActivity.isActive(context),
                          child: TickerMode(
                            enabled:
                                widget.showInfo &&
                                WorkspaceActivity.isVisible(context),
                            child: NestedScrollView(
                              controller: _scroll,
                              physics: const ClampingScrollPhysics(),
                              headerSliverBuilder: (context, _) => [
                                SliverToBoxAdapter(
                                  child: SizedBox(
                                    height: widget.wide ? 0 : scrollRange,
                                  ),
                                ),
                              ],
                              body: HeaderScrollBody(child: widget.info),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: -hiddenHeight,
                    width: playerWidth,
                    height: playerAreaHeight + hiddenHeight,
                    child: CollapsedPlaybackHeader(
                      hiddenHeight: hiddenHeight,
                      opacity: toolbarRange > 0
                          ? (hiddenHeight / toolbarRange).clamp(0, 1)
                          : 0,
                      action: _lastAction,
                      enabled: widget.collapsedAction != null,
                      child: PlaybackInfoScope.player(
                        wide: widget.wide,
                        showInfo: widget.showInfo,
                        tooltip: widget.toggleTooltip,
                        onToggle: widget.toggleInfo,
                        player: widget.player,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              content,
              if (bottomSummary != null)
                Positioned(
                  left: 0,
                  bottom: 0,
                  width: playerWidth,
                  height: bottomHeight,
                  child: bottomSummary,
                ),
            ],
          );
        },
      ),
    );
  }
}
