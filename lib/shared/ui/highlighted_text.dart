import 'package:flutter/material.dart';

import 'text_measurement_cache.dart';

final class HighlightedText extends StatelessWidget {
  const HighlightedText(
    this.text, {
    super.key,
    required this.query,
    this.style,
    this.maxLines = 1,
    this.showOverflowTooltip = false,
  });

  final String text, query;
  final TextStyle? style;
  final int maxLines;
  final bool showOverflowTooltip;

  @override
  Widget build(BuildContext context) {
    final needle = query.trim();
    if (needle.isEmpty) {
      return _withOverflowTooltip(
        context,
        Text(
          text,
          style: style,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    final spans = <TextSpan>[];
    var offset = 0;
    for (final match in RegExp(
      RegExp.escape(needle),
      caseSensitive: false,
    ).allMatches(text)) {
      if (match.start > offset) {
        spans.add(TextSpan(text: text.substring(offset, match.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
      );
      offset = match.end;
    }
    if (offset < text.length) spans.add(TextSpan(text: text.substring(offset)));
    return _withOverflowTooltip(
      context,
      Text.rich(
        TextSpan(children: spans),
        style: style ?? Theme.of(context).textTheme.bodyMedium,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _withOverflowTooltip(BuildContext context, Text child) {
    if (!showOverflowTooltip) return child;
    return _OverflowTooltip(text: text, maxLines: maxLines, child: child);
  }
}

typedef _OverflowInputs = ({
  double maxWidth,
  TextAlign align,
  TextDirection direction,
  TextScaler scaler,
  Locale? locale,
  int maxLines,
  TextWidthBasis widthBasis,
  TextHeightBehavior? heightBehavior,
});

final class _OverflowTooltip extends StatefulWidget {
  const _OverflowTooltip({
    required this.text,
    required this.maxLines,
    required this.child,
  });

  final String text;
  final int maxLines;
  final Text child;

  @override
  State<_OverflowTooltip> createState() => _OverflowTooltipState();
}

final class _OverflowTooltipState extends State<_OverflowTooltip> {
  _OverflowInputs? _inputs;
  TextSpan? _measuredText;
  bool _overflowing = false;

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
  }

  void _fontsChanged() => setState(() => _inputs = null);

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_fontsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final measurements = TextMeasurementCacheScope.maybeOf(context);
    final defaults = DefaultTextStyle.of(context);
    final childStyle = child.style;
    var effectiveStyle = childStyle == null || childStyle.inherit
        ? defaults.style.merge(childStyle)
        : childStyle;
    if (MediaQuery.boldTextOf(context)) {
      effectiveStyle = effectiveStyle.merge(
        const TextStyle(fontWeight: FontWeight.bold),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final inputs = (
          maxWidth: constraints.maxWidth,
          align: defaults.textAlign ?? TextAlign.start,
          direction: Directionality.of(context),
          scaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
          maxLines: widget.maxLines,
          widthBasis: defaults.textWidthBasis,
          heightBehavior: defaults.textHeightBehavior,
        );
        final span = TextSpan(
          style: effectiveStyle,
          text: child.data,
          children: [?child.textSpan],
        );
        // One result per mounted title. Flutter's span comparison distinguishes
        // paint-only hover/highlight colors from changes that affect layout.
        if (_inputs != inputs ||
            _measuredText?.compareTo(span) == RenderComparison.layout) {
          bool measure() {
            final painter = TextPainter(
              text: span,
              textAlign: inputs.align,
              textDirection: inputs.direction,
              textScaler: inputs.scaler,
              locale: inputs.locale,
              maxLines: inputs.maxLines,
              ellipsis: '\u2026',
              textWidthBasis: inputs.widthBasis,
              textHeightBehavior: inputs.heightBehavior,
            );
            try {
              painter.layout(maxWidth: inputs.maxWidth);
              return painter.didExceedMaxLines;
            } finally {
              painter.dispose();
            }
          }

          _overflowing =
              measurements?.overflows((inputs, span), measure) ?? measure();
          _inputs = inputs;
          _measuredText = span;
        }
        return Tooltip(
          message: _overflowing ? widget.text : '',
          excludeFromSemantics: true,
          triggerMode: TooltipTriggerMode.longPress,
          child: child,
        );
      },
    );
  }
}
