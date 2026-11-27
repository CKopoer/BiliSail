/// Official Pegasus entry points. Values are mapped at the API boundary.
enum AppRecommendationLoadReason {
  initial,
  tabClick,
  pullDown,
  refreshButton,
  loadMore,
  identityChanged,
}

final class AppRecommendationRequest {
  const AppRecommendationRequest({
    this.cursor = '0',
    this.reason = AppRecommendationLoadReason.initial,
  });

  /// Server card index anchoring this recommendation batch, never a page number.
  final String cursor;
  final AppRecommendationLoadReason reason;
}
