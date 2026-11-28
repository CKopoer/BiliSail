import 'package:bilisail/domain/recommendation_settings.dart';
import 'package:bilisail/domain/video.dart';
import 'package:flutter_test/flutter_test.dart';

VideoSummary _video({
  String title = 'video',
  int? plays,
  int? likes,
  int seconds = 60,
  String? category,
  bool? followed,
}) => VideoSummary(
  id: const VideoId('sample'),
  title: title,
  coverUrl: '',
  author: '',
  duration: Duration(seconds: seconds),
  playCount: plays,
  likeCount: likes,
  categoryName: category,
  isFollowed: followed,
);

void main() {
  test('featured source survives saving independently of home source', () {
    for (final source in FeaturedSource.values) {
      final settings = RecommendationSettings(source: RecommendationSource.web)
          .copyWith(featuredSource: source);
      final loaded = RecommendationSettings.fromJson(settings.toJson());
      expect(loaded.featuredSource, source);
      expect(loaded.source, RecommendationSource.web);
    }
    for (final json in <Map<String, Object?>>[
      {},
      {'featuredSource': 'obsolete'},
    ]) {
      expect(
        RecommendationSettings.fromJson(json).featuredSource,
        FeaturedSource.automatic,
      );
    }
  });
  test('Story cards use the feed by default and preserve a saved opt-out', () {
    expect(
      const RecommendationSettings.defaults().openStoryCardsInFeed,
      isTrue,
    );
    expect(RecommendationSettings.fromJson({}).openStoryCardsInFeed, isTrue);
    expect(
      RecommendationSettings.fromJson({'openStoryCardsInFeed': 'false'})
          .openStoryCardsInFeed,
      isTrue,
    );
    final saved = RecommendationSettings().copyWith(
      openStoryCardsInFeed: false,
    );
    expect(
      RecommendationSettings.fromJson(saved.toJson()).openStoryCardsInFeed,
      isFalse,
    );
    expect(saved.filterKey, RecommendationSettings().filterKey);
  });
  test('custom thresholds persist and enforce numeric limits', () {
    final custom = RecommendationSettings(
      minimumLikeRatio: 7,
      minimumDurationSeconds: 45,
      minimumPlayCount: 2333,
    );
    final restored = RecommendationSettings.fromJson(custom.toJson());
    expect(restored.minimumLikeRatio, 7);
    expect(restored.minimumDurationSeconds, 45);
    expect(restored.minimumPlayCount, 2333);
    expect(RecommendationSettings(minimumLikeRatio: 101).minimumLikeRatio, 0);
    expect(
      RecommendationSettings(minimumDurationSeconds: -1).minimumDurationSeconds,
      0,
    );
    expect(
      RecommendationSettings(minimumPlayCount: 2147483648).minimumPlayCount,
      0,
    );
  });
  test('defaults preserve existing refresh and unfiltered lists', () {
    final settings = const RecommendationSettings.defaults();
    expect(settings.keepPrevious, isFalse);
    final filter = RecommendationFilter(settings);
    for (final surface in RecommendationSurface.values) {
      expect(filter.enabledFor(surface), isFalse);
      expect(filter.allows(_video(), surface), isTrue);
    }
  });

  test('numeric boundaries and unknown/negative metadata are distinct', () {
    final filter = RecommendationFilter(
      RecommendationSettings(
        minimumPlayCount: 100,
        minimumLikeRatio: 2,
        minimumDurationSeconds: 60,
      ),
    );
    bool allows(VideoSummary video) =>
        filter.allows(video, RecommendationSurface.recommended);
    expect(allows(_video(plays: 100, likes: 2)), isTrue);
    expect(allows(_video(plays: 100, likes: 1)), isFalse);
    expect(allows(_video(plays: 99, likes: 10)), isFalse);
    expect(allows(_video(seconds: 59)), isFalse);
    expect(allows(_video(seconds: 0)), isTrue);
    expect(allows(_video(plays: -1, likes: -1, seconds: -1)), isTrue);
    expect(allows(_video()), isTrue);
    expect(
      filter.allows(_video(seconds: 1), RecommendationSurface.discovery),
      isTrue,
    );
  });

  test('followed exemption is limited to confirmed home recommendations', () {
    final settings = RecommendationSettings(titleKeywords: ['blocked']);
    final filter = RecommendationFilter(settings);
    final followed = _video(title: 'blocked', followed: true);
    expect(filter.allows(followed, RecommendationSurface.recommended), isTrue);
    expect(filter.allows(followed, RecommendationSurface.discovery), isFalse);
    expect(filter.allows(followed, RecommendationSurface.related), isFalse);
    expect(
      filter.allows(
        _video(title: 'blocked'),
        RecommendationSurface.recommended,
      ),
      isFalse,
    );
    expect(
      RecommendationFilter(settings.copyWith(exemptFollowed: false))
          .allows(followed, RecommendationSurface.recommended),
      isFalse,
    );
  });

  test(
    'keywords are literal, ignore case, and use available category names',
    () {
      final filter = RecommendationFilter(
        RecommendationSettings(
          titleKeywords: [r'(a+)+$', 'SPAM'],
          categoryKeywords: ['游戏'],
        ),
      );
      bool allows(VideoSummary video) =>
          filter.allows(video, RecommendationSurface.recommended);
      expect(allows(_video(title: 'a' * 10000)), isTrue);
      expect(allows(_video(title: r'prefix (a+)+$')), isFalse);
      expect(allows(_video(title: 'spam title')), isFalse);
      expect(allows(_video(category: '网络游戏')), isFalse);
      expect(allows(_video(category: null)), isTrue);
    },
  );

  test('related opt-out leaves all results intact', () {
    final filter = RecommendationFilter(
      RecommendationSettings(
        filterRelated: false,
        titleKeywords: ['video'],
        minimumPlayCount: 1000,
      ),
    );
    expect(filter.enabledFor(RecommendationSurface.related), isFalse);
    expect(
      filter.allows(_video(plays: 1), RecommendationSurface.related),
      isTrue,
    );
    expect(
      filter.allows(_video(plays: 1), RecommendationSurface.recommended),
      isFalse,
    );
  });

  test('malformed snapshots fall back by field; keyword collections are bounded and immutable', () {
    for (final value in [
      null,
      'invalid',
      [],
      {'minimumLikeRatio': 500, 'minimumPlayCount': -1, 'keepPrevious': 'true'},
    ]) {
      final settings = RecommendationSettings.fromJson(value);
      expect(settings.keepPrevious, isFalse);
      expect(settings.minimumLikeRatio, 0);
      expect(settings.minimumPlayCount, 0);
    }
    final input = [
      ' trim ',
      '',
      'trim',
      'x' * 65,
      ...List.generate(80, (index) => 'word$index'),
    ];
    final settings = RecommendationSettings(titleKeywords: input);
    input.clear();
    expect(settings.titleKeywords.first, 'trim');
    expect(settings.titleKeywords.length, lessThanOrEqualTo(32));
    expect(settings.titleKeywords.any((word) => word.length > 64), isFalse);
    expect(() => settings.titleKeywords.clear(), throwsUnsupportedError);
    expect(
      RecommendationSettings.fromJson(settings.toJson()).toJson(),
      settings.toJson(),
    );
  });
}
