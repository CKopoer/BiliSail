import 'dart:async';

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
    this.clock,
  });

  final LiveSuperChatMessage message;
  final bool selected;
  final VoidCallback onPressed;
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) => _SuperChatCountdown(
    message: message,
    clock: clock,
    builder: (seconds) => _bubble(seconds),
  );

  Widget _bubble(int? seconds) {
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
                if (seconds != null) ...[
                  const SizedBox(width: 7),
                  Text(
                    '${seconds}s',
                    style: TextStyle(
                      color: palette.bubbleInk.withValues(alpha: 0.8),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Two-tone SC card with the remaining lifetime beside its author and amount.
class LiveSuperChatCard extends StatelessWidget {
  const LiveSuperChatCard({
    super.key,
    required this.message,
    this.onOpenUser,
    this.clock,
  });

  final LiveSuperChatMessage message;
  final VoidCallback? onOpenUser;
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) => _SuperChatCountdown(
    message: message,
    clock: clock,
    builder: (seconds) => _card(context, seconds),
  );

  Widget _card(BuildContext context, int? seconds) {
    final palette = _SuperChatPalette.from(message);
    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.body.withValues(alpha: 0.7)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
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
                      if (seconds != null) ...[
                        const SizedBox(width: 8),
                        Semantics(
                          label: '剩余 $seconds 秒',
                          excludeSemantics: true,
                          child: Text(
                            '${seconds}s',
                            style: TextStyle(
                              color: palette.headerInk.withValues(alpha: 0.8),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
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

/// Tick only this small view; the application controller owns SC removal.
/// TickerMode also stops timers while the sidebar/tab/workspace is hidden.
class _SuperChatCountdown extends StatefulWidget {
  const _SuperChatCountdown({
    required this.message,
    required this.builder,
    this.clock,
  });

  final LiveSuperChatMessage message;
  final Widget Function(int? seconds) builder;
  final DateTime Function()? clock;

  @override
  State<_SuperChatCountdown> createState() => _SuperChatCountdownState();
}

class _SuperChatCountdownState extends State<_SuperChatCountdown> {
  Timer? _timer;
  bool _enabled = false;

  int? get _seconds {
    final end = widget.message.expiresAt;
    if (end == null) return null;
    final remaining = end.difference((widget.clock ?? DateTime.now)());
    return remaining <= Duration.zero
        ? 0
        : (remaining.inMicroseconds + Duration.microsecondsPerSecond - 1) ~/
              Duration.microsecondsPerSecond;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _enabled = TickerMode.valuesOf(context).enabled;
    _schedule();
  }

  @override
  void didUpdateWidget(covariant _SuperChatCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (!_enabled || (_seconds ?? 0) == 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if ((_seconds ?? 0) == 0) {
        _timer?.cancel();
        _timer = null;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_seconds);
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
