import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';

import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/recommendation_settings.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/app_recommendation_identity.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/domain/app_recommendation_identity_repository.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;
  late _Feed feed;
  late _Identity identity;
  late FeedController controller;
  setUp(() async {
    feed = _Feed();
    identity = _Identity();
    container = ProviderContainer(
      overrides: [
        feedRepositoryProvider.overrideWithValue(feed),
        appRecommendationIdentityRepositoryProvider.overrideWithValue(identity),
        settingsRepositoryProvider.overrideWithValue(_Settings()),
      ],
    );
    await container.read(settingsControllerProvider.future);
    container.listen(feedControllerProvider, (_, _) {});
    controller = container.read(feedControllerProvider.notifier);
  });
  tearDown(() async {
    container.dispose();
    await identity.events.close();
  });
  Future<void> source(RecommendationSource value) async {
    await container
        .read(settingsControllerProvider.notifier)
        .setRecommendations(
          RecommendationSettings(source: value, keepPrevious: true),
        );
    await container.pump();
  }

  void complete(String id, {String? cursor}) => feed.calls.last.result.complete(
    PageResult(
      items: [
        VideoSummary(
          id: VideoId(id),
          title: id,
          coverUrl: '',
          author: '',
          duration: Duration.zero,
        ),
      ],
      hasMore: true,
      nextCursor: cursor,
    ),
  );
  List<String>? ids() => container
      .read(feedControllerProvider)
      .items
      .asData
      ?.value
      .map((item) => item.id.value)
      .toList();

  test('flush and server anchor survive pagination, failed refresh and retry together', () async {
    await source(RecommendationSource.app);
    expect(feed.appRequests.last.reason, AppRecommendationLoadReason.initial);
    expect(feed.appRequests.last.cursor, '0');
    complete('first', cursor: '1794819840');
    await container.pump();
    final more = controller.loadMore();
    expect(feed.appRequests.last.reason, AppRecommendationLoadReason.loadMore);
    expect(feed.appRequests.last.cursor, '1794819840');
    complete('second', cursor: '1794819830');
    await more;
    final filtered = controller.loadMore();
    expect(feed.appRequests.last.cursor, '1794819840');
    feed.calls.last.result.complete(
      const PageResult(items: [], hasMore: true, nextCursor: '1794819820'),
    );
    await filtered;
    final refresh = controller.refresh(
      appReason: AppRecommendationLoadReason.pullDown,
    );
    final failed = feed.appRequests.last;
    expect(failed.cursor, '1794819840');
    feed.calls.last.result.completeError(
      const AppFailure(AppFailureKind.network, 'fixture'),
    );
    await refresh;
    final retry = controller.refresh();
    expect(feed.appRequests.last.cursor, failed.cursor);
    expect(feed.appRequests.last.reason, failed.reason);
    complete('refreshed', cursor: '1794819850');
    await retry;
    final next = controller.loadMore();
    expect(feed.appRequests.last.cursor, '1794819850');
    complete('third');
    await next;
    identity.change();
    await container.pump();
    expect(feed.appRequests.last.cursor, '0');
    expect(
      feed.appRequests.last.reason,
      AppRecommendationLoadReason.identityChanged,
    );
    complete('new-identity', cursor: '42');
    await container.pump();
  });

  for (final target in [
    RecommendationSource.app,
    RecommendationSource.desktop,
  ]) {
    test(
      'switching to $target cancels late data and never merges old entries',
      () async {
        final old = controller.refresh();
        final stale = feed.calls.last;
        expect(stale.source, 'web');
        await source(target);
        expect(stale.cancellation.isCancelled, isTrue);
        expect(feed.calls.last.source, target.name);
        expect(feed.calls.last.page, 1);
        complete('app');
        await container.pump();
        stale.result.complete(const PageResult(items: [], hasMore: false));
        await old;
        expect(ids(), ['app']);
        await source(RecommendationSource.web);
        expect(ids(), isNull);
        complete('new-web');
        await container.pump();
        expect(ids(), ['new-web']);
      },
    );
  }
  for (final target in [
    RecommendationSource.app,
    RecommendationSource.desktop,
  ]) {
    test('hidden recommendation invalidation preserves popular content and starts no hidden request', () async {
      final first = controller.refresh();
      complete('old-web');
      await first;
      final popular = controller.selectPopular();
      complete('popular');
      await popular;
      final count = feed.calls.length;
      await source(target);
      expect(feed.calls.length, count);
      expect(ids(), ['popular']);
      expect(
        controller.stateForChannel(HomeChannel.recommended).items.isLoading,
        isTrue,
      );
      final back = controller.selectRecommended();
      expect(feed.calls.last.source, target.name);
      complete('app');
      await back;
      expect(ids(), ['app']);
      await controller.selectPopular();
      expect(ids(), ['popular']);
      expect(feed.calls.length, count + 1);
    });
  }
  test(
    'device revisions refresh only App recommendations and reset pagination',
    () async {
      final first = controller.refresh();
      complete('web');
      await first;
      identity.change();
      await container.pump();
      expect(feed.calls.length, 1);
      await source(RecommendationSource.app);
      complete('app');
      await container.pump();
      final count = feed.calls.length;
      identity.change();
      await container.pump();
      expect(feed.calls.length, count + 1);
      expect(feed.calls.last.source, 'app');
      expect(feed.calls.last.page, 1);
      expect(ids(), isNull);
      complete('new-device');
      await container.pump();
      expect(ids(), ['new-device']);
    },
  );
}

