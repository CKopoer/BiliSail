import 'package:flutter/widgets.dart';

/// The inline surface yields vertical paging to its enclosing featured viewer.
class FeaturedPagingScope extends InheritedWidget {
  const FeaturedPagingScope({super.key, required super.child});
  static FeaturedPagingScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FeaturedPagingScope>();
  @override
  bool updateShouldNotify(FeaturedPagingScope oldWidget) => false;
}
