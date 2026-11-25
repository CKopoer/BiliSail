import 'video.dart';
import 'recommendation_source.dart';
export 'recommendation_source.dart';

enum RecommendationSurface { recommended, discovery, related }

final class RecommendationSettings {
  RecommendationSettings({
    this.source = RecommendationSource.web,
    this.reportInteractions = false,
    this.keepPrevious = false,
    this.showPreviousMarker = true,
    int minimumLikeRatio = 0,
    int minimumDurationSeconds = 0,
    int minimumPlayCount = 0,
    List<String> titleKeywords = const [],
    List<String> categoryKeywords = const [],
    this.exemptFollowed = true,
    this.filterRelated = true,
  }) : minimumLikeRatio =
           minimumLikeRatio >= 0 && minimumLikeRatio <= maximumLikeRatio
           ? minimumLikeRatio
           : 0,
       minimumDurationSeconds =
           minimumDurationSeconds >= 0 &&
               minimumDurationSeconds <= maximumDurationSeconds
           ? minimumDurationSeconds
           : 0,
       minimumPlayCount =
           minimumPlayCount >= 0 && minimumPlayCount <= maximumPlayCount
           ? minimumPlayCount
           : 0,
       titleKeywords = _keywords(titleKeywords),
       categoryKeywords = _keywords(categoryKeywords);

  const RecommendationSettings.defaults()
    : source = RecommendationSource.web,
      reportInteractions = false,
      keepPrevious = false,
      showPreviousMarker = true,
      minimumLikeRatio = 0,
      minimumDurationSeconds = 0,
      minimumPlayCount = 0,
      titleKeywords = const [],
      categoryKeywords = const [],
      exemptFollowed = true,
      filterRelated = true;

  static const likeRatios = [0, 1, 2, 3, 4];
  static const durations = [0, 30, 60, 90, 120];
  static const playCounts = [0, 50, 100, 500, 1000];
  static const maximumKeywords = 32;
  static const maximumKeywordLength = 64;
  static const maximumLikeRatio = 100;
  static const maximumDurationSeconds = 604800;
  static const maximumPlayCount = 2147483647;

  final bool reportInteractions;
  final bool keepPrevious, showPreviousMarker, exemptFollowed, filterRelated;
  final RecommendationSource source;
  final int minimumLikeRatio, minimumDurationSeconds, minimumPlayCount;
  final List<String> titleKeywords, categoryKeywords;

  Object get filterKey => (
    minimumLikeRatio,
    minimumDurationSeconds,
    minimumPlayCount,
    titleKeywords.join('\u0000'),
    categoryKeywords.join('\u0000'),
    exemptFollowed,
    filterRelated,
  );

  static List<String> _keywords(List<String> input) => List.unmodifiable(
    input
        .take(maximumKeywords)
        .map((word) => word.trim())
        .where(
          (word) =>
              word.isNotEmpty &&
              word.length <= maximumKeywordLength &&
              !word.contains('\u0000'),
        )
        .toSet(),
  );

  factory RecommendationSettings.fromJson(Object? value) {
    if (value is! Map<String, Object?>) {
      return const RecommendationSettings.defaults();
    }
    bool flag(String key, bool fallback) =>
        value[key] is bool ? value[key] as bool : fallback;
    int number(String key) => value[key] is int ? value[key] as int : 0;
    List<String> words(String key) => value[key] is List
        ? (value[key] as List)
              .take(maximumKeywords)
              .whereType<String>()
              .toList()
        : const [];
    return RecommendationSettings(
      source:
          RecommendationSource.values
              .where((item) => item.name == value['source'])
              .firstOrNull ??
          RecommendationSource.web,
      reportInteractions: flag('reportInteractions', false),
      keepPrevious: flag('keepPrevious', false),
      showPreviousMarker: flag('showPreviousMarker', true),
      minimumLikeRatio: number('minimumLikeRatio'),
      minimumDurationSeconds: number('minimumDurationSeconds'),
      minimumPlayCount: number('minimumPlayCount'),
      titleKeywords: words('titleKeywords'),
      categoryKeywords: words('categoryKeywords'),
      exemptFollowed: flag('exemptFollowed', true),
      filterRelated: flag('filterRelated', true),
    );
  }

