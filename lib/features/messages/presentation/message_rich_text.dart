import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'private_message_image.dart';

/// Unknown emote tokens retain their text; only validated HTTP links are active.
class MessageRichText extends StatefulWidget {
  const MessageRichText({
    super.key,
    required this.text,
    this.emotes = const {},
    this.onOpenTarget,
    this.maxLines,
    this.style,
  });
  final String text;
  final Map<String, Uri> emotes;
  final ValueChanged<Uri>? onOpenTarget;
  final int? maxLines;
  final TextStyle? style;

  @override
  State<MessageRichText> createState() => _MessageRichTextState();
}

class _MessageRichTextState extends State<MessageRichText> {
  final _recognizers = <TapGestureRecognizer>[];
  static final _tokens = RegExp(r'https?://[^\s<>]+|\[[^\]\r\n]{1,64}\]');

  void _release() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _release();
    final spans = <InlineSpan>[];
    var end = 0;
    for (final match in _tokens.allMatches(widget.text)) {
      if (match.start > end) {
        spans.add(TextSpan(text: widget.text.substring(end, match.start)));
      }
      final token = match.group(0) ?? '';
      final emote = widget.emotes[token];
      if (emote != null) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Tooltip(
              message: token,
              child: PrivateMessageImage(
                url: emote,
                preview: false,
                compact: true,
                label: token,
                fallbackText: token,
              ),
            ),
          ),
        );
      } else {
        final target = Uri.tryParse(token);
        final host = target?.host.toLowerCase() ?? '';
        final trusted =
            host == 'bilibili.com' ||
            host.endsWith('.bilibili.com') ||
            host == 'b23.tv';
        final linked =
            trusted &&
            widget.onOpenTarget != null &&
            target != null &&
            target.host.isNotEmpty &&
            target.userInfo.isEmpty &&
            (target.scheme == 'http' || target.scheme == 'https');
        if (linked) {
          final recognizer = TapGestureRecognizer()
            ..onTap = () =>
                widget.onOpenTarget?.call(target.replace(scheme: 'https'));
          _recognizers.add(recognizer);
          spans.add(
            TextSpan(
              text: token,
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
              recognizer: recognizer,
            ),
          );
        } else {
          spans.add(TextSpan(text: token));
        }
      }
      end = match.end;
    }
    if (end < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(end)));
    }
    final span = TextSpan(children: spans, style: widget.style);
    if (widget.maxLines != null) {
      return Text.rich(
        span,
        maxLines: widget.maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }
    return SelectableText.rich(span);
  }
}
