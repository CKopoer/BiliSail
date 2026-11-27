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

  PlaybackInfoScope.player({
    super.key,
    required this.showInfo,
    required this.tooltip,
    required this.onToggle,
    required bool wide,
    required Widget player,
  }) : super(
         child: Stack(
           fit: StackFit.expand,
           children: [
             player,
             if (wide)
               Align(
                 alignment: Alignment.centerRight,
                 child: _SidebarEdgeToggle(
                   showInfo: showInfo,
                   onToggle: onToggle,
                 ),
               ),
           ],
         ),
       );

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

class _SidebarEdgeToggle extends StatelessWidget {
  const _SidebarEdgeToggle({required this.showInfo, required this.onToggle});

  final bool showInfo;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Semantics(
    expanded: showInfo,
    child: Material(
      type: MaterialType.transparency,
      child: IconButton(
        tooltip: showInfo ? '收起右侧信息栏' : '展开右侧信息栏',
        onPressed: onToggle,
        style: IconButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.black45,
          fixedSize: const Size(36, 56),
          minimumSize: Size.zero,
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.standard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        icon: Icon(showInfo ? Icons.chevron_right : Icons.chevron_left),
      ),
    ),
  );
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
