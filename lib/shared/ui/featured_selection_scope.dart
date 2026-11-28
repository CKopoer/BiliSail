import 'package:flutter/widgets.dart';

/// Only clicks on a primary navigation destination advance this revision.
class FeaturedSelectionScope extends InheritedNotifier<ValueNotifier<int>> {
  const FeaturedSelectionScope({
    super.key,
    required super.notifier,
    required super.child,
  });

  static int? revisionOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<FeaturedSelectionScope>()
      ?.notifier
      ?.value;
}
