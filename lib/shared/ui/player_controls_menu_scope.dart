import 'package:flutter/widgets.dart';

// Lets controls built by the caller share the player's menu visibility guard.
class PlayerControlsMenuScope extends InheritedWidget {
  const PlayerControlsMenuScope({
    super.key,
    required this.onChanged,
    required super.child,
  });

  final ValueChanged<bool> onChanged;

  static ValueChanged<bool>? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<PlayerControlsMenuScope>()
      ?.onChanged;

  @override
  bool updateShouldNotify(PlayerControlsMenuScope oldWidget) =>
      onChanged != oldWidget.onChanged;
}
