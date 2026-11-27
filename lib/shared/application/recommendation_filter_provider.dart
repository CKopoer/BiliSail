import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/recommendation_settings.dart';
import '../../features/settings/application/settings_controller.dart';

final recommendationSettingsProvider = Provider<RecommendationSettings>(
  (ref) =>
      ref.watch(
        settingsControllerProvider.select(
          (value) => value.value?.recommendations,
        ),
      ) ??
      ref.watch(settingsDefaultsProvider).recommendations,
);

final recommendationFilterProvider = Provider<RecommendationFilter>(
  (ref) => RecommendationFilter(ref.watch(recommendationSettingsProvider)),
);
