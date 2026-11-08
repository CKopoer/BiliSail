import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/feed/application/dynamic_authors_controller.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/dynamic_author.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/dynamic_author_fakes.dart';

const query = (
  channel: HomeChannel.dynamic,
  section: '全部',
  scope: 'user:7',
  folderId: null,
);

void main() {
  late DynamicAuthorRepository repository;
  late ProviderContainer container;
  final provider = dynamicAuthorsProvider('user:7');
  setUp(() {
    repository = DynamicAuthorRepository()..deferAuthors = true;
    container = ProviderContainer(
      overrides: [homeRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    container.listen(provider, (_, _) {});
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);
  Future<void> first({bool more = true}) async {
    await settle();
    repository.authorCalls.last.result.complete(
      DynamicAuthorPage(
        [author(3), author(1)],
        hasMore: more,
        nextCursor: more ? 'first' : null,
      ),
    );
    await settle();
  }

  test(
    'recent-update order, deduplication, selection and pagination are shared',
    () async {
      await first();
      final controller = container.read(provider.notifier);
      controller.select(const UserId('1'));
      final load = controller.loadMore();
      expect(repository.authorCalls.last.cursor, 'first');
      repository.authorCalls.last.result.complete(
        DynamicAuthorPage([author(1), author(2)], hasMore: false),
      );
      await load;
      expect(container.read(provider).items.map((item) => item.id.value), [
        '3',
        '1',
        '2',
      ]);
      expect(container.read(provider).selected?.id, const UserId('1'));
      controller.select(const UserId('999'));
      expect(container.read(provider).selected?.id, const UserId('1'));
      controller.select(null);
      expect(container.read(provider).selected, isNull);
    },
  );

  test(
    'refresh keeps explicit selection and ignores an older response',
    () async {
      await first();
      final controller = container.read(provider.notifier);
      controller.select(const UserId('1'));
      final old = controller.loadMore();
      final stale = repository.authorCalls.last;
      final refresh = controller.refresh();
      expect(stale.cancellation.isCancelled, isTrue);
      repository.authorCalls.last.result.complete(
        DynamicAuthorPage([author(4)], hasMore: false),
      );
      await refresh;
      stale.result.complete(DynamicAuthorPage([author(8)], hasMore: false));
      await old;
      expect(container.read(provider).items.single.id, const UserId('4'));
      expect(container.read(provider).selected?.id, const UserId('1'));
    },
  );

  for (final cursor in ['first', 'second']) {
    test('rejects stalled cursors or duplicate-only pages ($cursor)', () async {
      await first();
      final load = container.read(provider.notifier).loadMore();
      repository.authorCalls.last.result.complete(
        DynamicAuthorPage([author(1)], hasMore: true, nextCursor: cursor),
      );
      await load;
      expect(container.read(provider).error, isA<AppFailure>());
      expect(container.read(provider).items, hasLength(2));
      final retry = container.read(provider.notifier).loadMore();
      expect(repository.authorCalls.last.cursor, 'first');
      repository.authorCalls.last.result.complete(
        DynamicAuthorPage([author(2)], hasMore: false),
      );
      await retry;
      expect(container.read(provider).error, isNull);
    });
  }

  test(
    'retry after a failed refresh replaces the old directory order',
    () async {
      await first();
      final controller = container.read(provider.notifier);
      final refresh = controller.refresh();
      repository.authorCalls.last.result.completeError(
        const AppFailure(AppFailureKind.network, '暂时无法连接'),
      );
      await refresh;
      expect(container.read(provider).items, hasLength(2));
      final retry = controller.loadMore();
      expect(repository.authorCalls.last.cursor, isNull);
      repository.authorCalls.last.result.complete(
        DynamicAuthorPage([author(2)], hasMore: false),
      );
      await retry;
      expect(container.read(provider).items.single.id, const UserId('2'));
    },
  );

  test('author cache is bounded', () async {
    await settle();
    repository.authorCalls.single.result.complete(
      DynamicAuthorPage(
        [for (var i = 1; i <= 600; i++) author(i)],
        hasMore: true,
        nextCursor: 'next',
      ),
    );
    await settle();
    expect(
      container.read(provider).items,
      hasLength(DynamicAuthorsController.maxAuthors),
    );
    expect(container.read(provider).hasMore, isFalse);
  });

  test('account changes and disposal discard pending author reads', () async {
    await settle();
    final pending = repository.authorCalls.single;
    repository.scope = 'user:8';
    pending.result.complete(DynamicAuthorPage([author(1)], hasMore: false));
    await settle();
    expect(container.read(provider).items, isEmpty);
    // A replacement account has its own selection and cancellation owner.
    final next = dynamicAuthorsProvider('user:8');
    final subscription = container.listen(next, (_, _) {});
    await settle();
    final replacement = repository.authorCalls.last;
    subscription.close();
    await container.pump();
    expect(replacement.cancellation.isCancelled, isTrue);
    replacement.result.complete(DynamicAuthorPage([author(2)], hasMore: false));
    await settle();
  });

  test(
    'filtered feeds keep per-author cursors and discard disposed responses',
    () async {
      repository.deferFeeds = true;
      final firstProvider = dynamicAuthorFeedProvider((
        query: query,
        authorId: const UserId('1'),
      ));
      final firstSubscription = container.listen(firstProvider, (_, _) {});
      await settle();
      final firstCall = repository.feedCalls.single;
      firstCall.result.complete(
        const HomePage([], hasMore: true, nextCursor: 'author-one'),
      );
      await settle();
      final page = container.read(firstProvider.notifier).loadMore();
      final pending = repository.feedCalls.last;
      expect(pending.cursor, 'author-one');
      firstSubscription.close();
      await container.pump();
      expect(pending.cancellation.isCancelled, isTrue);
      final secondProvider = dynamicAuthorFeedProvider((
        query: query,
        authorId: const UserId('2'),
      ));
      container.listen(secondProvider, (_, _) {});
      await settle();
      final secondCall = repository.feedCalls.last;
      expect(secondCall.authorId, const UserId('2'));
      expect(secondCall.cursor, isNull);
      secondCall.result.complete(repository.content(query, const UserId('2')));
      await settle();
      pending.result.complete(repository.content(query, const UserId('1')));
      await page;
      expect(
        container.read(secondProvider).items.requireValue.first.title,
        '筛选 2 视频 1',
      );
    },
  );
}