final class _Settings implements SettingsRepository {
  AppSettings value = const AppSettings.defaults();
  @override
  Future<AppSettings> load() async => value;
  @override
  Future<void> save(AppSettings settings) async {
    value = settings;
  }
}

final class _Feed
    implements
        FeedRepository,
        AppRecommendationFeedRepository,
        DesktopRecommendationFeedRepository {
  final appRequests = <AppRecommendationRequest>[];
  final calls =
      <
        ({
          String source,
          int page,
          RequestCancellation cancellation,
          Completer<PageResult<VideoSummary>> result,
        })
      >[];
  Future<PageResult<VideoSummary>> read(
    String source,
    int page,
    RequestCancellation cancellation,
  ) {
    final result = Completer<PageResult<VideoSummary>>();
    calls.add((
      source: source,
      page: page,
      cancellation: cancellation,
      result: result,
    ));
    return result.future;
  }

  @override
  Future<List<VideoCategory>> loadCategories({
    required RequestCancellation cancellation,
  }) async => [];
  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) => read('web', page, cancellation);
  @override
  Future<PageResult<VideoSummary>> loadPopular({
    required int page,
    required RequestCancellation cancellation,
  }) => read('popular', page, cancellation);
  @override
  Future<PageResult<VideoSummary>> loadAppRecommendations({
    required AppRecommendationRequest request,
    required RequestCancellation cancellation,
  }) {
    appRequests.add(request);
    return read(
      'app',
      request.reason == AppRecommendationLoadReason.loadMore ? 2 : 1,
      cancellation,
    );
  }

  @override
  Future<PageResult<VideoSummary>> loadDesktopRecommendations({
    required int page,
    required RequestCancellation cancellation,
  }) => read('desktop', page, cancellation);
}

final class _Identity implements AppRecommendationIdentityRepository {
  final events = StreamController<int>.broadcast(sync: true);
  @override
  int revision = 0;
  void change() {
    revision++;
    events.add(revision);
  }

  @override
  Stream<int> get changes => events.stream;
  @override
  Future<AppRecommendationIdentity> load() async =>
      const AppRecommendationIdentity(buvid: 'fixture_device_0123456789');
  @override
  Future<void> setBuvid(String value) async => change();
  @override
  Future<void> randomizeBuvid() async => change();
}
