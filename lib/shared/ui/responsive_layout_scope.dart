import 'package:flutter/widgets.dart';

import '../../domain/responsive_layout_settings.dart';

class ResponsiveLayoutScope extends InheritedWidget {
  const ResponsiveLayoutScope({
    super.key,
    required this.settings,
    required super.child,
  });

  final ResponsiveLayoutSettings settings;

  static ResponsiveLayoutSettings of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ResponsiveLayoutScope>()
          ?.settings ??
      const ResponsiveLayoutSettings.defaults();

  @override
  bool updateShouldNotify(ResponsiveLayoutScope oldWidget) =>
      settings != oldWidget.settings;
}
