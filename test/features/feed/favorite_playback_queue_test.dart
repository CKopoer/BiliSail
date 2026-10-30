import 'dart:async';

import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/favorite_playback_queue.dart';
import 'package:bilisail/features/feed/application/home_repository_provider.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/video/application/watch_later_queue_registry.dart';
import 'package:bilisail/features/video/domain/watch_later_queue.dart';
import 'package:bilisail/features/video/application/playback_queue_controller.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../messages/message_fakes.dart';

const _request = (
  query: (
    channel: HomeChannel.favorites,
    section: '默认收藏夹',
    scope: 'user:7',
    folderId: '42',
  ),
  title: '我的收藏夹',
);
HomeEntry _entry(int index) => HomeEntry(
  id: '$index',
  kind: HomeEntryKind.video,
  bvid: 'BV${index.toString().padLeft(10, '0')}',
  title: '视频 $index',
  aid: '9007199254740993',
  authorName: 'UP',
  playCountText: '2万',
  danmakuCountText: '100',
);

void main() {
  late _Repository repository;
  late ProviderContainer container;
  late AuthFake auth;
  var epoch = 4;
  final provider = favoritePlaybackQueueProvider(_request);
  setUp(() {
    epoch = 4;
    repository = _Repository();
    auth = AuthFake();
    container = ProviderContainer(
      overrides: [
        homeRepositoryProvider.overrideWithValue(repository),
        sessionEpochProvider.overrideWithValue(() => epoch),
        authRepositoryProvider.overrideWithValue(auth),
      ],
    );
    container.listen(provider, (_, _) {});
  });
  tearDown(() async {
    container.dispose();
    await auth.stream.close();
  });
  Future<WatchLaterQueue?> capture() =>
      container.read(provider.notifier).capture();

  test('reads only the initial page, preserving metadata and deferring the next page', () async {
    repository.pages = {
      1: HomePage(
        [
          const HomeEntry(
            id: 'invalid',
            title: '失效',
            kind: HomeEntryKind.video,
          ),
          _entry(1),
          _entry(2),
        ],
        hasMore: true,
        nextCursor: 'next',
      ),
      2: HomePage([_entry(2), _entry(3)], hasMore: false),
    };
    final queue = (await capture())!;
    expect(repository.calls, [1]);
    expect(repository.cursors, [null]);
    expect(queue.items.map((item) => item.video.id.value), [
      'BV0000000001',
      'BV0000000002',
    ]);
    expect(queue.title, '我的收藏夹');
    expect(queue.isWatchLater, isFalse);
    expect(queue.hasMore, true);
    final subscription = container.listen(
      playbackQueueProvider(queue.id),
      (_, _) {},
    );
    addTearDown(subscription.close);
    await container
        .read(playbackQueueProvider(queue.id).notifier)
        .loadMore(queue.items.first.video.id);
    expect(repository.calls, [1, 2]);
    expect(repository.cursors, [null, 'next']);
    expect(
      container.read(playbackQueueProvider(queue.id)).queue?.items,
      hasLength(3),
    );
    expect(queue.items.first.aid, '9007199254740993');
    expect(queue.items.first.playCountText, '2万');
    expect(queue.items.first.danmakuCountText, '100');
    expect(queue.withoutRemoved({'1', '2'}), same(queue));
    expect(
      queue.adjacent(const VideoId('BV0000000001'), 1)?.video.id.value,
      'BV0000000002',
    );
    expect(
      container
          .read(watchLaterQueueRegistryProvider)
          .resolve(queue.id, scope: 'user:7', sessionEpoch: 4),
      same(container.read(playbackQueueProvider(queue.id)).queue),
    );
  });

  test(
    'an initial page failure can retry without scanning any subsequent pages',
    () async {
      repository.pages = {
        1: HomePage([_entry(1)], hasMore: true),
      };
      repository.failPage = 1;
      expect(await capture(), isNull);
      expect(container.read(provider).error, isA<AppFailure>());
      repository.failPage = null;
      repository.pages[2] = HomePage([_entry(2)], hasMore: false);
      expect((await capture())!.items, hasLength(1));
      expect(repository.calls, [1, 1]);
    },
  );

  test(
    'empty or entirely invalid favorites report no playable video',
    () async {
      repository.pages = {
        1: const HomePage([
          HomeEntry(id: 'invalid', title: '失效', kind: HomeEntryKind.video),
        ], hasMore: false),
      };
      expect(await capture(), isNull);
      expect(
        (container.read(provider).error as AppFailure).kind,
        AppFailureKind.notFound,
      );
    },
  );

  test(
    'stalled pagination stops after three pages without new entries',
    () async {
      repository.pages = {
        for (var page = 1; page < 10; page++)
          page: HomePage([_entry(1)], hasMore: true),
      };
      final queue = (await capture())!;
      final sub = container.listen(playbackQueueProvider(queue.id), (_, _) {});
      addTearDown(sub.close);
      final pager = container.read(playbackQueueProvider(queue.id).notifier);
      for (var i = 0; i < 3; i++) {
        await pager.loadMore(queue.items.first.video.id);
      }
      expect(repository.calls, [1, 2, 3, 4]);
      expect(
        container.read(playbackQueueProvider(queue.id)).message,
        contains('连续多页'),
      );
    },
  );

  test('limits scanned resources and explicitly marks truncation', () async {
    repository.pages = {
      1: HomePage(List.generate(1200, _entry), hasMore: false),
    };
    final queue = (await capture())!;
    expect(queue.items, hasLength(99));
    expect(queue.truncated, isTrue);
    expect(repository.calls, [1]);
  });

  test('a selected source page supports previous and next pages with a fixed cursor', () async {
    repository.pages = {
      for (var page = 1; page <= 3; page++)
        page: HomePage([
          for (var n = (page - 1) * 40; n < page * 40; n++) _entry(n),
        ], hasMore: page < 3),
    };
    final queue = (await container
        .read(provider.notifier)
        .capture(
          page: 2,
          cursor: 'folder-42',
          initial: VideoId(_entry(50).bvid!),
        ))!;
    expect(queue.items, hasLength(40));
    expect(queue.items.first.video.id.value, _entry(40).bvid);
    expect(queue.hasPrevious, true);
    final sub = container.listen(playbackQueueProvider(queue.id), (_, _) {});
    addTearDown(sub.close);
    final pager = container.read(playbackQueueProvider(queue.id).notifier);
    await pager.loadMore(queue.items[10].video.id);
    await pager.loadPrevious(queue.items[10].video.id);
    expect(repository.calls, [2, 3, 1]);
    expect(repository.cursors, everyElement('folder-42'));
    expect(
      container.read(playbackQueueProvider(queue.id)).queue?.items,
      hasLength(120),
    );
  });

  test('favorites share the 99 initial and 999 moving window limits', () async {
    repository.pages = {
      1: HomePage([for (var n = 0; n < 200; n++) _entry(n)], hasMore: true),
      2: HomePage([for (var n = 200; n < 650; n++) _entry(n)], hasMore: true),
      3: HomePage([for (var n = 650; n < 1100; n++) _entry(n)], hasMore: true),
      4: HomePage([
        for (var n = 1100; n < 1550; n++) _entry(n),
      ], hasMore: false),
    };
    final queue = (await capture())!;
    expect(queue.items, hasLength(99));
    final sub = container.listen(playbackQueueProvider(queue.id), (_, _) {});
    addTearDown(sub.close);
    final pager = container.read(playbackQueueProvider(queue.id).notifier);
    for (var page = 2; page <= 4; page++) {
      await pager.loadMore(queue.items.first.video.id);
      expect(
        container.read(playbackQueueProvider(queue.id)).queue!.items.length,
        lessThanOrEqualTo(999),
      );
    }
    expect(
      container.read(playbackQueueProvider(queue.id)).queue?.hasPrevious,
      true,
    );
    expect(
      container.read(playbackQueueProvider(queue.id)).queue?.hasMore,
      false,
    );
  });

  for (final change in ['account', 'epoch', 'dispose']) {
    test('$change cancels or isolates an in-flight queue', () async {
      repository.pending = Completer<HomePage>();
      final notifier = container.read(provider.notifier);
      final result = notifier.capture();
      await Future<void>.delayed(Duration.zero);
      expect(await notifier.capture(), isNull);
      expect(repository.calls, [1]);
      if (change == 'account') repository.accountScope = 'user:8';
      if (change == 'epoch') epoch++;
      if (change == 'dispose') container.invalidate(provider);
      await container.pump();
      repository.pending!.complete(HomePage([_entry(1)], hasMore: false));
      expect(await result, isNull);
      if (change == 'dispose') {
        expect(repository.cancellation!.isCancelled, isTrue);
      }
    });
  }

  test('public folder playback supports guest scope', () async {
    repository.accountScope = 'guest';
    repository.pages = {
      1: HomePage([_entry(1)], hasMore: false),
    };
    final request = (
      query: (
        channel: HomeChannel.favorites,
        section: '默认收藏夹',
        scope: 'guest',
        folderId: '42',
      ),
      title: '公开收藏夹',
    );
    final guest = favoritePlaybackQueueProvider(request);
    final subscription = container.listen(guest, (_, _) {});
    addTearDown(subscription.close);
    final queue = (await container.read(guest.notifier).capture())!;
    expect(queue.scope, 'guest');
    expect(queue.title, '公开收藏夹');
  });

  test('stale account query does not start reading', () async {
    repository.accountScope = 'user:8';
    expect(await capture(), isNull);
    expect(repository.calls, isEmpty);
    container.invalidate(provider);
    await container.pump();
  });

  testWidgets('total deadline cancels a stalled request and reports timeout', (
    tester,
  ) async {
    repository.pending = Completer<HomePage>();
    final result = capture();
    await tester.pump(const Duration(seconds: 31));
    expect(await result, isNull);
    expect(repository.cancellation!.isCancelled, isTrue);
    expect(
      (container.read(provider).error as AppFailure).kind,
      AppFailureKind.timeout,
    );
    repository.pending!.complete(const HomePage([], hasMore: false));
    await tester.pump();
  });
}

final class _Repository implements HomeRepository {
  @override
  String accountScope = 'user:7';
  Map<int, HomePage> pages = {};
  int? failPage;
  Completer<HomePage>? pending;
  RequestCancellation? cancellation;
  final calls = <int>[];
  final cursors = <String?>[];
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    calls.add(page);
    cursors.add(cursor);
    this.cancellation = cancellation;
    if (pending != null) return pending!.future;
    if (failPage == page) {
      throw const AppFailure(AppFailureKind.network, '加载失败');
    }
    return pages[page] ?? const HomePage([], hasMore: false);
  }
}
