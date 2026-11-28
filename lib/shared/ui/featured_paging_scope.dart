import 'package:flutter/widgets.dart';

/// The inline surface yields vertical paging to its enclosing featured viewer.
class FeaturedPagingScope extends InheritedWidget {
  const FeaturedPagingScope({
    super.key,
    required this.step,
    required this.hasFocus,
    required super.child,
  });
  final ValueChanged<int> step;
  final bool Function() hasFocus;
  static FeaturedPagingScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FeaturedPagingScope>();
  @override
  bool updateShouldNotify(FeaturedPagingScope oldWidget) =>
      step != oldWidget.step || hasFocus != oldWidget.hasFocus;
}
