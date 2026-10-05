import 'package:flutter/widgets.dart';

/// Visibility and playback ownership are independent of page lifetime.
class WorkspaceActivity extends InheritedWidget {
  const WorkspaceActivity({
    super.key,
    required this.active,
    required super.child,
  });

  final bool active;

  static bool isActive(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceActivity>()?.active ??
      true;

  @override
  bool updateShouldNotify(WorkspaceActivity oldWidget) =>
      active != oldWidget.active;
}
