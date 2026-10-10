import 'package:flutter/material.dart';

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
        // Measure the same spans and available width as the rendered title,
        // including space reserved by the card's menu button.
        final painter = TextPainter(
          text: TextSpan(
            style: effectiveStyle,
            text: child.data,
            children: [?child.textSpan],
          ),
          textAlign: defaults.textAlign ?? TextAlign.start,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
          maxLines: maxLines,
          ellipsis: '\u2026',
          textWidthBasis: defaults.textWidthBasis,
          textHeightBehavior: defaults.textHeightBehavior,
        )..layout(maxWidth: constraints.maxWidth);
        final overflowing = painter.didExceedMaxLines;
        painter.dispose();
        return Tooltip(
          message: overflowing ? text : '',
          excludeFromSemantics: true,
          triggerMode: TooltipTriggerMode.manual,
          child: child,
        );
      },
    );
  }
}
