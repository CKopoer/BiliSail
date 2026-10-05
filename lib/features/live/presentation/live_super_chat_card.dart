import 'package:flutter/material.dart';

import '../../../shared/ui/network_avatar.dart';
import '../domain/live_room.dart';

/// Live SC amounts are yuan from the API, rather than an inferred coin balance.
class LiveSuperChatBubble extends StatelessWidget {
  const LiveSuperChatBubble({
    super.key,
    required this.message,
    required this.selected,
    required this.onPressed,
  });

  final LiveSuperChatMessage message;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = _SuperChatPalette.from(message);
    return Semantics(
      button: true,
      selected: selected,
      label: '${message.userName}，醒目留言 ${message.price} 元',
      child: Material(
        color: palette.bubble,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? palette.body : Colors.transparent,
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(3, 3, 13, 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                NetworkAvatar(
                  url: message.avatarUrl,
                  name: message.userName,
                  radius: 15,
                ),
                const SizedBox(width: 6),
                Text(
                  '¥${message.price}',
                  style: TextStyle(
                    color: palette.bubbleInk,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact, two-tone card matching the official desktop SC hierarchy.
class LiveSuperChatCard extends StatelessWidget {
  const LiveSuperChatCard({super.key, required this.message, this.onOpenUser});

  final LiveSuperChatMessage message;
  final VoidCallback? onOpenUser;

  @override
  Widget build(BuildContext context) {
    final palette = _SuperChatPalette.from(message);
    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: palette.body.withValues(alpha: 0.7)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ColoredBox(
                color: palette.header,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: palette.body.withValues(alpha: 0.7),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: NetworkAvatar(
                            url: message.avatarUrl,
                            name: message.userName,
                            radius: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              onTap: onOpenUser,
                              child: Text(
                                message.userName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.headerInk.withValues(
                                    alpha: 0.75,
                                  ),
                                  fontSize: 12,
                                  decoration: onOpenUser == null
                                      ? null
                                      : TextDecoration.underline,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '¥${message.price}',
                              style: TextStyle(
                                color: palette.headerInk,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.diamond_outlined,
                        color: palette.body,
                        size: 28,
                      ),
                    ],
                  ),
                ),
              ),
              ColoredBox(
                color: palette.body,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      color: palette.bodyInk,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _SuperChatPalette {
  const _SuperChatPalette(this.header, this.body, this.bodyInk);

  factory _SuperChatPalette.from(LiveSuperChatMessage message) {
    final fallback = switch (message.price) {
      >= 2000 => const Color(0xffc44458),
      >= 1000 => const Color(0xffd55b89),
      >= 500 => const Color(0xffdd903b),
      >= 100 => const Color(0xffcda334),
      >= 50 => const Color(0xff4eaf9e),
      _ => const Color(0xff459fcb),
    };
    final body = message.backgroundBottomColor == null
        ? fallback
        : Color(message.backgroundBottomColor!).withValues(alpha: 1);
    final header = message.backgroundColor == null
        ? Color.lerp(Colors.white, body, 0.2)!
        : Color(message.backgroundColor!).withValues(alpha: 1);
    final suppliedInk = message.textColor == null
        ? null
        : Color(message.textColor!).withValues(alpha: 1);
    // Some snapshots carry a header font color; validate it against the body.
    final bodyInk = suppliedInk != null && _contrast(body, suppliedInk) >= 4.5
        ? suppliedInk
        : _readableInk(body);
    return _SuperChatPalette(header, body, bodyInk);
  }

  final Color header, body, bodyInk;
  Color get headerInk => _readableInk(header);
  Color get bubble => Color.lerp(body, Colors.black, 0.4)!;
  Color get bubbleInk => _readableInk(bubble);

  static Color _readableInk(Color background) =>
      _contrast(background, Colors.white) >= _contrast(background, Colors.black)
      ? Colors.white
      : const Color(0xff252525);

  static double _contrast(Color a, Color b) {
    final first = a.computeLuminance(), second = b.computeLuminance();
    final lighter = first > second ? first : second;
    final darker = first > second ? second : first;
    return (lighter + 0.05) / (darker + 0.05);
  }
}
