import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Platform chrome is injected by the app, keeping the workspace testable.
final class DesktopWindowControls extends StatelessWidget {
  const DesktopWindowControls({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 138,
    child: WindowCaption(
      brightness: Theme.of(context).brightness,
      backgroundColor: Colors.transparent,
    ),
  );
}

final class DesktopDragRegion extends StatelessWidget {
  const DesktopDragRegion({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DragToMoveArea(child: child);
}
