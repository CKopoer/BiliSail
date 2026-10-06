import 'dart:async';

import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/library/application/library_controller.dart';
import 'package:bilisail/features/library/domain/library_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

WatchHistoryEntry entry(String cid, {int day = 5, String? episodeId}) =>
    WatchHistoryEntry(
      video: const VideoSummary(
        id: VideoId('BV1234567890'),
        title: '云端视频',
        coverUrl: '',
        author: '作者',
        duration: Duration(seconds: 100),
      ),
      part: VideoPart(
        cid: cid,
        page: 1,
        title: '',
        duration: const Duration(seconds: 100),
      ),
      position: const Duration(seconds: 20),
      watchedAt: DateTime(2026, 10, day),
      episodeId: episodeId,
    );

final class _Repository implements LibraryRepository {
  @override
  String accountScope = 'user:1';
  final List<
    ({
      String? cursor,
      RequestCancellation cancellation,
      Completer<WatchHistoryPage> result,
    })
  >
  calls = [];
  @override
  Future<WatchHistoryPage> loadHistory({
    String? cursor,
    required RequestCancellation cancellation,
  }) {
    final result = Completer<WatchHistoryPage>();
    calls.add((cursor: cursor, cancellation: cancellation, result: result));
    return result.future;
  }
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late _Repository repository;
  late ProviderContainer container;
  var epoch = 0;
  setUp(() {
    epoch = 0;
    repository = _Repository();
    container = ProviderContainer(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(repository),
        sessionEpochProvider.overrideWithValue(() => epoch),
      ],
    );
    container.listen(historyProvider, (_, _) {});
  });
  tearDown(() => container.dispose());

  test('pagination preserves parts/episodes, deduplicates overlap and stops at the end', () async {
    await settle();
    repository.calls[0].result.complete(
      WatchHistoryPage(
        [entry('1'), entry('2')],
        hasMore: true,
        nextCursor: '1',
      ),
    );
    await settle();
    final more = container.read(historyProvider.notifier).loadMore();
    expect(repository.calls[1].cursor, '1');
    repository.calls[1].result.complete(
      WatchHistoryPage([
        entry('2'),
        entry('3', episodeId: '123'),
      ], hasMore: false),
    );
    await more;
    expect(
      container.read(historyProvider).items.requireValue.map((e) => e.part.cid),
      ['1', '2', '3'],
    );
    await container.read(historyProvider.notifier).loadMore();
    expect(repository.calls, hasLength(2));
  });

  test('refresh cancels an old page and ignores its late response', () async {
    await settle();
    final refresh = container.read(historyProvider.notifier).refresh();
    expect(repository.calls[0].cancellation.isCancelled, true);
    repository.calls[1].result.complete(
      WatchHistoryPage([entry('new')], hasMore: false),
    );
    await refresh;
    repository.calls[0].result.complete(
      WatchHistoryPage([entry('old')], hasMore: false),
    );
    await settle();
    expect(
      container.read(historyProvider).items.requireValue.single.part.cid,
      'new',
    );
  });

  test(
    'failed next page retains cards and retry uses the original cursor',
    () async {
      await settle();
      repository.calls[0].result.complete(
        WatchHistoryPage([entry('1')], hasMore: true, nextCursor: '1'),
      );
      await settle();
      final more = container.read(historyProvider.notifier).loadMore();
      repository.calls[1].result.completeError(
        const AppFailure(AppFailureKind.network, '网络错误'),
      );
      await more;
      expect(container.read(historyProvider).items.requireValue, hasLength(1));
      expect(container.read(historyProvider).pageError, isA<AppFailure>());
      final retry = container.read(historyProvider.notifier).loadMore();
      expect(repository.calls[2].cursor, '1');
      repository.calls[2].result.complete(
        WatchHistoryPage([entry('2')], hasMore: false),
      );
      await retry;
      expect(container.read(historyProvider).items.requireValue, hasLength(2));
    },
  );

  test(
    'repeated cursor reports a page error without appending its records',
    () async {
      await settle();
      repository.calls[0].result.complete(
        WatchHistoryPage([entry('1')], hasMore: true, nextCursor: '1'),
      );
      await settle();
      final more = container.read(historyProvider.notifier).loadMore();
      repository.calls[1].result.complete(
        WatchHistoryPage([entry('2')], hasMore: true, nextCursor: '1'),
      );
      await more;
      expect(container.read(historyProvider).pageError, isA<AppFailure>());
      expect(container.read(historyProvider).items.requireValue, hasLength(1));
    },
  );

  test('filtered pages have a bounded automatic scan', () async {
    await settle();
    repository.calls[0].result.complete(
      const WatchHistoryPage([], hasMore: true, nextCursor: '1'),
    );
    await settle();
    for (var i = 1; i < 3; i++) {
      final more = container.read(historyProvider.notifier).loadMore();
      repository.calls[i].result.complete(
        WatchHistoryPage(const [], hasMore: true, nextCursor: '${i + 1}'),
      );
      await more;
    }
    expect(container.read(historyProvider).pageError, isA<AppFailure>());
  });

  for (final sameAccount in [false, true]) {
    test(
      '${sameAccount ? 'epoch' : 'scope'} change cannot publish old cards',
      () async {
        await settle();
        if (sameAccount) {
          epoch++;
        } else {
          repository.accountScope = 'user:2';
        }
        repository.calls[0].result.complete(
          WatchHistoryPage([entry('old')], hasMore: false),
        );
        await settle();
        expect(container.read(historyProvider).items.asData, isNull);
        final refresh = container.read(historyProvider.notifier).refresh();
        repository.calls[1].result.complete(
          WatchHistoryPage([entry('new')], hasMore: false),
        );
        await refresh;
        expect(
          container.read(historyProvider).items.requireValue.single.part.cid,
          'new',
        );
      },
    );
  }

  test('retains only a bounded list of recent history', () async {
    await settle();
    repository.calls[0].result.complete(
      WatchHistoryPage(
        [for (var i = 0; i < 501; i++) entry('$i')],
        hasMore: true,
        nextCursor: '1',
      ),
    );
    await settle();
    expect(container.read(historyProvider).items.requireValue, hasLength(500));
    expect(container.read(historyProvider).limitReached, true);
    expect(container.read(historyProvider).hasMore, false);
  });
}
