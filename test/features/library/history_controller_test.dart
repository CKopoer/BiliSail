import 'dart:async';

import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/library/application/library_controller.dart';
import 'package:bilisail/features/library/domain/library_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

WatchHistoryEntry entry(
  String cid, {
  int day = 5,
  String? episodeId,
  String? deletionKey,
}) => WatchHistoryEntry(
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
  deletionKey: deletionKey ?? 'archive_$cid',
);

final class _Repository implements LibraryRepository, WatchHistoryMutations {
  @override
  String accountScope = 'user:1';
  final List<
    ({
      String keyword,
      String? cursor,
      RequestCancellation cancellation,
      Completer<WatchHistoryPage> result,
    })
  >
  calls = [];
  final writes =
      <({String? key, RequestCancellation token, Completer<void> result})>[];
  @override
  Future<void> deleteHistory(
    String deletionKey, {
    required RequestCancellation cancellation,
  }) => _write(deletionKey, cancellation);
  @override
  Future<void> clearHistory({required RequestCancellation cancellation}) =>
      _write(null, cancellation);
  Future<void> _write(String? key, RequestCancellation token) {
    final result = Completer<void>();
    writes.add((key: key, token: token, result: result));
    return result.future;
  }

  @override
  Future<WatchHistoryPage> loadHistory({
    String keyword = '',
    String? cursor,
    required RequestCancellation cancellation,
  }) {
    final result = Completer<WatchHistoryPage>();
    calls.add((
      keyword: keyword,
      cursor: cursor,
      cancellation: cancellation,
      result: result,
    ));
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

  test('disposing before the initial refresh prevents reads', () async {
    final isolatedRepository = _Repository();
    final isolated = ProviderContainer(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(isolatedRepository),
      ],
    );
    isolated.listen(historyProvider, (_, _) {});
    isolated.dispose();
    await settle();
    expect(isolatedRepository.calls, isEmpty);
  });

  Future<void> loaded() async {
    await settle();
    repository.calls[0].result.complete(
      WatchHistoryPage(
        [entry('1'), entry('2'), entry('3', deletionKey: 'archive_2')],
        hasMore: true,
        nextCursor: 'first',
      ),
    );
    await settle();
  }

  test(
    'search cancels old paging, resets the cursor and discards late responses',
    () async {
      await loaded();
      final controller = container.read(historyProvider.notifier);
      final oldPage = controller.loadMore();
      final first = controller.search('  Flutter  ');
      expect(repository.calls[1].cancellation.isCancelled, true);
      expect(repository.calls[2].keyword, 'Flutter');
      expect(repository.calls[2].cursor, isNull);
      final second = controller.search('Dart');
      expect(repository.calls[2].cancellation.isCancelled, true);
      repository.calls[3].result.complete(
        WatchHistoryPage([entry('4')], hasMore: true, nextCursor: '2'),
      );
      await second;
      repository.calls[1].result.complete(
        WatchHistoryPage([entry('old-page')], hasMore: false),
      );
      repository.calls[2].result.completeError(
        const AppFailure(AppFailureKind.network, '旧错误'),
      );
      await Future.wait([oldPage, first]);
      expect(container.read(historyProvider).keyword, 'Dart');
      expect(
        container.read(historyProvider).items.requireValue.single.part.cid,
        '4',
      );
      final more = controller.loadMore();
      expect(repository.calls.last.keyword, 'Dart');
      expect(repository.calls.last.cursor, '2');
      repository.calls.last.result.complete(
        WatchHistoryPage([entry('5')], hasMore: false),
      );
      await more;
      expect(container.read(historyProvider).keyword, 'Dart');
      final refresh = controller.refresh();
      expect(repository.calls.last.keyword, 'Dart');
      expect(repository.calls.last.cursor, isNull);
      repository.calls.last.result.complete(
        const WatchHistoryPage([], hasMore: false),
      );
      await refresh;
      final clearSearch = controller.search('  ');
      expect(repository.calls.last.keyword, '');
      expect(repository.calls.last.cursor, isNull);
      repository.calls.last.result.complete(
        WatchHistoryPage([entry('1')], hasMore: false),
      );
      await clearSearch;
      expect(container.read(historyProvider).keyword, '');
    },
  );

  test('failed search and paging retry keep the submitted keyword', () async {
    await loaded();
    final controller = container.read(historyProvider.notifier);
    final search = controller.search('Flutter');
    repository.calls.last.result.completeError(
      const AppFailure(AppFailureKind.network, '网络错误'),
    );
    await search;
    expect(container.read(historyProvider).keyword, 'Flutter');
    final retry = controller.refresh();
    expect(repository.calls.last.keyword, 'Flutter');
    repository.calls.last.result.complete(
      WatchHistoryPage([entry('1')], hasMore: true, nextCursor: '2'),
    );
    await retry;
    final more = controller.loadMore();
    repository.calls.last.result.completeError(
      const AppFailure(AppFailureKind.network, '分页错误'),
    );
    await more;
    expect(container.read(historyProvider).keyword, 'Flutter');
    final next = controller.loadMore();
    expect(repository.calls.last.keyword, 'Flutter');
    expect(repository.calls.last.cursor, '2');
    repository.calls.last.result.complete(
      const WatchHistoryPage([], hasMore: false),
    );
    await next;
  });

