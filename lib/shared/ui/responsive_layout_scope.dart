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

/// Cards and their grid's row-height cache use the same page preference.
class CardCoverScope extends InheritedWidget {
  const CardCoverScope({super.key, required this.group, required super.child});

  final CardCoverGroup group;

  static CardCoverRatio ratioOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CardCoverScope>();
    return ResponsiveLayoutScope.of(context)
        .cardCoverRatioFor(scope?.group ?? CardCoverGroup.home);
  }

  @override
  bool updateShouldNotify(CardCoverScope oldWidget) => group != oldWidget.group;
}
