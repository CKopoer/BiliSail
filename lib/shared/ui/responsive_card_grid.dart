import 'package:material_ui/material_ui.dart';

import 'sliver_cached_extent_list.dart';
import 'text_measurement_cache.dart';
import 'responsive_layout_scope.dart';

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
  var columns = ((extent + _desktopSpacing) / (minimum + _desktopSpacing))
      .floor()
      .clamp(minimumColumns, 12);
  if (ResponsiveLayoutScope.of(context).videoGridMinWidths case final widths?) {
    // Custom thresholds refer to default title size; enlarged text still
    // receives more horizontal space. Smaller text never adds extra columns.
    final scale = titleScale < 1 ? 1.0 : titleScale;
    columns = 1;
    for (final threshold in widths) {
      if (extent < threshold * scale) break;
      columns++;
    }
  }
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
    required IndexedWidgetBuilder this.itemBuilder,
  }) : positionedBuilder = null;

  const SliverResponsiveCardGrid.withColumns({
    super.key,
    required this.itemCount,
    required Widget Function(BuildContext, int index, int columns)
    this.positionedBuilder,
  }) : itemBuilder = null;

  final int itemCount;
  final IndexedWidgetBuilder? itemBuilder;
  final Widget Function(BuildContext, int index, int columns)?
  positionedBuilder;

  @override
  State<SliverResponsiveCardGrid> createState() =>
      _SliverResponsiveCardGridState();
}

final class _SliverResponsiveCardGridState
    extends State<SliverResponsiveCardGrid> {
  ({int columns, double width, double spacing, double runSpacing})?
  _previousLayout;
  Object? _previousEnvironment;
  Widget? _rows;

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.systemFonts.addListener(_invalidateMeasurements);
  }

  void _invalidateMeasurements() => setState(() => _rows = null);

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(
      _invalidateMeasurements,
    );
    super.dispose();
  }

  @override
  void didUpdateWidget(SliverResponsiveCardGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount ||
        oldWidget.itemBuilder != widget.itemBuilder ||
        oldWidget.positionedBuilder != widget.positionedBuilder) {
      _rows = null;
    }
  }

  @override
  Widget build(BuildContext context) => TextMeasurementCacheScope(
    child: SliverLayoutBuilder(
      builder: (context, constraints) {
        final layout = _layout(context, constraints.crossAxisExtent);
        // Offscreen rows can depend on typography even when the currently
        // mounted rows do not. Invalidate their sizes on ambient layout changes.
        final environment = (
          Theme.of(context),
          DefaultTextStyle.of(context),
          MediaQuery.textScalerOf(context),
          MediaQuery.boldTextOf(context),
          Localizations.maybeLocaleOf(context),
          Directionality.of(context),
        );
        // Sliver constraints also change on every scroll frame. Reusing the rows
        // keeps a scroll offset change from replacing the delegate and rebuilding
        // all visible cards; cross-axis layout and content changes still update it.
        if (_rows case final rows?
            when layout == _previousLayout &&
                environment == _previousEnvironment) {
          return rows;
        }
        _previousLayout = layout;
        _previousEnvironment = environment;
        return _rows = SliverCachedExtentList(
          delegate: SliverChildBuilderDelegate(
            (context, row) => Padding(
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
                          child:
                              widget.positionedBuilder?.call(
                                context,
                                row * layout.columns + column,
                                layout.columns,
                              ) ??
                              widget.itemBuilder!(
                                context,
                                row * layout.columns + column,
                              ),
                        ),
                      ),
                ],
              ),
            ),
            childCount: (widget.itemCount / layout.columns).ceil(),
          ),
        );
      },
    ),
  );
}
