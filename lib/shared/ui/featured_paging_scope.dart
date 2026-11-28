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

  /// Reports the inline controls' layout height, including while hidden.
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
