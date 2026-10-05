import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/presentation/workspace_activity.dart';
import 'scroll_floating_actions.dart';

/// Checks pagination after layout as well as when scrolling toward the end.
/// Keep a distinct key and PageStorageKey for each independently retained list.
final class PagedScrollViewport extends StatefulWidget {
  const PagedScrollViewport({
    super.key,
    required this.active,
    required this.canLoadMore,
    required this.contentVersion,
    required this.onLoadMore,
    required this.builder,
    this.onRefresh,
    this.refreshTooltip = '刷新列表',
    this.keepScrollOffset = true,
  });

  final bool active;
  final bool canLoadMore;
  final Object contentVersion;
  final Future<void> Function() onLoadMore;
  final Widget Function(ScrollController controller) builder;
  final Future<void> Function()? onRefresh;
  final String refreshTooltip;

  /// Query replacement can opt out of restoring offsets from a previous list.
  final bool keepScrollOffset;

  @override
  State<PagedScrollViewport> createState() => _PagedScrollViewportState();
}

final class _PagedScrollViewportState extends State<PagedScrollViewport> {
  late final _scrollController = ScrollController(
    keepScrollOffset: widget.keepScrollOffset,
  );
  bool _active = false;
  bool _checkScheduled = false;
  bool _forceCheck = false;
  bool _requestPending = false;
  bool _showTop = false;
  (Object, double, double)? _lastRequestLayout;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateTopVisibility);
    _scheduleCheck();
  }

  @override
  void didUpdateWidget(PagedScrollViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentVersion != widget.contentVersion ||
        oldWidget.canLoadMore != widget.canLoadMore ||
        oldWidget.active != widget.active) {
      _scheduleCheck(
        force:
            oldWidget.canLoadMore != widget.canLoadMore ||
            oldWidget.active != widget.active,
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncActivity();
  }

  void _syncActivity() {
    final active = widget.active && WorkspaceActivity.isActive(context);
    if (active != _active) {
      _active = active;
      if (active) _scheduleCheck(force: true);
    }
  }

  void _scheduleCheck({bool force = false}) {
    _forceCheck = _forceCheck || force;
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      final force = _forceCheck;
      _forceCheck = false;
      if (!mounted) return;
      _updateTopVisibility();
      _checkForMore(force: force);
    });
    // Metrics notifications can arrive after the frame has finished; request
    // one frame for this coalesced check rather than polling every frame.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _updateTopVisibility() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final show = position.pixels > position.minScrollExtent + 0.5;
    if (show != _showTop && mounted) setState(() => _showTop = show);
  }

  void _checkForMore({required bool force}) {
    if (!_active ||
        !widget.canLoadMore ||
        _requestPending ||
        !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (!position.hasContentDimensions || position.extentAfter > 600) return;
    final layout = (
      widget.contentVersion,
      position.viewportDimension,
      position.maxScrollExtent,
    );
    // Initial layout and its deferred metrics notification may describe the
    // same content. Only a new layout/state, downward scroll, or activation
    // should attempt another page once that request has completed.
    if (!force && layout == _lastRequestLayout) return;
    _lastRequestLayout = layout;
    _requestPending = true;
    unawaited(_loadMore());
  }

  Future<void> _loadMore() async {
    try {
      await widget.onLoadMore();
    } finally {
      _requestPending = false;
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final movingDown = switch (notification) {
      ScrollUpdateNotification(:final scrollDelta) => (scrollDelta ?? 0) > 0,
      OverscrollNotification(:final overscroll) => overscroll > 0,
      _ => false,
    };
    if (movingDown) _scheduleCheck(force: true);
    return false;
  }

  bool _onMetrics(ScrollMetricsNotification notification) {
    if (notification.depth == 0 && notification.metrics.axis == Axis.vertical) {
      _scheduleCheck();
    }
    return false;
  }

  Future<void> _refresh() async {
    final refresh = widget.onRefresh;
    if (refresh == null) return;
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.minScrollExtent);
    }
    await refresh();
  }

  void _toTop() {
    if (!_scrollController.hasClients) return;
    unawaited(
      _scrollController.animateTo(
        _scrollController.position.minScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncActivity();
    return Stack(
      children: [
        TickerMode(
          enabled: _active,
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: _onMetrics,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: widget.builder(_scrollController),
            ),
          ),
        ),
        if (widget.onRefresh != null)
          Positioned(
            right: 20,
            bottom: 20,
            child: ScrollFloatingActions(
              refreshTooltip: widget.refreshTooltip,
              onRefresh: _refresh,
              onToTop: _showTop ? _toTop : null,
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_updateTopVisibility)
      ..dispose();
    super.dispose();
  }
}