  Map<String, Object?> toJson() => {
    'source': source.name,
    'reportInteractions': reportInteractions,
    'keepPrevious': keepPrevious,
    'showPreviousMarker': showPreviousMarker,
    'minimumLikeRatio': minimumLikeRatio,
    'minimumDurationSeconds': minimumDurationSeconds,
    'minimumPlayCount': minimumPlayCount,
    'titleKeywords': titleKeywords,
    'categoryKeywords': categoryKeywords,
    'exemptFollowed': exemptFollowed,
    'filterRelated': filterRelated,
  };

  RecommendationSettings copyWith({
    RecommendationSource? source,
    bool? reportInteractions,
    bool? keepPrevious,
    bool? showPreviousMarker,
    int? minimumLikeRatio,
    int? minimumDurationSeconds,
    int? minimumPlayCount,
    List<String>? titleKeywords,
    List<String>? categoryKeywords,
    bool? exemptFollowed,
    bool? filterRelated,
  }) => RecommendationSettings(
    source: source ?? this.source,
    reportInteractions: reportInteractions ?? this.reportInteractions,
    keepPrevious: keepPrevious ?? this.keepPrevious,
    showPreviousMarker: showPreviousMarker ?? this.showPreviousMarker,
    minimumLikeRatio: minimumLikeRatio ?? this.minimumLikeRatio,
    minimumDurationSeconds:
        minimumDurationSeconds ?? this.minimumDurationSeconds,
    minimumPlayCount: minimumPlayCount ?? this.minimumPlayCount,
    titleKeywords: titleKeywords ?? this.titleKeywords,
    categoryKeywords: categoryKeywords ?? this.categoryKeywords,
    exemptFollowed: exemptFollowed ?? this.exemptFollowed,
    filterRelated: filterRelated ?? this.filterRelated,
  );
}

/// Compiled once per preference change; callers filter incoming pages, never
/// scroll frames. Literal terms avoid unbounded user-defined regex execution.
final class RecommendationFilter {
  RecommendationFilter(this.settings)
    : _titles = settings.titleKeywords
          .map((word) => word.toLowerCase())
          .toList(),
      _categories = settings.categoryKeywords
          .map((word) => word.toLowerCase())
          .toList();

  final RecommendationSettings settings;
  final List<String> _titles, _categories;

  bool enabledFor(RecommendationSurface surface) =>
      (surface != RecommendationSurface.related || settings.filterRelated) &&
      (_titles.isNotEmpty ||
          _categories.isNotEmpty ||
          settings.minimumLikeRatio > 0 ||
          settings.minimumPlayCount > 0 ||
          surface != RecommendationSurface.discovery &&
              settings.minimumDurationSeconds > 0);

  bool allows(VideoSummary video, RecommendationSurface surface) {
    if (!enabledFor(surface)) return true;
    if (surface == RecommendationSurface.recommended &&
        settings.exemptFollowed &&
        video.isFollowed == true) {
      return true;
    }
    final play = video.playCount;
    final likes = video.likeCount;
    if (play != null && play >= 0) {
      if (play < settings.minimumPlayCount) return false;
      if (likes != null &&
          likes >= 0 &&
          likes * 100 < settings.minimumLikeRatio * play) {
        return false;
      }
    }
    if (surface != RecommendationSurface.discovery &&
        video.duration > Duration.zero &&
        video.duration.inSeconds < settings.minimumDurationSeconds) {
      return false;
    }
    if (_titles.isNotEmpty) {
      final title = video.title.toLowerCase();
      if (_titles.any(title.contains)) return false;
    }
    final category = video.categoryName;
    if (_categories.isNotEmpty && category != null) {
      final name = category.toLowerCase();
      if (_categories.any(name.contains)) return false;
    }
    return true;
  }
}
