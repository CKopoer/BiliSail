import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/application/watch_later_removal_controller.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/video/domain/video_actions_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _video = VideoSummary(
  id: VideoId('BV1234567890'),
  title: '推荐视频',
  coverUrl: '',
  author: 'UP',
  duration: Duration(seconds: 60),
  recommendationFeedback: RecommendationFeedback(
    aid: '42',
    goto: 'av',
    trackId: '',
    ownerMid: '7',
  ),
);
const _entry = HomeEntry(
  id: 'BV1234567890',
  bvid: 'BV1234567890',
  aid: '42',
  title: '稍后视频',
  kind: HomeEntryKind.video,
);
const _all = (
  channel: HomeChannel.watchLater,
  section: '全部',
  scope: 'user:7',
  folderId: null,
);
const _unfinished = (
  channel: HomeChannel.watchLater,
  section: '未看完',
  scope: 'user:7',
  folderId: null,
);

void main() {
  for (final error in [
    const UnknownWriteOutcome(),
    const AppFailure(AppFailureKind.rateLimited, 'fixture'),
  ]) {
    test(
      'cached recommendation pending clears after a hidden channel failure $error',
      () async {
        final (container, repo, controller) = await _feed();
        final write = controller.rejectRecommendation(_video);
        final check = expectLater(write, throwsA(same(error)));
        await controller.selectPopular();
        repo.writes.single.completeError(error);
        await check;
        expect(
          controller.stateForChannel(HomeChannel.recommended).rejecting,
          isEmpty,
        );
        await controller.selectRecommended();
        expect(container.read(feedControllerProvider).rejecting, isEmpty);
        expect(container.read(feedControllerProvider).items.requireValue, [
          _video,
        ]);
      },
    );
  }
  test(
    'recommendation feedback keeps its slot through late paging and refresh',
    () async {
      final (container, repo, controller) = await _feed();
      final more = controller.loadMore();
      final latePage = repo.pages.last;
      final write = controller.rejectRecommendation(_video);
      expect(await controller.rejectRecommendation(_video), false);
      expect(container.read(feedControllerProvider).items.requireValue, [
        _video,
      ]);
      expect(container.read(feedControllerProvider).rejecting, {_video.id});
      repo.writes.single.complete();
      expect(await write, true);
      expect(container.read(feedControllerProvider).items.requireValue, [
        _video,
      ]);
      expect(container.read(feedControllerProvider).rejected, {_video.id});
      latePage.complete(const PageResult(items: [_video], hasMore: false));
      await more;
      expect(container.read(feedControllerProvider).items.requireValue, [
        _video,
      ]);
      expect(container.read(feedControllerProvider).rejected, {_video.id});
      final refresh = controller.refresh();
      repo.pages.last.complete(
        const PageResult(items: [_video], hasMore: false),
      );
      await refresh;
      expect(container.read(feedControllerProvider).items.requireValue, [
        _video,
      ]);
      expect(container.read(feedControllerProvider).rejected, {_video.id});
    },
  );
  test(
    'recommendation known failure keeps video and explicit retry may succeed',
    () async {
      final (container, repo, controller) = await _feed();
      final write = controller.rejectRecommendation(_video);
      final check = expectLater(write, throwsA(isA<AppFailure>()));
      repo.writes.single.completeError(
        const AppFailure(AppFailureKind.rateLimited, 'fixture'),
      );
      await check;
      expect(container.read(feedControllerProvider).items.requireValue, [
        _video,
      ]);
      expect(container.read(feedControllerProvider).rejected, isEmpty);
      final retry = controller.rejectRecommendation(_video);
      repo.writes.last.complete();
      expect(await retry, true);
      expect(repo.writes, hasLength(2));
    },
  );
  test(
    'unknown recommendation outcome blocks repeated explicit submission',
    () async {
      final (container, repo, controller) = await _feed();
      final write = controller.rejectRecommendation(_video);
      final check = expectLater(write, throwsA(isA<UnknownWriteOutcome>()));
      repo.writes.single.completeError(const UnknownWriteOutcome());
      await check;
      await expectLater(
        controller.rejectRecommendation(_video),
        throwsA(isA<UnknownWriteOutcome>()),
      );
      expect(repo.writes, hasLength(1));
      expect(container.read(feedControllerProvider).items.requireValue, [
        _video,
      ]);
      expect(container.read(feedControllerProvider).rejected, isEmpty);
    },
  );
  test(
    'late recommendation success edits saved recommendation channel only',
    () async {
      final (container, repo, controller) = await _feed();
      final write = controller.rejectRecommendation(_video);
      await controller.selectPopular();
      repo.writes.single.complete();
      expect(await write, true);
      expect(container.read(feedControllerProvider).items.requireValue, [
        _video,
      ]);
      expect(container.read(feedControllerProvider).rejected, isEmpty);
      expect(controller.stateForChannel(HomeChannel.recommended).rejected, {
        _video.id,
      });
      await controller.selectRecommended();
      expect(container.read(feedControllerProvider).items.requireValue, [
        _video,
      ]);
      expect(container.read(feedControllerProvider).rejected, {_video.id});
    },
  );
  test(
    'undo is single flight and clears feedback only after confirmation',
    () async {
      final (container, repo, controller) = await _feed();
      final reject = controller.rejectRecommendation(_video);
      repo.writes.single.complete();
      await reject;
      final undo = controller.undoRecommendationFeedback(_video.id);
      expect(await controller.undoRecommendationFeedback(_video.id), false);
      expect(await controller.rejectRecommendation(_video), false);
      expect(container.read(feedControllerProvider).rejecting, {_video.id});
      expect(container.read(feedControllerProvider).rejected, {_video.id});
      repo.writes.last.complete();
      expect(await undo, true);
      expect(container.read(feedControllerProvider).rejected, isEmpty);
      expect(container.read(feedControllerProvider).items.requireValue, [
        _video,
      ]);
      final next = controller.rejectRecommendation(_video);
      repo.writes.last.complete();
      expect(await next, true);
      expect(repo.writes, hasLength(3));
    },
  );
  test(
    'undo uses accepted feedback context after refreshed metadata changes',
    () async {
      final (_, repo, controller) = await _feed();
      final reject = controller.rejectRecommendation(_video);
      repo.writes.single.complete();
      await reject;
      final refresh = controller.refresh();
      repo.pages.last.complete(
        const PageResult(
          items: [
            VideoSummary(
              id: VideoId('BV1234567890'),
              title: '新推荐上下文',
              coverUrl: '',
              author: 'UP',
              duration: Duration(seconds: 60),
              recommendationFeedback: RecommendationFeedback(
                aid: '42',
                goto: 'av',
                trackId: 'new-track',
                ownerMid: '7',
              ),
            ),
          ],
          hasMore: false,
        ),
      );
      await refresh;
      final undo = controller.undoRecommendationFeedback(_video.id);
      expect(repo.undoFeedback?.trackId, '');
      repo.writes.last.complete();
      expect(await undo, true);
    },
  );
  for (final unknown in [false, true]) {
    test(
      'undo failure keeps feedback and unknown outcome prevents replay: $unknown',
      () async {
        final (container, repo, controller) = await _feed();
        final reject = controller.rejectRecommendation(_video);
        repo.writes.single.complete();
        await reject;
        final undo = controller.undoRecommendationFeedback(_video.id);
        final error = unknown
            ? const UnknownWriteOutcome()
            : const AppFailure(AppFailureKind.rateLimited, 'fixture');
        final check = expectLater(undo, throwsA(same(error)));
        repo.writes.last.completeError(error);
        await check;
        expect(container.read(feedControllerProvider).rejected, {_video.id});
        expect(container.read(feedControllerProvider).rejecting, isEmpty);
        if (unknown) {
          expect(container.read(feedControllerProvider).uncertainRestorations, {
            _video.id,
          });
          await expectLater(
            controller.undoRecommendationFeedback(_video.id),
            throwsA(isA<UnknownWriteOutcome>()),
          );
          expect(repo.writes, hasLength(2));
        } else {
          final retry = controller.undoRecommendationFeedback(_video.id);
          repo.writes.last.complete();
          expect(await retry, true);
        }
      },
    );
  }
  test(
    'hidden channel undo restores the cached card without affecting popular',
    () async {
      final (container, repo, controller) = await _feed();
      final reject = controller.rejectRecommendation(_video);
      repo.writes.single.complete();
      await reject;
      final undo = controller.undoRecommendationFeedback(_video.id);
      await controller.selectPopular();
      repo.writes.last.complete();
      expect(await undo, true);
      expect(container.read(feedControllerProvider).rejected, isEmpty);
      expect(
        controller.stateForChannel(HomeChannel.recommended).rejected,
        isEmpty,
      );
      await controller.selectRecommended();
      expect(container.read(feedControllerProvider).items.requireValue, [
        _video,
      ]);
    },
  );
  test(
    'late undo reply cannot restore feedback after account epoch changes',
    () async {
      final (container, repo, controller) = await _feed();
      final reject = controller.rejectRecommendation(_video);
      repo.writes.single.complete();
      await reject;
      final undo = controller.undoRecommendationFeedback(_video.id);
      repo.feedbackScope = 'session:2';
      repo.writes.last.complete();
      expect(await undo, false);
      expect(container.read(feedControllerProvider).rejected, {_video.id});
      container.invalidate(feedControllerProvider);
      expect(container.read(feedControllerProvider).rejected, isEmpty);
    },
  );
  test(
    'account epoch or disposal invalidates delayed recommendation write',
    () async {
      final (container, repo, controller) = await _feed();
      final write = controller.rejectRecommendation(_video);
      repo.feedbackScope = 'session:2';
      repo.writes.single.complete();
      expect(await write, false);
      expect(container.read(feedControllerProvider).items.requireValue, [
        _video,
      ]);
      final next = controller.rejectRecommendation(_video);
      container.invalidate(feedControllerProvider);
      expect(repo.tokens.last.isCancelled, true);
      repo.writes.last.complete();
      expect(await next, false);
    },
  );
  test('delete updates both subtabs and filters late refresh until confirmed add restores it', () async {
    final (container, repo, removals) = await _home();
    final refresh = container
        .read(homeControllerProvider(_all).notifier)
        .refresh();
    final write = removals.remove(_entry);
    expect(await removals.remove(_entry), false);
    expect(container.read(watchLaterRemovalProvider('user:7')).pending, {
      _entry.id,
    });
    repo.writes.single.complete();
    expect(await write, true);
    repo.pending?.complete(const HomePage([_entry], hasMore: false));
    repo.pending = null;
    await refresh;
    for (final query in [_all, _unfinished]) {
      expect(
        container.read(homeControllerProvider(query)).items.requireValue,
        isEmpty,
      );
    }
    removals.restore(_entry.bvid ?? '');
    await container.read(homeControllerProvider(_all).notifier).refresh();
    expect(container.read(homeControllerProvider(_all)).items.requireValue, [
      _entry,
    ]);
  });
  test(
    'delete failure keeps both subtabs and unknown results are not replayed',
    () async {
      final (container, repo, removals) = await _home();
      final write = removals.remove(_entry);
      final check = expectLater(write, throwsA(isA<UnknownWriteOutcome>()));
      repo.writes.single.completeError(const UnknownWriteOutcome());
      await check;
      await expectLater(
        removals.remove(_entry),
        throwsA(isA<UnknownWriteOutcome>()),
      );
      expect(repo.writes, hasLength(1));
      for (final query in [_all, _unfinished]) {
        expect(
          container.read(homeControllerProvider(query)).items.requireValue,
          [_entry],
        );
      }
    },
  );
  test(
    'deleted video with aid remains removable when playback bvid is missing',
    () async {
      final (_, repo, removals) = await _home();
      const invalid = HomeEntry(
        id: 'invalid:43',
        aid: '43',
        title: '已失效视频',
        kind: HomeEntryKind.video,
      );
      final write = removals.remove(invalid);
      repo.writes.single.complete();
      expect(await write, true);
      expect(repo.entries.single.aid, '43');
    },
  );
  test('session change and family invalidation cancel pending deletes and reset tombstones', () async {
    final (container, repo, removals) = await _home();
    final write = removals.remove(_entry);
    repo.accountScope = 'user:8';
    repo.writes.single.complete();
    expect(await write, false);
    expect(
      container.read(watchLaterRemovalProvider('user:7')).removed,
      isEmpty,
    );
    repo.accountScope = 'user:7';
    final next = removals.remove(_entry);
    container.invalidate(watchLaterRemovalProvider);
    expect(repo.tokens.last.isCancelled, true);
    repo.writes.last.complete();
    expect(await next, false);
    expect(
      container.read(watchLaterRemovalProvider('user:7')).removed,
      isEmpty,
    );
  });
}

