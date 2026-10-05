import 'package:flutter/material.dart';

class PlaybackSidebarToggle extends StatelessWidget {
  const PlaybackSidebarToggle({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  static const size = Size(36, 56);

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black45,
        fixedSize: size,
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      icon: Icon(icon),
    ),
  );
}
