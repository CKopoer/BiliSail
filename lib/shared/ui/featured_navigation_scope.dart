import 'package:material_ui/material_ui.dart';

import 'playback_sidebar_toggle.dart';

enum FeaturedNavigationPlacement {
  bottom('底栏'),
  sidebar('侧栏');

  const FeaturedNavigationPlacement(this.label);

  final String label;
}

typedef FeaturedNavigation = ({
  FeaturedNavigationPlacement placement,
  bool visible,
  VoidCallback onToggle,
});

/// Shares the current workspace navigation state with its featured root page.
class FeaturedNavigationScope extends InheritedWidget {
  const FeaturedNavigationScope({
    super.key,
    required this.navigation,
    required super.child,
  });

  final FeaturedNavigation? navigation;

  static FeaturedNavigation? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<FeaturedNavigationScope>()
      ?.navigation;

  @override
  bool updateShouldNotify(FeaturedNavigationScope oldWidget) =>
      navigation != oldWidget.navigation;
}

class FeaturedNavigationToggle extends StatelessWidget {
  const FeaturedNavigationToggle({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final navigation = FeaturedNavigationScope.maybeOf(context);
    if (navigation == null) return const SizedBox.shrink();
    return PlaybackSidebarToggle.controlled(
      color: color,
      expanded: navigation.visible,
      tooltip:
          '${navigation.visible ? '收起' : '展开'}${navigation.placement.label}',
      onToggle: navigation.onToggle,
    );
  }
}
