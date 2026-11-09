import 'dart:math' as math;

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';

import 'playback_sidebar_toggle.dart';
import 'scroll_collapsing_header.dart';

/// Keeps the player mounted while the information lists collapse its extra
/// square or portrait height before consuming their own scroll distance.
class PlaybackPageLayout extends StatefulWidget {
  const PlaybackPageLayout({
    super.key,
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
  });

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

  @override
  State<PlaybackPageLayout> createState() => _PlaybackPageLayoutState();
}

class _PlaybackPageLayoutState extends State<PlaybackPageLayout> {
  final _scroll = ScrollController();

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
    builder: (context, bounds) {
      // Scaffold already consumes the keyboard inset from the body constraints
      // and clears MediaQuery.viewInsets there. Read the view only to switch
      // layout policy; never subtract the inset a second time.
      final keyboardVisible = View.of(context).viewInsets.bottom > 0;
      final editingInfo = keyboardVisible && widget.showInfo && !widget.wide;
      final collapsed = editingInfo
          ? math.min(
              widget.collapsedHeight,
              math.max(0.0, bounds.maxHeight - 240),
            )
          : widget.collapsedHeight;
      final dimensions = widget.dimensions;
      var expanded = collapsed;
      if (!widget.wide &&
          !editingInfo &&
          !widget.listening &&
          dimensions != null &&
          dimensions.width > 0 &&
          dimensions.height >= dimensions.width &&
          bounds.maxHeight.isFinite) {
        // Leave at least 240 logical pixels and 35% of the page for the
        // information tabs. Very short windows simply have no extra height.
        expanded = math.max(
          collapsed,
          math.min(
            bounds.maxWidth * dimensions.height / dimensions.width,
            math.min(bounds.maxHeight * .65, bounds.maxHeight - 240),
          ),
        );
      }
      final infoWidth = widget.wide ? 380.0 : bounds.maxWidth;
      final playerWidth = widget.wide && widget.showInfo
          ? math.max(0.0, bounds.maxWidth - infoWidth)
          : bounds.maxWidth;
      final scrollRange = expanded - collapsed;
      final pageHeight =
          widget.wide || !widget.showInfo || scrollRange > 0 || editingInfo
          ? bounds.maxHeight
          : math.max(bounds.maxHeight, collapsed + widget.minimumInfoHeight);
      return AnimatedBuilder(
        animation: _scroll,
        builder: (context, _) {
          final offset = _scroll.hasClients ? _scroll.offset : 0.0;
          final playerHeight = widget.wide || !widget.showInfo
              ? bounds.maxHeight
              : expanded - offset.clamp(0.0, scrollRange);
          return SingleChildScrollView(
            padding: EdgeInsets.zero,
            child: SizedBox(
              width: bounds.maxWidth,
              height: pageHeight,
              child: Stack(
                children: [
                  Positioned(
                    right: 0,
                    top: widget.wide ? 0 : collapsed,
                    width: infoWidth,
                    height: math.max(
                      1.0,
                      pageHeight - (widget.wide ? 0 : collapsed),
                    ),
                    child: ExcludeFocus(
                      excluding: !widget.showInfo,
                      child: Offstage(
                        offstage: !widget.showInfo,
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
                  Positioned(
                    left: 0,
                    top: 0,
                    width: playerWidth,
                    height: playerHeight,
                    child: widget.player,
                  ),
                  if (widget.wide)
                    Positioned(
                      right: widget.showInfo ? infoWidth : 0,
                      top: math.max(
                        0,
                        playerHeight / 2 -
                            PlaybackSidebarToggle.size.height / 2,
                      ),
                      child: PlaybackSidebarToggle(
                        tooltip: widget.toggleTooltip,
                        onPressed: widget.toggleInfo,
                        icon: widget.showInfo
                            ? Icons.chevron_right
                            : Icons.chevron_left,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
