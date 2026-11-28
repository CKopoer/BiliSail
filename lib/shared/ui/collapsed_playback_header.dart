import 'package:material_ui/material_ui.dart';

import 'playback_navigation.dart';

enum CollapsedPlaybackAction {
  play('立即播放'),
  resume('继续播放'),
  replay('重新播放');

  const CollapsedPlaybackAction(this.label);
  final String label;
}

/// Geometry of the portion of the inline player scrolled above the viewport.
class CollapsedPlaybackHeader extends InheritedWidget {
  const CollapsedPlaybackHeader({
    super.key,
    required this.hiddenHeight,
    required this.opacity,
    required this.action,
    required this.enabled,
    required super.child,
  });

  final double hiddenHeight;
  final double opacity;
  final CollapsedPlaybackAction action;
  final bool enabled;

  static CollapsedPlaybackHeader? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CollapsedPlaybackHeader>();

  @override
  bool updateShouldNotify(CollapsedPlaybackHeader oldWidget) =>
      hiddenHeight != oldWidget.hiddenHeight ||
      opacity != oldWidget.opacity ||
      action != oldWidget.action ||
      enabled != oldWidget.enabled;
}

/// Keeps the surface mounted at its normal size as the toolbar fades in.
class CollapsedPlaybackOverlay extends StatelessWidget {
  const CollapsedPlaybackOverlay({
    super.key,
    required this.onPlay,
    required this.onMore,
    required this.onNavigate,
    required this.child,
  });

  final VoidCallback onPlay, onMore;
  final ValueChanged<VoidCallback> onNavigate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final header = CollapsedPlaybackHeader.maybeOf(context);
    final opacity = header?.opacity ?? 0;
    final interactive = opacity >= .5;
    return Stack(
      fit: StackFit.expand,
      children: [
        _input(enabled: !interactive, child: child),
        if (header != null && opacity > 0)
          Positioned.fill(
            top: header.hiddenHeight,
            child: _input(
              enabled: interactive && header.enabled,
              child: Opacity(
                opacity: opacity,
                child: _toolbar(context, header.action),
              ),
            ),
          ),
      ],
    );
  }

  Widget _input({required bool enabled, required Widget child}) => ExcludeFocus(
    excluding: !enabled,
    child: ExcludeSemantics(
      excluding: !enabled,
      child: IgnorePointer(ignoring: !enabled, child: child),
    ),
  );

  Widget _toolbar(BuildContext context, CollapsedPlaybackAction action) {
    final navigation = PlaybackNavigation.maybeOf(context);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: kToolbarHeight,
          child: NavigationToolbar(
            middleSpacing: 4,
            leading: navigation != null && navigation.showInPlayer
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '返回',
                        onPressed: () => onNavigate(navigation.onBack),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      IconButton(
                        tooltip: '回到主页',
                        onPressed: () => onNavigate(navigation.onHome),
                        icon: const Icon(Icons.home_outlined),
                      ),
                    ],
                  )
                : null,
            middle: TextButton.icon(
              onPressed: onPlay,
              icon: Icon(
                action == CollapsedPlaybackAction.replay
                    ? Icons.replay_rounded
                    : Icons.play_arrow_rounded,
              ),
              label: Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            trailing: IconButton(
              tooltip: '更多播放选项',
              onPressed: onMore,
              icon: const Icon(Icons.more_horiz),
            ),
          ),
        ),
      ),
    );
  }
}
