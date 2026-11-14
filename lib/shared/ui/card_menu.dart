import 'package:flutter/material.dart';

import 'video_card_menu_sheet.dart';

/// Shared compact action button without the default 48px title-row footprint.
class CardMenuButton extends StatelessWidget {
  const CardMenuButton({
    super.key,
    required this.anchorKey,
    required this.buttonKey,
    required this.cardWidth,
    required this.visible,
    required this.busy,
    required this.onFocusChange,
    required this.onPressed,
    this.tooltip,
  });

  final GlobalKey anchorKey;
  final Key buttonKey;
  final double cardWidth;
  final bool visible, busy;
  final ValueChanged<bool> onFocusChange;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final (buttonSize, iconSize) = switch (cardWidth) {
      < 180 => (20.0, 14.0),
      < 240 => (24.0, 17.0),
      _ => (28.0, 20.0),
    };
    final size = Size.square(buttonSize);
    return Focus(
      skipTraversal: true,
      onFocusChange: onFocusChange,
      child: Opacity(
        opacity: visible ? 1 : 0,
        child: IgnorePointer(
          ignoring: !visible,
          child: GestureDetector(
            key: anchorKey,
            // Disabled nested actions still consume taps inside the card.
            onTap: () {},
            excludeFromSemantics: true,
            child: IconButton(
              key: buttonKey,
              onPressed: onPressed,
              tooltip: tooltip,
              icon: busy
                  ? SizedBox.square(
                      dimension: iconSize * .8,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: '操作中',
                      ),
                    )
                  : Icon(
                      Icons.more_vert,
                      size: iconSize,
                      semanticLabel: '更多操作',
                    ),
              iconSize: iconSize,
              style: IconButton.styleFrom(
                minimumSize: size,
                maximumSize: size,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.standard,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<T?> showCardMenu<T>(
  BuildContext context, {
  required GlobalKey anchorKey,
  required List<({T value, IconData icon, String label})> actions,
}) async {
  if (MediaQuery.sizeOf(context).width < 600) {
    return showVideoCardMenuSheet(context, actions);
  }
  final overlay = Navigator.of(context).overlay;
  final anchor = anchorKey.currentContext?.findRenderObject();
  if (overlay == null || anchor is! RenderBox) return null;
  final overlayBox = overlay.context.findRenderObject() as RenderBox;
  RelativeRect position() => RelativeRect.fromRect(
    Rect.fromPoints(
      anchor.localToGlobal(Offset(0, anchor.size.height), ancestor: overlayBox),
      anchor.localToGlobal(
        anchor.size.bottomRight(Offset.zero),
        ancestor: overlayBox,
      ),
    ),
    Offset.zero & overlayBox.size,
  );
  final initialPosition = position();
  return showMenu<T>(
    context: context,
    positionBuilder: (_, _) => anchor.attached ? position() : initialPosition,
    constraints: const BoxConstraints(minWidth: 156, maxWidth: 240),
    color: Theme.of(context).colorScheme.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 3,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(
        color: Theme.of(context).colorScheme.outlineVariant
            .withValues(alpha: .6),
      ),
    ),
    items: [
      for (final action in actions)
        PopupMenuItem<T>(
          value: action.value,
          child: Row(
            children: [
              Icon(action.icon, size: 19),
              const SizedBox(width: 10),
              Flexible(child: Text(action.label)),
            ],
          ),
        ),
    ],
  );
}