  for (final clear in [false, true]) {
    test(
      'search keyword survives ${clear ? 'clearing' : 'deleting'} history and cannot change during a write',
      () async {
        await loaded();
        final controller = container.read(historyProvider.notifier);
        final search = controller.search('Flutter');
        repository.calls.last.result.complete(
          WatchHistoryPage([entry('1')], hasMore: false),
        );
        await search;
        final pending = clear
            ? controller.clear()
            : controller.delete(
                container.read(historyProvider).items.requireValue.single,
              );
        await controller.search('ignored');
        expect(repository.calls, hasLength(2));
        repository.writes.single.result.complete();
        await pending;
        expect(container.read(historyProvider).keyword, 'Flutter');
        expect(container.read(historyProvider).items.requireValue, isEmpty);
      },
    );
  }

  for (final clear in [false, true]) {
    Future<bool> write() {
      final controller = container.read(historyProvider.notifier);
      return clear
          ? controller.clear()
          : controller.delete(
              container.read(historyProvider).items.requireValue[1],
            );
    }

    test(
      '${clear ? 'clear' : 'delete'} is single flight and discards a late page',
      () async {
        await loaded();
        final controller = container.read(historyProvider.notifier);
        final more = controller.loadMore();
        final pending = write();
        expect(repository.calls[1].cancellation.isCancelled, true);
        expect(container.read(historyProvider).writeBusy, true);
        expect(await write(), false);
        await controller.refresh();
        await controller.loadMore();
        expect(repository.calls, hasLength(2));
        expect(repository.writes.single.key, clear ? null : 'archive_2');
        repository.writes.single.result.complete();
        expect(await pending, true);
        repository.calls[1].result.complete(
          WatchHistoryPage([entry('2')], hasMore: false),
        );
        await more;
        expect(
          container
              .read(historyProvider)
              .items
              .requireValue
              .map((e) => e.part.cid),
          clear ? isEmpty : ['1'],
        );
        expect(container.read(historyProvider).writeBusy, false);
        expect(container.read(historyProvider).hasMore, !clear);
        if (!clear) {
          final next = controller.loadMore();
          expect(repository.calls.last.cursor, 'first');
          repository.calls.last.result.complete(
            WatchHistoryPage([entry('4')], hasMore: false),
          );
          await next;
          expect(
            container
                .read(historyProvider)
                .items
                .requireValue
                .map((e) => e.part.cid),
            ['1', '4'],
          );
        }
      },
    );
    test(
      '${clear ? 'clear' : 'delete'} explicit failure keeps cards and allows retry',
      () async {
        await loaded();
        final pending = write();
        final assertion = expectLater(pending, throwsA(isA<AppFailure>()));
        repository.writes.single.result.completeError(
          const AppFailure(AppFailureKind.permission, '拒绝操作'),
        );
        await assertion;
        expect(
          container.read(historyProvider).items.requireValue,
          hasLength(3),
        );
        expect(container.read(historyProvider).writeBusy, false);
        final retry = write();
        repository.writes.last.result.complete();
        expect(await retry, true);
      },
    );
    test(
      '${clear ? 'clear' : 'delete'} uncertain outcome requires a successful refresh',
      () async {
        await loaded();
        final pending = write();
        final assertion = expectLater(
          pending,
          throwsA(isA<HistoryWriteUncertain>()),
        );
        repository.writes.single.result.completeError(
          const HistoryWriteUncertain(),
        );
        await assertion;
        expect(
          container.read(historyProvider).items.requireValue,
          hasLength(3),
        );
        await expectLater(write(), throwsA(isA<HistoryWriteUncertain>()));
        expect(repository.writes, hasLength(1));
        final controller = container.read(historyProvider.notifier);
        final failed = controller.refresh();
        repository.calls.last.result.completeError(
          const AppFailure(AppFailureKind.network, '网络错误'),
        );
        await failed;
        expect(container.read(historyProvider).writeUncertain, true);
        final refreshed = controller.refresh();
        repository.calls.last.result.complete(
          WatchHistoryPage([entry('1'), entry('2')], hasMore: false),
        );
        await refreshed;
        expect(container.read(historyProvider).writeUncertain, false);
        final retry = write();
        repository.writes.last.result.complete();
        expect(await retry, true);
      },
    );
    for (final change in ['scope', 'epoch', 'dispose']) {
      test(
        '${clear ? 'clear' : 'delete'} ignores completion after $change',
        () async {
          await loaded();
          final pending = write();
          if (change == 'scope') repository.accountScope = 'user:2';
          if (change == 'epoch') epoch++;
          if (change == 'dispose') {
            container.invalidate(historyProvider);
            expect(repository.writes.single.token.isCancelled, true);
          }
          repository.writes.single.result.complete();
          expect(await pending, false);
          if (change != 'dispose') {
            expect(
              container.read(historyProvider).items.requireValue,
              hasLength(3),
            );
          }
        },
      );
    }
  }

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
