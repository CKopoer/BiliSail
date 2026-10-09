import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'retained_tab_view.dart';
import 'tab_paging_motion.dart';

/// The indicator and horizontal strip follow the content pages' progress.
final class PagingTabStrip<T extends Object> extends StatefulWidget {
  const PagingTabStrip({
    super.key,
    required this.tabs,
    required this.value,
    required this.onSelected,
    required this.labelBuilder,
    required this.buttonStyle,
    this.progress,
    this.itemKey,
    this.spacing = 3,
    this.fullWidthIndicator = false,
    this.indicatorHeight = 2,
    this.unselectedColor,
  });

  final List<T> tabs;
  final T? value;
  final ValueChanged<T> onSelected;
  final Widget Function(BuildContext, T) labelBuilder;
  final ButtonStyle buttonStyle;
  final TabPagingProgress? progress;
  final Key Function(T)? itemKey;
  final double spacing, indicatorHeight;
  final bool fullWidthIndicator;
  final Color? unselectedColor;

  @override
  State<PagingTabStrip<T>> createState() => _PagingTabStripState<T>();
}

final class _PagingTabStripState<T extends Object>
    extends State<PagingTabStrip<T>>
    with SingleTickerProviderStateMixin {
  final _rowKey = GlobalKey();
  final _itemKeys = <T, GlobalKey>{};
  bool _scrollPending = false;
  int _indexOf(T? value) => value == null
      ? 0
      : widget.tabs.indexOf(value).clamp(0, widget.tabs.length - 1);
  late final _fallback = AnimationController.unbounded(
    vsync: this,
    value: _indexOf(widget.value).toDouble(),
  );

  double get _position => widget.progress?.isAttached == true
      ? widget.progress?.value ?? _fallback.value
      : _fallback.value;

  @override
  void initState() {
    super.initState();
    _fallback.addListener(_onProgressChanged);
    widget.progress?.addListener(_onProgressChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Invalidate on window/font changes; offsets use the strip's own viewport.
    MediaQuery.sizeOf(context);
    MediaQuery.textScalerOf(context);
    _followProgress();
  }

  void _onProgressChanged() {
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      _followProgress();
    } else {
      _scrollToProgress();
    }
  }

  void _followProgress() {
    if (_scrollPending) return;
    _scrollPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollPending = false;
      _scrollToProgress();
    });
  }

  void _scrollToProgress() {
    if (!mounted || widget.value == null || widget.tabs.isEmpty) return;
    final value = _position.clamp(0, widget.tabs.length - 1).toDouble();
    final itemContext = _itemKeys[widget.tabs[value.floor()]]?.currentContext;
    final item = itemContext?.findRenderObject();
    final next = _itemKeys[widget.tabs[value.ceil()]]?.currentContext
        ?.findRenderObject();
    if (itemContext == null ||
        item is! RenderBox ||
        !item.hasSize ||
        next is! RenderBox ||
        !next.hasSize) {
      return;
    }
    final scrollable = Scrollable.maybeOf(itemContext);
    if (scrollable == null || scrollable.position.axis != Axis.horizontal) {
      return;
    }
    final position = scrollable.position;
    if (!position.hasContentDimensions ||
        position.maxScrollExtent <= position.minScrollExtent) {
      return;
    }
    final viewport = RenderAbstractViewport.of(item);
    final start = viewport.getOffsetToReveal(item, .5).offset;
    final end = viewport.getOffsetToReveal(next, .5).offset;
    final target = (start + (end - start) * (value - value.floor())).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    // Paging already supplies the animation, including rebound and reduced
    // motion. A second scroll animation would trail behind the finger.
    // Move only this strip, leaving the surrounding vertical header alone.
    if ((position.pixels - target).abs() > .01) position.jumpTo(target);
  }

  @override
  void didUpdateWidget(PagingTabStrip<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.progress, widget.progress)) {
      oldWidget.progress?.removeListener(_onProgressChanged);
      widget.progress?.addListener(_onProgressChanged);
    }
    if (oldWidget.value != widget.value && widget.value != null) {
      final target = _indexOf(widget.value).toDouble();
      if (widget.progress?.isAttached == true) {
        _fallback.value = target;
      } else {
        _fallback.animateTo(
          target,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : TabPagingMotion.duration,
          curve: Curves.ease,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_fallback, widget.progress]),
    builder: (context, _) {
      _followProgress();
      final colors = Theme.of(context).colorScheme;
      final position = _position;
      final inactive = widget.unselectedColor ?? colors.onSurface;
      return CustomPaint(
        foregroundPainter: _PagingIndicatorPainter(
          rowKey: _rowKey,
          itemKeys: [
            for (final tab in widget.tabs)
              _itemKeys.putIfAbsent(tab, GlobalKey.new),
          ],
          position: position,
          color: colors.primary,
          height: widget.indicatorHeight,
          fullWidth: widget.fullWidthIndicator,
          visible: widget.value != null,
        ),
        child: Row(
          key: _rowKey,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (index, tab) in widget.tabs.indexed)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: widget.spacing),
                child: SizedBox(
                  key: _itemKeys[tab],
                  child: Semantics(
                    selected: widget.value == tab,
                    child: TextButton(
                      key: widget.itemKey?.call(tab),
                      onPressed: () => widget.onSelected(tab),
                      style: widget.buttonStyle.copyWith(
                        animationDuration: Duration.zero,
                        foregroundColor: WidgetStatePropertyAll(
                          Color.lerp(
                            inactive,
                            colors.primary,
                            widget.value == null
                                ? 0
                                : (1 - (position - index).abs()).clamp(0, 1),
                          ),
                        ),
                      ),
                      child: widget.fullWidthIndicator
                          ? widget.labelBuilder(context, tab)
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                widget.labelBuilder(context, tab),
                                const SizedBox(height: 6),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );

  @override
  void dispose() {
    widget.progress?.removeListener(_onProgressChanged);
    _fallback.dispose();
    super.dispose();
  }
}

final class _PagingIndicatorPainter extends CustomPainter {
  const _PagingIndicatorPainter({
    required this.rowKey,
    required this.itemKeys,
    required this.position,
    required this.color,
    required this.height,
    required this.fullWidth,
    required this.visible,
  });

  final GlobalKey rowKey;
  final List<GlobalKey> itemKeys;
  final double position, height;
  final Color color;
  final bool fullWidth, visible;

  Rect? _rect(int index) {
    final row = rowKey.currentContext?.findRenderObject();
    final item = itemKeys[index].currentContext?.findRenderObject();
    if (row is! RenderBox || item is! RenderBox || !item.hasSize) return null;
    final offset = item.localToGlobal(Offset.zero, ancestor: row);
    final width = fullWidth ? item.size.width : 20.0;
    return Rect.fromLTWH(
      offset.dx + (item.size.width - width) / 2,
      offset.dy + item.size.height - height - (fullWidth ? 0 : 8),
      width,
      height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible || itemKeys.isEmpty) return;
    final value = position.clamp(0, itemKeys.length - 1).toDouble();
    final source = _rect(value.floor());
    final target = _rect(value.ceil());
    if (source == null || target == null) return;
    final rect = Rect.lerp(source, target, value - value.floor());
    if (rect != null) canvas.drawRect(rect, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PagingIndicatorPainter oldDelegate) => true;
}
