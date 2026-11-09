import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../../domain/dynamic_post.dart';
import '../../domain/user.dart';
import '../../features/dynamic/domain/dynamic_link.dart';
import 'app_network_image.dart';

/// Expansion belongs to the retained list, rather than to an evictable row.
class DynamicPostExpansionState {
  final _expanded = <String>{};

  bool isExpanded(String id) => _expanded.contains(id);

  void setExpanded(String id, bool expanded) {
    if (expanded) {
      _expanded.add(id);
    } else {
      _expanded.remove(id);
    }
  }

  void retain(Set<String> ids) =>
      _expanded.removeWhere((id) => !ids.contains(id));
}

class DynamicPostText extends StatefulWidget {
  const DynamicPostText({
    super.key,
    required this.post,
    this.onOpenUser,
    this.onOpenLink,
    this.layoutOnly = false,
    this.expansionState,
    this.inDetail = false,
  });
  final DynamicPost post;
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<Uri>? onOpenLink;
  final bool layoutOnly, inDetail;
  final DynamicPostExpansionState? expansionState;
  @override
  State<DynamicPostText> createState() => _DynamicPostTextState();
}

class _DynamicPostTextState extends State<DynamicPostText> {
  bool _locallyExpanded = false;
  bool get _expanded =>
      widget.inDetail ||
      (widget.expansionState?.isExpanded(widget.post.id) ?? _locallyExpanded);
  final _recognizers = <TapGestureRecognizer>[];
  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  void didUpdateWidget(DynamicPostText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id) _locallyExpanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(fontSize: 15, height: 22 / 15);
    _disposeRecognizers();
    final parts = widget.post.spans;
    var remaining = 32768;
    final placeholders = <PlaceholderDimensions>[];
    final children = <InlineSpan>[];
    for (final part in parts.take(256)) {
      if (remaining <= 0) break;
      final text = part.text.length > remaining
          ? '${part.text.substring(0, remaining)}…'
          : part.text;
      remaining -= part.text.length;
      final image = part.imageUrl;
      final link = part.kind == DynamicTextKind.topic
          ? dynamicTopicDestination(name: part.text, url: part.linkUrl)
          : part.linkUrl;
      if (part.kind == DynamicTextKind.emoji &&
          image != null &&
          ['http', 'https'].contains(image.scheme)) {
        final size =
            MediaQuery.textScalerOf(context).scale(24) *
            part.emojiSize.clamp(1, 2);
        placeholders.add(
          PlaceholderDimensions(
            size: Size.square(size),
            alignment: PlaceholderAlignment.middle,
          ),
        );
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Semantics(
              label: part.text,
              image: true,
              child: SizedBox.square(
                dimension: size,
                child: widget.layoutOnly
                    ? const SizedBox.expand()
                    : AppNetworkImage(
                        url: image.toString(),
                        width: size,
                        height: size,
                        cacheWidth: (size * 3).ceil(),
                        errorBuilder: (_, _, _) =>
                            Text(part.text, style: style),
                      ),
              ),
            ),
          ),
        );
      } else if ((part.userId != null && widget.onOpenUser != null) ||
          (link != null && widget.onOpenLink != null)) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () {
            final userId = part.userId;
            if (userId != null && widget.onOpenUser != null) {
              widget.onOpenUser!(userId);
            } else if (link != null) {
              widget.onOpenLink?.call(link);
            }
          };
        _recognizers.add(recognizer);
        children.add(
          TextSpan(
            text: text,
            recognizer: recognizer,
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
        );
      } else {
        children.add(
          TextSpan(
            text: text,
            style: part.kind == DynamicTextKind.plain
                ? null
                : TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
        );
      }
    }
    final plain = widget.post.text;
    final defaults = DefaultTextStyle.of(context);
    final effectiveStyle = defaults.style.merge(style);
    final span = TextSpan(
      style: effectiveStyle,
      children: parts.isEmpty
          ? [
              TextSpan(
                text: plain.length > remaining
                    ? '${plain.substring(0, remaining)}…'
                    : plain,
              ),
            ]
          : children,
    );
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);
    final align = defaults.textAlign ?? TextAlign.start;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use the same font, width, scale and emoji slots as the rendered text.
        // Character counts and explicit newlines cannot tell whether it is clipped.
        final painter = TextPainter(
          text: span,
          textDirection: direction,
          textAlign: align,
          textScaler: scaler,
          locale: locale,
          maxLines: 6,
          ellipsis: '…',
          textWidthBasis: defaults.textWidthBasis,
          textHeightBehavior: defaults.textHeightBehavior,
        );
        painter.setPlaceholderDimensions(placeholders);
        painter.layout(maxWidth: constraints.maxWidth);
        final canExpand = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              span,
              style: effectiveStyle,
              textAlign: align,
              textDirection: direction,
              textScaler: scaler,
              locale: locale,
              textWidthBasis: defaults.textWidthBasis,
              textHeightBehavior: defaults.textHeightBehavior,
              maxLines: canExpand && !_expanded ? 6 : null,
              softWrap: true,
              overflow: canExpand && !_expanded
                  ? TextOverflow.ellipsis
                  : TextOverflow.clip,
            ),
            if (canExpand && !widget.inDetail)
              TextButton(
                onPressed: () => setState(() {
                  final expanded = !_expanded;
                  widget.expansionState?.setExpanded(widget.post.id, expanded);
                  _locallyExpanded = expanded;
                }),
                child: Text(_expanded ? '收起' : '展开全文'),
              ),
          ],
        );
      },
    );
  }
}
