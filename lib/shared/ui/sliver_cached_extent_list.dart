import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Reuses measured sizes across scroll jumps while keeping rows lazy.
final class SliverCachedExtentList extends SliverList {
  const SliverCachedExtentList({
    super.key,
    required super.delegate,
    this.cacheExtents = true,
  });

  final bool cacheExtents;

  @override
  RenderSliverList createRenderObject(BuildContext context) =>
      _RenderCachedExtentList(
        childManager: context as SliverMultiBoxAdaptorElement,
        cacheExtents: cacheExtents,
      );

  @override
  void updateRenderObject(BuildContext context, RenderSliverList renderObject) {
    super.updateRenderObject(context, renderObject);
    (renderObject as _RenderCachedExtentList).cacheExtents = cacheExtents;
    // Appended rows change the scroll range even when reused visible cards do
    // not invalidate layout. Publish the new extent before a jump/scrollbar drag.
    renderObject.markNeedsLayout();
  }
}

class _RenderCachedExtentList extends RenderSliverList {
  _RenderCachedExtentList({
    required super.childManager,
    required this.cacheExtents,
  });

  static const _maximumMeasurements = 512;
  bool cacheExtents;
  final _extents = <int, double>{};
  double? _crossAxisExtent;
  bool _layingOut = false;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    PaintingBinding.instance.systemFonts.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    PaintingBinding.instance.systemFonts.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  void markNeedsLayout() {
    // A descendant's layout change or a new delegate invalidates old sizes.
    // Scroll-only constraint changes do not call this; inserting/recycling
    // children during our own layout must not discard earlier measurements.
    if (!_layingOut) _extents.clear();
    super.markNeedsLayout();
  }

  @override
  void performLayout() {
    if (_crossAxisExtent != constraints.crossAxisExtent) _extents.clear();
    _crossAxisExtent = constraints.crossAxisExtent;
    _layingOut = true;
    try {
      if (cacheExtents) _skipMeasuredRows();
      super.performLayout();
    } finally {
      _layingOut = false;
    }
  }

  void _skipMeasuredRows() {
    if (_extents.isEmpty) return;
    final first = firstChild;
    final last = lastChild;
    if (first == null || last == null) return;
    final firstOffset = childScrollOffset(first);
    final lastOffset = childScrollOffset(last);
    if (firstOffset == null || lastOffset == null) return;
    final start = constraints.scrollOffset + constraints.cacheOrigin;
    // Overlapping ranges keep their existing Elements and layout untouched.
    if (start + constraints.remainingCacheExtent < firstOffset) {
      final firstIndex = indexOf(first);
      var index = firstIndex;
      var offset = firstOffset;
      while (index > 0 && offset > start) {
        final extent = _extents[index - 1];
        if (extent == null) break;
        offset -= extent;
        index--;
      }
      if (index != firstIndex && offset >= 0) _startAt(index, offset);
    } else if (last.hasSize && start >= lastOffset + paintExtentOf(last)) {
      final nextIndex = indexOf(last) + 1;
      final count = childManager.estimatedChildCount;
      var index = nextIndex;
      var offset = lastOffset + paintExtentOf(last);
      while (count == null || index < count - 1) {
        final extent = _extents[index];
        if (extent == null || offset + extent > start) break;
        offset += extent;
        index++;
      }
      if (index != nextIndex) _startAt(index, offset);
    }
  }

  void _startAt(int index, double offset) {
    // The normal SliverList algorithm would construct and immediately discard
    // every skipped row. Seed it at the same offset, then let Flutter measure
    // the target rows normally, including any unknown part of the gap.
    collectGarbage(childCount, 0);
    addInitialChild(index: index, layoutOffset: offset);
  }

  @override
  void collectGarbage(int leadingGarbage, int trailingGarbage) {
    if (!cacheExtents) {
      super.collectGarbage(leadingGarbage, trailingGarbage);
      return;
    }
    // Capture sizes before Flutter recycles rows, including rows traversed by
    // a forward jump. The bounded cache owns only indices and pixel extents.
    // Rewriting every mounted row here churns the LRU on every scroll layout,
    // even when no row is recycled. Trailing garbage may have stale sizes.
    var remaining = leadingGarbage;
    final boxConstraints = constraints.asBoxConstraints();
    for (
      var child = firstChild;
      child != null && remaining > 0;
      child = childAfter(child), remaining--
    ) {
      // Trailing garbage may still have its old width/dirty layout after a
      // resize or content change; only cache rows measured for this layout.
      if (!child.hasSize || child.constraints != boxConstraints) continue;
      final index = indexOf(child);
      final extent = paintExtentOf(child);
      final previous = _extents.remove(index);
      if (previous != null && previous != extent) _extents.clear();
      _extents[index] = extent;
      if (_extents.length > _maximumMeasurements) {
        _extents.remove(_extents.keys.first);
      }
    }
    super.collectGarbage(leadingGarbage, trailingGarbage);
  }
}
