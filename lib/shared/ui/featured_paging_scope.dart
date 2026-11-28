import 'package:flutter/widgets.dart';

/// The inline surface yields vertical paging to its enclosing featured viewer.
class FeaturedPagingScope extends InheritedWidget {
  const FeaturedPagingScope({
    super.key,
    required super.child,
    this.onControlsInsetChanged,
  });

  /// Reports the height of the visible inline controls during player layout.
  final ValueChanged<double>? onControlsInsetChanged;

  static FeaturedPagingScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FeaturedPagingScope>();
  @override
  bool updateShouldNotify(FeaturedPagingScope oldWidget) =>
      onControlsInsetChanged != oldWidget.onControlsInsetChanged;
}
