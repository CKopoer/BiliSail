import 'dart:async';

import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/recommendation_settings.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/featured_feed_controller.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:flutter_test/flutter_test.dart';

VideoSummary _item(int id, {String? cid, String title = 'example'}) =>
    VideoSummary(
      id: VideoId('video-$id'),
      previewCid: cid,
      title: title,
      coverUrl: '',
      author: '',
      duration: Duration.zero,
    );

class _Requests implements FeaturedFeedRepository {
  final batches = <int>[],
      refreshes = <bool>[],
      cancellations = <RequestCancellation>[];
  final replies = <Completer<PageResult<VideoSummary>>>[];
  @override
  Future<PageResult<VideoSummary>> loadFeatured({
    required FeaturedSource source,
    required int batch,
    required bool refresh,
    FeaturedSeed? seed,
    required RequestCancellation cancellation,
  }) {
    final reply = Completer<PageResult<VideoSummary>>();
    batches.add(batch);
    refreshes.add(refresh);
    cancellations.add(cancellation);
    replies.add(reply);
    return reply.future;
  }

  void finish(List<VideoSummary> items, {bool more = true}) =>
      replies.last.complete(PageResult(items: items, hasMore: more));
}

void main() {
  test(
    'a sparse first page fills the swipe window without user input',
    () async {
      final repo = _Requests();
      final feed = FeaturedFeedController(
        repo,
        FeaturedSource.desktop,
        RecommendationFilter(const RecommendationSettings.defaults()),
      );
      addTearDown(feed.dispose);
      feed.setActive(true);
      repo.finish([_item(1)]);
      await Future<void>.delayed(Duration.zero);
      expect(repo.batches, [1, 2]);
      repo.finish([_item(2), _item(3), _item(4)]);
      await Future<void>.delayed(Duration.zero);
      expect(feed.end, 4);
      expect(repo.batches, [1, 2]);
    },
  );

  test('seed, deduplication, prefetch and late cancelled batches', () async {
    final repo = _Requests();
    final feed = FeaturedFeedController(
      repo,
      FeaturedSource.mobile,
      RecommendationFilter(const RecommendationSettings.defaults()),
      seed: (video: _item(0).id, cid: '1', aid: '4', trackId: null),
    );
    addTearDown(feed.dispose);
    feed.setActive(true);
    final pending = feed.load();
    expect(repo.batches, [1]);
    repo.finish([_item(0, cid: '1'), _item(0, cid: '2'), _item(1), _item(2)]);
    await pending;
    expect(feed.end, 4);
    expect(feed.at(1)?.previewCid, '2');
    feed.select(2);
    expect(repo.batches, [1, 2]);
    final stale = repo.replies.last;
    feed.setActive(false);
    expect(repo.cancellations.last.isCancelled, isTrue);
    feed.setActive(true);
    final fresh = feed.load();
    expect(repo.batches, [1, 2, 2]);
    stale.complete(PageResult(items: [_item(99)], hasMore: false));
    repo.finish([_item(3)], more: false);
    await fresh;
    expect(feed.end, 5);
    expect(feed.at(4)?.id, _item(3).id);
  });

  test('leaving an unfinished refresh resumes the retained cursor', () async {
    final repo = _Requests();
    final feed = FeaturedFeedController(
      repo,
      FeaturedSource.desktop,
      RecommendationFilter(const RecommendationSettings.defaults()),
    );
    addTearDown(feed.dispose);
    feed.setActive(true);
    final first = feed.load();
    repo.finish(List.generate(5, _item));
    await first;

    feed.select(2);
    final append = feed.load();
    repo.finish(List.generate(5, (i) => _item(i + 5)));
    await append;
    feed.select(7);
    final staleAppend = repo.replies.last;
    final refresh = feed.refresh();
    staleAppend.complete(PageResult(items: [_item(99)], hasMore: false));
    repo.finish([]);
    await Future<void>.delayed(Duration.zero);
    final staleReplacement = repo.replies.last;

    feed.setActive(false);
    expect(repo.cancellations.last.isCancelled, isTrue);
    feed.setActive(true);
    final resumed = feed.load();
    staleReplacement.complete(PageResult(items: [_item(100)], hasMore: false));
    repo.finish([_item(10)], more: false);
    await refresh;
    await resumed;

    expect(repo.batches, [1, 2, 3, 1, 2, 3]);
    expect(repo.refreshes, [false, false, false, true, false, false]);
    expect(feed.refreshRevision, 0);
    expect(feed.selected, 7);
    expect(feed.at(7)?.id, _item(7).id);
    expect(feed.at(10)?.id, _item(10).id);
  });

  test(
    'filtered refresh preserves the current card until a retry can replace it',
    () async {
      final repo = _Requests();
      final feed = FeaturedFeedController(
        repo,
        FeaturedSource.desktop,
        RecommendationFilter(
          RecommendationSettings(titleKeywords: ['blocked']),
        ),
      );
      addTearDown(feed.dispose);
      feed.setActive(true);
      final first = feed.load();
      repo.finish([_item(1), _item(2)], more: false);
      await first;
      feed.select(1);
      final refresh = feed.refresh();
      repo.finish([_item(3, title: 'blocked')]);
      await Future<void>.delayed(Duration.zero);
      repo.replies.last.completeError(StateError('offline'));
      await refresh;
      expect(feed.selected, 1);
      expect(feed.at(1)?.id, _item(2).id);
      expect(feed.error, isNotNull);
      feed.setActive(false);
      feed.setActive(true);
      expect(repo.batches, [1, 1, 2]);
      final retry = feed.load();
      repo.finish([_item(4)], more: false);
      await retry;
      expect(repo.batches, [1, 1, 2, 2]);
      expect(repo.refreshes, [false, true, false, false]);
      expect(feed.selected, 0);
      expect(feed.at(0)?.id, _item(4).id);
      expect(feed.refreshRevision, 1);
    },
  );
}
