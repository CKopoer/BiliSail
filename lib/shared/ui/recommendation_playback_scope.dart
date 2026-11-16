import 'package:flutter/widgets.dart';

import '../../domain/recommendation_playback_context.dart';

final class RecommendationPlaybackScope extends InheritedWidget {
  const RecommendationPlaybackScope({
    super.key,
    required this.value,
    required super.child,
  });
  final RecommendationPlaybackContext? value;
  static RecommendationPlaybackContext? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<RecommendationPlaybackScope>()
      ?.value;
  @override
  bool updateShouldNotify(RecommendationPlaybackScope oldWidget) =>
      value != oldWidget.value;
}
