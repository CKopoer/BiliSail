import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/user.dart';
import '../../../shared/ui/app_network_image.dart';
import '../domain/live_room.dart';
import '../domain/live_chat_content.dart';

class LiveChatBubble extends StatefulWidget {
  const LiveChatBubble({
    super.key,
    required this.message,
    this.onOpenUser,
    this.content,
    this.onSelectContent,
  });
  final LiveChatMessage message;
  final ValueChanged<UserId>? onOpenUser;
  final LiveChatContent? content;
  final VoidCallback? onSelectContent;

  @override
  State<LiveChatBubble> createState() => _LiveChatBubbleState();
}

class _LiveChatBubbleState extends State<LiveChatBubble> {
  late LiveChatContent _content;

  @override
  void initState() {
    super.initState();
    _content = widget.content ?? LiveChatContent(widget.message);
  }

  @override
  void didUpdateWidget(covariant LiveChatBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    final content = widget.content;
    if (content != null) {
      _content = content;
    } else if (!_content.matches(widget.message)) {
      _content = LiveChatContent(widget.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final theme = Theme.of(context);
    final userId = message.userId;
    final open = userId != null && userId.isValid && widget.onOpenUser != null
        ? () => widget.onOpenUser?.call(userId)
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final inlineWidth = math.min(
          180.0,
          math.max(1.0, constraints.maxWidth - 20),
        );
        final name = Text(
          message.userName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: open == null
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.primary,
          ),
        );
        final spans = <InlineSpan>[
          if (message.medal case final medal?)
            _badge(
              context,
              medal.name,
              level: medal.level,
              maxWidth: math.min(140, inlineWidth),
              color: medal.color,
              textColor: medal.textColor,
            ),
          if (message.userLevel case final level? when level > 0)
            _badge(context, 'UL $level', maxWidth: inlineWidth),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: SelectionContainer.disabled(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: inlineWidth),
                child: open == null
                    ? name
                    : Semantics(
                        button: true,
                        child: InkWell(onTap: open, child: name),
                      ),
              ),
            ),
          ),
          const TextSpan(text: ': '),
        ];
        for (final part in _content.parts) {
          final image = part.image;
          spans.add(
            image == null
                ? TextSpan(text: part.text)
                : _image(context, image, part.text, sticker: part.sticker),
          );
        }
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectionArea(
              onSelectionChanged: (selection) {
                if (selection != null && selection.plainText.isNotEmpty) {
                  widget.onSelectContent?.call();
                }
              },
              child: Text.rich(TextSpan(children: spans)),
            ),
          ),
        );
      },
    );
  }

  WidgetSpan _badge(
    BuildContext context,
    String label, {
    required double maxWidth,
    int? level,
    int? color,
    int? textColor,
  }) {
    final colors = Theme.of(context).colorScheme;
    final background = color == null ? colors.secondaryContainer : Color(color);
    final foreground = textColor == null
        ? (ThemeData.estimateBrightnessForColor(background) == Brightness.dark
              ? Colors.white
              : Colors.black87)
        : Color(textColor);
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: SelectionContainer.disabled(
        child: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(4),
              ),
              child: DefaultTextStyle.merge(
                style: TextStyle(fontSize: 11, color: foreground),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        // WidgetSpan already scales the entire inline badge.
                        textScaler: TextScaler.noScaling,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (level != null)
                      Text(
                        ' $level',
                        textScaler: TextScaler.noScaling,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  WidgetSpan _image(
    BuildContext context,
    LiveChatImage image,
    String label, {
    bool sticker = false,
  }) {
    final limit = sticker
        ? 80.0
        : MediaQuery.textScalerOf(context).scale(24).clamp(24.0, 48.0);
    final longest = math.max(1, math.max(image.width, image.height));
    final width = (limit * image.width / longest).clamp(1.0, limit);
    final height = (limit * image.height / longest).clamp(1.0, limit);
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: AppNetworkImage(
        url: image.url.toString(),
        width: width,
        height: height,
        fit: BoxFit.contain,
        cacheWidth: (width * 3).ceil(),
        semanticLabel: label,
        errorBuilder: (_, _, _) => SizedBox(
          width: sticker ? width : null,
          child: Text(
            label,
            maxLines: sticker ? 2 : 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
