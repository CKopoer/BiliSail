import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderSliverList;

import 'text_measurement_cache.dart';

const _desktopSpacing = 20.0;

({int columns, double width, double spacing, double runSpacing}) _layout(
  BuildContext context,
  double extent,
) {
  final compact = extent < 600;
  final spacing = compact ? 6.0 : _desktopSpacing;
  final textScaler = MediaQuery.textScalerOf(context);
  // Sample the 15px card title. Android's nonlinear font scaling leaves large
  // reference sizes unchanged, so scaling a card width misses enlarged text.
  final titleScale = textScaler.scale(15) / 15;
  final minimum = (260 * titleScale).clamp(260, 450);
  // Two cards remain readable on phones; tablet rows can use three smaller
  // cards before the regular desktop minimum permits additional columns.
  final compactMinimum = (140 * titleScale).clamp(140, 210);
  final threeCardMinimum = (160 * titleScale).clamp(160, 240);
  final minimumColumns = extent >= threeCardMinimum * 3 + spacing * 2
      ? 3
      : extent >= compactMinimum * 2 + _desktopSpacing
      ? 2
      : 1;
  final columns = ((extent + _desktopSpacing) / (minimum + _desktopSpacing))
      .floor()
      .clamp(minimumColumns, 12);
  return (
    columns: columns,
    width: (extent - (columns - 1) * spacing) / columns,
    spacing: spacing,
    runSpacing: compact ? 16.0 : 24.0,
  );
}

/// Shared list insets measured before padding, including resizable windows.
final class SliverCardGridPadding extends StatelessWidget {
  const SliverCardGridPadding({
    super.key,
    required this.sliver,
    this.top = 8,
    this.bottom = 24,
    this.desktopInset = 20,
  });

  final Widget sliver;
  final double top, bottom, desktopInset;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final inset = constraints.crossAxisExtent < 600 ? 4.0 : desktopInset;
      return SliverPadding(
        padding: EdgeInsets.fromLTRB(inset, top, inset, bottom),
        sliver: sliver,
      );
    },
  );
}

/// Fill the available width with equal cards, including the final partial row.
final class ResponsiveCardGrid extends StatelessWidget {
  const ResponsiveCardGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => TextMeasurementCacheScope(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final layout = _layout(context, constraints.maxWidth);
        return Wrap(
          spacing: layout.spacing,
          runSpacing: layout.runSpacing,
          children: [
            for (final child in children)
              SizedBox(
                width: layout.width,
                child: RepaintBoundary(child: child),
              ),
          ],
        );
      },
    ),
  );
}

/// Lazily build rows with natural heights for cards and enlarged text.
final class SliverResponsiveCardGrid extends StatefulWidget {
  const SliverResponsiveCardGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<SliverResponsiveCardGrid> createState() =>
      _SliverResponsiveCardGridState();
}

final class _SliverResponsiveCardGridState
    extends State<SliverResponsiveCardGrid> {
  ({int columns, double width, double spacing, double runSpacing})?
  _previousLayout;
  Widget? _rows;

  @override
  void didUpdateWidget(SliverResponsiveCardGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount ||
        oldWidget.itemBuilder != widget.itemBuilder) {
      _rows = null;
    }
  }

  @override
  Widget build(BuildContext context) => TextMeasurementCacheScope(
    child: SliverLayoutBuilder(
      builder: (context, constraints) {
        final layout = _layout(context, constraints.crossAxisExtent);
        // Sliver constraints also change on every scroll frame. Reusing the rows
        // keeps a scroll offset change from replacing the delegate and rebuilding
        // all visible cards; cross-axis layout and content changes still update it.
        if (_rows case final rows? when layout == _previousLayout) return rows;
        _previousLayout = layout;
        return _rows = _CardRows(
          itemCount: (widget.itemCount / layout.columns).ceil(),
          itemBuilder: (context, row) => Padding(
            padding: EdgeInsets.only(bottom: layout.runSpacing),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: layout.spacing,
              children: [
                for (var column = 0; column < layout.columns; column++)
                  if (row * layout.columns + column < widget.itemCount)
                    SizedBox(
                      width: layout.width,
                      // Hover/preview changes on one card must not repaint the
                      // other cards in this row's sliver repaint boundary.
                      child: RepaintBoundary(
                        child: widget.itemBuilder(
                          context,
                          row * layout.columns + column,
                        ),
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _CardRows extends SliverList {
  _CardRows({required int itemCount, required IndexedWidgetBuilder itemBuilder})
    : super(
        delegate: SliverChildBuilderDelegate(
          itemBuilder,
          childCount: itemCount,
        ),
      );

  @override
  void updateRenderObject(BuildContext context, RenderSliverList renderObject) {
    super.updateRenderObject(context, renderObject);
    // Appended rows change the scroll range even when reused visible cards do
    // not invalidate layout. Publish the new extent before a jump/scrollbar drag.
    renderObject.markNeedsLayout();
  }
}
