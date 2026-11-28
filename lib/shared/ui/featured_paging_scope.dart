import 'package:flutter/widgets.dart';

/// Identifies playback owned by a featured viewer.
class FeaturedPagingScope extends InheritedWidget {
  const FeaturedPagingScope({
    super.key,
    required super.child,
    this.onControlsInsetChanged,
    this.showVideoOverlays = true,
    this.onToggleVideoOverlays,
  });

  /// Reports space to keep above the bottom edge for the inline controls.
  final ValueChanged<double>? onControlsInsetChanged;
  final bool showVideoOverlays;
  final VoidCallback? onToggleVideoOverlays;

  static FeaturedPagingScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FeaturedPagingScope>();
  @override
  bool updateShouldNotify(FeaturedPagingScope oldWidget) =>
      onControlsInsetChanged != oldWidget.onControlsInsetChanged ||
      showVideoOverlays != oldWidget.showVideoOverlays ||
      onToggleVideoOverlays != oldWidget.onToggleVideoOverlays;
}
