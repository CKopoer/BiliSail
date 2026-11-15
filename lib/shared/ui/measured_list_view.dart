import 'package:flutter/material.dart';

import 'widget_measurement.dart';

/// Keeps scrollbar geometry independent of the currently visible row heights.
/// Only numeric extents survive measurement; interactive rows remain lazy.
class MeasuredListView extends StatefulWidget {
  const MeasuredListView({
    super.key,
    required this.controller,
    required this.storageKey,
    required this.padding,
    required this.identities,
    required this.itemBuilder,
    required this.layoutBuilder,
    required this.findChildIndexCallback,
  });

  final ScrollController controller;
  final Key storageKey;
  final EdgeInsets padding;
  // An identity must change whenever its row's natural height can change.
  final List<Object> identities;
  final IndexedWidgetBuilder itemBuilder, layoutBuilder;
  final ChildIndexGetter findChildIndexCallback;

  @override
  State<MeasuredListView> createState() => _MeasuredListViewState();
}

class _MeasuredListViewState extends State<MeasuredListView> {
  final _heights = <Object, double>{};
  Object? _textLayout;
  double? _width;
  Widget? _list;

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.systemFonts.addListener(_invalidateLayout);
  }

  void _invalidateLayout() => setState(() {
    _heights.clear();
    _list = null;
  });

  @override
  void didUpdateWidget(MeasuredListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _list = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final defaults = DefaultTextStyle.of(context);
    final layout = (
      Theme.of(context),
      MediaQuery.textScalerOf(context),
      MediaQuery.boldTextOf(context),
      Directionality.of(context),
      Localizations.localeOf(context),
      defaults.style,
      defaults.textAlign,
      defaults.softWrap,
      defaults.overflow,
      defaults.maxLines,
      defaults.textWidthBasis,
      defaults.textHeightBehavior,
    );
    if (_textLayout != layout) {
      _textLayout = layout;
      _heights.clear();
      _list = null;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth - widget.padding.horizontal;
      if (_width != width) {
        _width = width;
        _heights.clear();
        _list = null;
      }
      // Composer/keyboard height changes must not replace an otherwise
      // unchanged list or remeasure its loaded comments.
      final cached = _list;
      if (cached != null) return cached;
      final identities = widget.identities.toSet();
      _heights.removeWhere((identity, _) => !identities.contains(identity));
      WidgetMeasurement? measurement;
      final extents = <double>[];
      try {
        for (final (index, identity) in widget.identities.indexed) {
          extents.add(
            _heights.putIfAbsent(identity, () {
              measurement ??= WidgetMeasurement(context, width);
              return measurement!.height(widget.layoutBuilder(context, index));
            }),
          );
        }
      } finally {
        measurement?.dispose();
      }
      return _list = ListView.custom(
        key: widget.storageKey,
        controller: widget.controller,
        padding: widget.padding,
        itemExtentBuilder: (index, _) => extents[index],
        childrenDelegate: _MeasuredDelegate(
          widget.itemBuilder,
          childCount: extents.length,
          findChildIndexCallback: widget.findChildIndexCallback,
          extent: extents.fold(0, (sum, height) => sum + height),
        ),
      );
    },
  );

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_invalidateLayout);
    super.dispose();
  }
}

class _MeasuredDelegate extends SliverChildBuilderDelegate {
  _MeasuredDelegate(
    super.builder, {
    required super.childCount,
    required super.findChildIndexCallback,
    required this.extent,
  });

  final double extent;

  // A varied-extent sliver also defaults to a visible-row average unless its
  // delegate supplies the measured total.
  @override
  double estimateMaxScrollOffset(
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) => extent;
}