Future<(ProviderContainer, _Feed, FeedController)> _feed() async {
  final repo = _Feed();
  final container = ProviderContainer(
    overrides: [feedRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  final controller = container.read(feedControllerProvider.notifier);
  final refresh = controller.refresh();
  repo.pages.single.complete(const PageResult(items: [_video], hasMore: true));
  await refresh;
  return (container, repo, controller);
}

Future<(ProviderContainer, _Home, WatchLaterRemovalController)> _home() async {
  final repo = _Home();
  final container = ProviderContainer(
    overrides: [homeRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  for (final query in [_all, _unfinished]) {
    final sub = container.listen(homeControllerProvider(query), (_, _) {});
    addTearDown(sub.close);
  }
  await Future<void>.delayed(Duration.zero);
  repo.pending = Completer<HomePage>();
  return (
    container,
    repo,
    container.read(watchLaterRemovalProvider('user:7').notifier),
  );
}

final class _Feed extends Fake
    implements FeedRepository, RecommendationFeedbackRepository {
  @override
  String feedbackScope = 'session:1';
  final pages = <Completer<PageResult<VideoSummary>>>[];
  final writes = <Completer<void>>[];
  final tokens = <RequestCancellation>[];
  RecommendationFeedback? undoFeedback;
  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) {
    final result = Completer<PageResult<VideoSummary>>();
    pages.add(result);
    return result.future;
  }

  @override
  Future<PageResult<VideoSummary>> loadPopular({
    required int page,
    required RequestCancellation cancellation,
  }) async => const PageResult(items: [_video], hasMore: false);
  @override
  Future<void> rejectRecommendation(
    RecommendationFeedback feedback, {
    required RequestCancellation cancellation,
  }) {
    tokens.add(cancellation);
    final result = Completer<void>();
    writes.add(result);
    return result.future;
  }

  @override
  Future<void> undoRecommendationFeedback(
    RecommendationFeedback feedback, {
    required RequestCancellation cancellation,
  }) {
    undoFeedback = feedback;
    tokens.add(cancellation);
    final result = Completer<void>();
    writes.add(result);
    return result.future;
  }
}

final class _Home implements HomeRepository, HomeWatchLaterRepository {
  @override
  String accountScope = 'user:7';
  final writes = <Completer<void>>[];
  final tokens = <RequestCancellation>[];
  final entries = <HomeEntry>[];
  Completer<HomePage>? pending;
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async => pending?.future ?? const HomePage([_entry], hasMore: false);
  @override
  Future<void> removeWatchLater(
    HomeEntry entry, {
    required String scope,
    required RequestCancellation cancellation,
  }) {
    entries.add(entry);
    tokens.add(cancellation);
    final result = Completer<void>();
    writes.add(result);
    return result.future;
  }
}
