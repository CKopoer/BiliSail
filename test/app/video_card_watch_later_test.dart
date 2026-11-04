import 'dart:async';

import 'package:bilisail/app/video_card_watch_later.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/application/watch_later_removal_controller.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = VideoId('BV1234567890');
const _entry = HomeEntry(
  id: 'BV1234567890',
  bvid: 'BV1234567890',
  aid: '9007199254740993',
  title: 'fixture',
  kind: HomeEntryKind.video,
);

void main() {
  test(
    'membership uses the complete account list and preserves exact aid',
    () async {
      final home = _Home();
      final repository = AppVideoCardWatchLaterRepository(
        home,
        (_, _) async => true,
      );
      expect(await repository.load(RequestCancellation()), {
        _id: '9007199254740993',
      });
      expect(home.query?.channel, HomeChannel.watchLater);
      expect(home.query?.section, '全部');
      expect(home.query?.scope, 'user:7');
      final filtered = AppVideoCardWatchLaterRepository(
        home,
        (_, _) async => true,
        removedIds: () => {_id.value},
      );
      expect(await filtered.load(RequestCancellation()), isEmpty);
      home.hasMore = true;
      await expectLater(
        repository.load(RequestCancellation()),
        throwsA(isA<AppFailure>()),
      );
    },
  );

  test(
    'card cancellation filters both retained lists and stale refreshes',
    () async {
      final home = _Home();
      final container = ProviderContainer(
        overrides: [homeRepositoryProvider.overrideWithValue(home)],
      );
      addTearDown(container.dispose);
      final queries = [
        for (final section in ['全部', '未看完'])
          (
            channel: HomeChannel.watchLater,
            section: section,
            scope: home.accountScope,
            folderId: null,
          ),
      ];
      final subscriptions = [
        for (final query in queries)
          container.listen(homeControllerProvider(query), (_, _) {}),
      ];
      addTearDown(() {
        for (final subscription in subscriptions) {
          subscription.close();
        }
      });
      await Future<void>.delayed(Duration.zero);
      final repository = AppVideoCardWatchLaterRepository(
        home,
        (entry, cancellation) => container
            .read(watchLaterRemovalProvider(home.accountScope).notifier)
            .remove(entry, cancellation: cancellation),
      );
      expect(
        await repository.remove(_id, '9007199254740993', RequestCancellation()),
        true,
      );
      expect(home.removed?.aid, '9007199254740993');
      expect(home.removed?.id, _id.value);
      for (final query in queries) {
        expect(
          container.read(homeControllerProvider(query)).items.requireValue,
          isEmpty,
        );
        await container.read(homeControllerProvider(query).notifier).refresh();
        expect(
          container.read(homeControllerProvider(query)).items.requireValue,
          isEmpty,
        );
      }
      container
          .read(watchLaterRemovalProvider(home.accountScope).notifier)
          .restore(_id.value);
      await container
          .read(homeControllerProvider(queries.first).notifier)
          .refresh();
      expect(
        container
            .read(homeControllerProvider(queries.first))
            .items
            .requireValue,
        [_entry],
      );
    },
  );

  test('card cancellation signal cancels the shared write and rejects late success', () async {
    final home = _Home()..pending = Completer<void>();
    final container = ProviderContainer(
      overrides: [homeRepositoryProvider.overrideWithValue(home)],
    );
    addTearDown(container.dispose);
    final token = RequestCancellation();
    final remove = container
        .read(watchLaterRemovalProvider(home.accountScope).notifier)
        .remove(_entry, cancellation: token);
    token.cancel();
    expect(home.token?.isCancelled, true);
    home.pending?.complete();
    expect(await remove, false);
    expect(
      container.read(watchLaterRemovalProvider(home.accountScope)).removed,
      isEmpty,
    );
  });
}

final class _Home implements HomeRepository, HomeWatchLaterRepository {
  HomeQuery? query;
  HomeEntry? removed;
  bool hasMore = false;
  RequestCancellation? token;
  Completer<void>? pending;
  @override
  String get accountScope => 'user:7';
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    this.query = query;
    return HomePage([_entry], hasMore: hasMore);
  }

  @override
  Future<void> removeWatchLater(
    HomeEntry entry, {
    required String scope,
    required RequestCancellation cancellation,
  }) async {
    removed = entry;
    token = cancellation;
    await pending?.future;
  }
}
