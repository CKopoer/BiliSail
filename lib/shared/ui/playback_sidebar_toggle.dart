import 'package:material_ui/material_ui.dart';

/// The playback page owns the panel state, including manual overrides.
class PlaybackInfoScope extends InheritedWidget {
  const PlaybackInfoScope({
    super.key,
    required this.showInfo,
    required this.tooltip,
    required this.onToggle,
    required super.child,
  });

  final bool showInfo;
  final String tooltip;
  final VoidCallback onToggle;

  static PlaybackInfoScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlaybackInfoScope>();

  static PlaybackInfoScope? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PlaybackInfoScope>();

  @override
  bool updateShouldNotify(PlaybackInfoScope oldWidget) =>
      showInfo != oldWidget.showInfo ||
      tooltip != oldWidget.tooltip ||
      onToggle != oldWidget.onToggle;
}

class PlaybackSidebarToggle extends StatelessWidget {
  const PlaybackSidebarToggle({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final info = PlaybackInfoScope.maybeOf(context);
    if (info == null) return const SizedBox.shrink();
    return Semantics(
      expanded: info.showInfo,
      child: IconButton(
        color: color,
        tooltip: info.tooltip,
        onPressed: info.onToggle,
        icon: Icon(
          info.showInfo
              ? Icons.zoom_out_map_rounded
              : Icons.zoom_in_map_rounded,
          size: 20,
        ),
      ),
    );
  }
}

/// Offline rooms and unavailable episodes have no playback toolbar.
class PlaybackInfoPlaceholder extends StatelessWidget {
  const PlaybackInfoPlaceholder({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      child,
      const Align(
        alignment: Alignment.bottomRight,
        child: Material(
          color: Colors.black54,
          child: PlaybackSidebarToggle(color: Colors.white),
        ),
      ),
    ],
  );
}
