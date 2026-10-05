import 'package:flutter/material.dart';

const _spacing = 20.0;
const _runSpacing = 24.0;

({int columns, double width}) _layout(BuildContext context, double extent) {
  final minimum = MediaQuery.textScalerOf(context).scale(300).clamp(300, 450);
  final columns = ((extent + _spacing) / (minimum + _spacing)).floor().clamp(
    1,
    12,
  );
  return (
    columns: columns,
    width: (extent - (columns - 1) * _spacing) / columns,
  );
}

/// Fill the available width with equal cards, including the final partial row.
final class ResponsiveCardGrid extends StatelessWidget {
  const ResponsiveCardGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final layout = _layout(context, constraints.maxWidth);
      return Wrap(
        spacing: _spacing,
        runSpacing: _runSpacing,
        children: [
          for (final child in children)
            SizedBox(width: layout.width, child: child),
        ],
      );
    },
  );
}

/// Lazily build rows with natural heights for cards and enlarged text.
final class SliverResponsiveCardGrid extends StatelessWidget {
  const SliverResponsiveCardGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final layout = _layout(context, constraints.crossAxisExtent);
      return SliverList.builder(
        itemCount: (itemCount / layout.columns).ceil(),
        itemBuilder: (context, row) => Padding(
          padding: const EdgeInsets.only(bottom: _runSpacing),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: _spacing,
            children: [
              for (var column = 0; column < layout.columns; column++)
                if (row * layout.columns + column < itemCount)
                  SizedBox(
                    width: layout.width,
                    child: itemBuilder(context, row * layout.columns + column),
                  ),
            ],
          ),
        ),
      );
    },
  );
}
