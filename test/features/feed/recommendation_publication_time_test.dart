import 'dart:async';

import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/application/recommendation_publication_time.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/presentation/feed_video_grid.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

VideoId _id(int value) => VideoId('BV1abc${value.toString().padLeft(6, '0')}');
final _cancelled = isA<AppFailure>().having(
  (error) => error.kind,
  'kind',
  AppFailureKind.cancelled,
);

void main() {
  late _Repository repository;
  late RecommendationPublicationTimes times;
  var epoch = 0;
  setUp(() {
    epoch = 0;
    repository = _Repository();
    times = RecommendationPublicationTimes(
      repository: repository,
      sessionEpoch: () => epoch,
    );
  });
  tearDown(() => times.dispose());

  test(
    'bounds concurrency and cancels a queued card before making a request',
    () async {
      final tokens = List.generate(6, (_) => RequestCancellation());
      final futures = [
        for (var i = 0; i < 6; i++) times.load(_id(i), tokens[i]),
      ];
      expect(repository.calls, hasLength(4));
      final cancelled = expectLater(futures[4], throwsA(_cancelled));
      tokens[4].cancel();
      await cancelled;
      final date = DateTime(2026, 11, 1);
      repository.calls.first.result.complete(date);
      expect(await futures.first, date);
      expect(repository.calls, hasLength(5));
      expect(repository.calls.last.id, _id(5));
      for (final call in repository.calls.skip(1)) {
        call.result.complete(date);
      }
      await Future.wait([futures[1], futures[2], futures[3], futures[5]]);
      expect(await times.load(_id(0), RequestCancellation()), date);
      expect(repository.calls, hasLength(5));
    },
  );

  test(
    'late account responses are rejected and successful caches are scoped',
    () async {
      final old = times.load(_id(0), RequestCancellation());
      final rejected = expectLater(old, throwsA(_cancelled));
      epoch++;
      final current = times.load(_id(0), RequestCancellation());
      repository.calls[0].result.complete(DateTime(2025));
      final date = DateTime(2026);
      repository.calls[1].result.complete(date);
      await rejected;
      expect(await current, date);
      expect(await times.load(_id(0), RequestCancellation()), date);
      expect(repository.calls, hasLength(2));
      epoch++;
      final next = times.load(_id(0), RequestCancellation());
      expect(repository.calls, hasLength(3));
      repository.calls.last.result.complete(null);
      expect(await next, isNull);
    },
  );

  test(
    'cancellation rejects in-flight responses and does not cache them',
    () async {
      final token = RequestCancellation();
      final first = times.load(_id(0), token);
      final cancelled = expectLater(first, throwsA(_cancelled));
      token.cancel();
      repository.calls.single.result.complete(DateTime(2025));
      await cancelled;
      final retry = times.load(_id(0), RequestCancellation());
      repository.calls.last.result.complete(null);
      expect(await retry, isNull);
      expect(await times.load(_id(0), RequestCancellation()), isNull);
      expect(repository.calls, hasLength(2));
    },
  );

  test(
    'metadata failures remain errors and may be explicitly retried',
    () async {
      final first = times.load(_id(0), RequestCancellation());
      final failed = expectLater(first, throwsA(isA<AppFailure>()));
      repository.calls.single.result.completeError(
        const AppFailure(AppFailureKind.network, '网络失败'),
      );
      await failed;
      final retry = times.load(_id(0), RequestCancellation());
      repository.calls.last.result.complete(null);
      await retry;
      expect(repository.calls, hasLength(2));
    },
  );

  test('retains a bounded LRU cache and skips non-video identities', () async {
    repository.immediate = true;
    final limit = RecommendationPublicationTimes.maximumCachedEntries;
    for (var i = 0; i < limit; i++) {
      await times.load(_id(i), RequestCancellation());
    }
    await times.load(_id(0), RequestCancellation());
    await times.load(_id(limit), RequestCancellation());
    await times.load(_id(0), RequestCancellation());
    expect(repository.calls, hasLength(limit + 1));
    await times.load(_id(1), RequestCancellation());
    expect(repository.calls, hasLength(limit + 2));
    expect(
      await times.load(const VideoId('app:bangumi:42'), RequestCancellation()),
      isNull,
    );
    expect(repository.calls, hasLength(limit + 2));
  });

  test(
    'bounds queued work and disposal cancels active and queued requests',
    () async {
      final total =
          RecommendationPublicationTimes.maximumConcurrentRequests +
          RecommendationPublicationTimes.maximumQueuedRequests;
      final checks = [
        for (var i = 0; i < total; i++)
          expectLater(
            times.load(_id(i), RequestCancellation()),
            throwsA(_cancelled),
          ),
      ];
      await expectLater(
        times.load(_id(total), RequestCancellation()),
        throwsA(
          isA<AppFailure>().having(
            (error) => error.kind,
            'kind',
            AppFailureKind.rateLimited,
          ),
        ),
      );
      times.dispose();
      for (final call in repository.calls) {
        expect(call.cancellation.isCancelled, isTrue);
        call.result.complete(null);
      }
      await Future.wait(checks);
      await expectLater(
        times.load(_id(0), RequestCancellation()),
        throwsA(_cancelled),
      );
    },
  );

  testWidgets(
    'hidden workspaces defer metadata and cancel unfinished card requests',
    (tester) async {
      final active = ValueNotifier(false);
      addTearDown(active.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [feedRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder(
                valueListenable: active,
                builder: (_, value, _) => WorkspaceActivity(
                  active: value,
                  child: CustomScrollView(
                    slivers: [
                      FeedVideoGrid(
                        items: [
                          VideoSummary(
                            id: _id(0),
                            title: '视频',
                            coverUrl: '',
                            author: 'UP',
                            duration: const Duration(minutes: 1),
                          ),
                        ],
                        channel: HomeChannel.recommended,
                        onReject: (_) {},
                        onUndo: (_) {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.calls, isEmpty);
      active.value = true;
      await tester.pumpAndSettle();
      expect(repository.calls, hasLength(1));
      active.value = false;
      await tester.pumpAndSettle();
      expect(repository.calls.single.cancellation.isCancelled, isTrue);
      repository.calls.single.result.complete(DateTime(2020, 1, 2));
      await tester.pumpAndSettle();
      active.value = true;
      await tester.pumpAndSettle();
      expect(repository.calls, hasLength(2));
      repository.calls.last.result.complete(DateTime(2021, 3, 4));
      await tester.pumpAndSettle();
      expect(find.text('2020-01-02'), findsNothing);
      expect(find.text('2021-03-04'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mounted cards fill missing times without rebuilding their neighbors',
    (tester) async {
      final knownDate = DateTime(2020, 1, 2);
      final items = [
        for (var i = 0; i < 2; i++)
          VideoSummary(
            id: _id(i),
            title: '视频 $i',
            coverUrl: '',
            author: 'UP',
            duration: const Duration(minutes: 1),
            publishedAt: i == 0 ? null : knownDate,
          ),
      ];
      final active = ValueNotifier(true);
      addTearDown(active.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [feedRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder(
                valueListenable: active,
                builder: (_, value, _) => WorkspaceActivity(
                  active: value,
                  child: CustomScrollView(
                    slivers: [
                      FeedVideoGrid(
                        items: items,
                        channel: HomeChannel.recommended,
                        onReject: (_) {},
                        onUndo: (_) {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.calls, hasLength(1));
      expect(repository.calls.single.id, _id(0));
      expect(find.text('2020-01-02'), findsOneWidget);
      final neighbor = tester.widget<VideoCard>(find.byType(VideoCard).last);
      repository.calls.single.result.complete(
        DateTime.now().subtract(const Duration(minutes: 5, seconds: 10)),
      );
      await tester.pumpAndSettle();
      expect(find.text('5分钟前'), findsOneWidget);
      expect(
        identical(
          tester.widget<VideoCard>(find.byType(VideoCard).last),
          neighbor,
        ),
        isTrue,
      );
      active.value = false;
      await tester.pumpAndSettle();
      active.value = true;
      await tester.pumpAndSettle();
      expect(find.text('5分钟前'), findsOneWidget);
      expect(repository.calls, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}

final class _Repository extends Fake
    implements FeedRepository, RecommendationPublicationTimeRepository {
  final calls = <_Call>[];
  bool immediate = false;
  @override
  Future<DateTime?> loadPublicationTime(
    VideoId id, {
    required RequestCancellation cancellation,
  }) {
    final call = _Call(id, cancellation);
    calls.add(call);
    if (immediate) call.result.complete(DateTime(2026));
    return call.result.future;
  }
}

final class _Call {
  _Call(this.id, this.cancellation);
  final VideoId id;
  final RequestCancellation cancellation;
  final result = Completer<DateTime?>();
}
