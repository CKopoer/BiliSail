import 'package:material_ui/material_ui.dart';

/// Keeps the information toggle beside the player or in its own strip below it.
class PlaybackPlayerArea extends StatelessWidget {
  const PlaybackPlayerArea({
    super.key,
    required this.player,
    required this.wide,
    required this.showInfo,
    required this.tooltip,
    required this.onToggle,
    this.showStackedToggle = true,
  });

  static const toggleStripHeight = 40.0;

  final Widget player;
  final bool wide;
  final bool showInfo;
  final String tooltip;
  final VoidCallback onToggle;
  final bool showStackedToggle;

  @override
  Widget build(BuildContext context) {
    final toggle = PlaybackSidebarToggle(
      wide: wide,
      showInfo: showInfo,
      tooltip: tooltip,
      onPressed: onToggle,
    );
    return Stack(
      children: [
        Positioned.fill(
          bottom: wide || !showStackedToggle ? 0 : toggleStripHeight,
          child: player,
        ),
        if (wide)
          Align(alignment: Alignment.centerRight, child: toggle)
        else if (showStackedToggle)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: toggleStripHeight,
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: Center(child: toggle),
            ),
          ),
      ],
    );
  }
}

class PlaybackSidebarToggle extends StatelessWidget {
  const PlaybackSidebarToggle({
    super.key,
    required this.tooltip,
    required this.wide,
    required this.showInfo,
    required this.onPressed,
  });

  final String tooltip;
  final bool wide;
  final bool showInfo;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final icon = wide
        ? (showInfo ? Icons.chevron_right : Icons.chevron_left)
        : (showInfo ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up);
    return Material(
      type: MaterialType.transparency,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          foregroundColor: wide ? Colors.white : colors.onSurfaceVariant,
          backgroundColor: wide
              ? Colors.black45
              : colors.surfaceContainerHighest,
          fixedSize: wide ? const Size(36, 56) : const Size(64, 24),
          minimumSize: Size.zero,
          padding: EdgeInsets.zero,
          tapTargetSize: wide
              ? MaterialTapTargetSize.shrinkWrap
              : MaterialTapTargetSize.padded,
          visualDensity: VisualDensity.standard,
          shape: wide
              ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))
              : const StadiumBorder(),
        ),
        icon: Icon(icon, size: wide ? null : 20),
      ),
    );
  }
}
