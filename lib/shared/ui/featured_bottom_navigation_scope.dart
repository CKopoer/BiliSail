import 'package:material_ui/material_ui.dart';

import 'playback_sidebar_toggle.dart';

/// Shares the current workspace bottom navigation state with its featured page.
class FeaturedBottomNavigationScope extends InheritedWidget {
  const FeaturedBottomNavigationScope({
    super.key,
    required this.visible,
    required this.onToggle,
    required this.enabled,
    required super.child,
  });

  final bool visible;
  final VoidCallback onToggle;
  final bool enabled;

  static FeaturedBottomNavigationScope? maybeOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<FeaturedBottomNavigationScope>();
    return scope?.enabled == true ? scope : null;
  }

  @override
  bool updateShouldNotify(FeaturedBottomNavigationScope oldWidget) =>
      enabled != oldWidget.enabled ||
      (enabled &&
          (visible != oldWidget.visible || onToggle != oldWidget.onToggle));
}

class FeaturedBottomNavigationToggle extends StatelessWidget {
  const FeaturedBottomNavigationToggle({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final navigation = FeaturedBottomNavigationScope.maybeOf(context);
    if (navigation == null) return const SizedBox.shrink();
    return PlaybackSidebarToggle.controlled(
      color: color,
      expanded: navigation.visible,
      tooltip: navigation.visible ? '收起底栏' : '展开底栏',
      onToggle: navigation.onToggle,
    );
  }
}
