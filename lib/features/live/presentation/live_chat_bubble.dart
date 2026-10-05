import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/user.dart';
import '../../../shared/ui/app_network_image.dart';
import '../domain/live_room.dart';

class LiveChatBubble extends StatelessWidget {
  const LiveChatBubble({super.key, required this.message, this.onOpenUser});
  final LiveChatMessage message;
  final ValueChanged<UserId>? onOpenUser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userId = message.userId;
    final open = userId != null && userId.isValid && onOpenUser != null
        ? () => onOpenUser?.call(userId)
        : null;
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
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: open == null
              ? name
              : Semantics(
                  button: true,
                  child: InkWell(onTap: open, child: name),
                ),
        ),
      ),
      const TextSpan(text: ': '),
    ];
    final sticker = message.sticker;
    if (sticker != null) {
      spans.add(_image(context, sticker, message.text, sticker: true));
    } else {
      final tokens =
          message.emotes.keys.where((token) => token.isNotEmpty).toList()
            ..sort((a, b) => b.length.compareTo(a.length));
      var cursor = 0;
      while (cursor < message.text.length) {
        String? token;
        var position = message.text.length;
        for (final candidate in tokens) {
          final at = message.text.indexOf(candidate, cursor);
          if (at >= 0 && at < position) {
            token = candidate;
            position = at;
          }
        }
        if (token == null) {
          spans.add(TextSpan(text: message.text.substring(cursor)));
          break;
        }
        if (position > cursor) {
          spans.add(TextSpan(text: message.text.substring(cursor, position)));
        }
        final image = message.emotes[token];
        if (image != null) spans.add(_image(context, image, token));
        cursor = position + token.length;
      }
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
        child: Text.rich(TextSpan(children: spans)),
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
