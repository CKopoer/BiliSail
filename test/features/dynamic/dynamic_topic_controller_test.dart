import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/dynamic/application/dynamic_topic_controller.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_topic_repository.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/dynamic_fakes.dart';
import '../../support/dynamic_topic_fakes.dart';

void main() {
  late ProviderContainer container;
  late DynamicTopicRepositoryFake repository;
  late DynamicAuthFake auth;
  var started = false;
  final provider = dynamicTopicProvider('12');
  Future<void> flush() async {
    if (!started) {
      container.listen(provider, (_, _) {});
      started = true;
    }
    await Future<void>.delayed(Duration.zero);
    await container.pump();
  }

  setUp(() {
    repository = DynamicTopicRepositoryFake();
    auth = DynamicAuthFake();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        dynamicTopicRepositoryProvider.overrideWithValue(repository),
      ],
    );
    started = false;
  });
  tearDown(() async {
    container.dispose();
    await auth.stream.close();
  });

  test('favorite serializes writes and updates server-backed count only on success', () async {
    await flush();
    final pending = Completer<void>();
    repository.onWrite = (_) => pending.future;
    final controller = container.read(provider.notifier);
    final action = controller.toggleFavorite();
    expect(await controller.toggleFavorite(), isFalse);
    await controller.refresh();
    expect(repository.details, hasLength(1));
    expect(container.read(provider).detail?.isFavorite, isFalse);
    pending.complete();
    expect(await action, isTrue);
    expect(
      (
        container.read(provider).detail?.isFavorite,
        container.read(provider).detail?.favoriteCount,
      ),
      (true, 1),
    );
    repository.onWrite = null;
    expect(await controller.toggleFavorite(), isTrue);
    expect(container.read(provider).detail?.favoriteCount, 0);
  });

  test(
    'uncertain favorite blocks replay until a successful header refresh',
    () async {
      await flush();
      repository.onWrite = (_) async => throw const DynamicWriteUncertain();
      final controller = container.read(provider.notifier);
      expect(await controller.toggleFavorite(), isFalse);
      expect(await controller.toggleFavorite(), isFalse);
      expect(repository.favorites, hasLength(1));
      expect(container.read(provider).favoriteUncertain, isTrue);
      repository.onWrite = null;
      await controller.refresh();
      expect(container.read(provider).favoriteUncertain, isFalse);
      expect(await controller.toggleFavorite(), isTrue);
    },
  );

  test('report has guest protection, preserves raw reason and prevents duplicate submission', () async {
    await flush();
    final controller = container.read(provider.notifier);
    expect(await controller.report('广告：&+=%/#'), isTrue);
    expect(repository.reports.single, ('12', '广告：&+=%/#'));
    expect(await controller.report('广告'), isFalse);
    auth.change(const AuthState());
    await flush();
    expect(await controller.report('广告'), isFalse);
    expect(await controller.toggleFavorite(), isFalse);
    expect(repository.reports, hasLength(1));
  });

  test('account change cancels a write and ignores its late success', () async {
    await flush();
    final pending = Completer<void>();
    repository.onWrite = (_) => pending.future;
    final action = container.read(provider.notifier).toggleFavorite();
    repository.sessionEpoch++;
    repository.accountScope = 'user:8';
    auth.change(const AuthState(status: AuthStatus.signedIn, mid: '8'));
    await flush();
    pending.complete();
    expect(await action, isFalse);
    expect(container.read(provider).detail?.isFavorite, isFalse);
    expect(container.read(provider).actionBusy, isFalse);
  });

  test('loads metadata and server sorts, deduplicates pages and preserves exact cursor', () async {
    repository.page = DynamicTopicPage(
      posts: [DynamicPost(id: '1')],
      hasMore: true,
      nextCursor: '页?#12',
      sorts: const [DynamicTopicSort(0, '综合'), DynamicTopicSort(2, '最新')],
    );
    await flush();
    expect(container.read(provider).detail?.name, '应用内话题');
    repository.page = DynamicTopicPage(
      posts: [
        DynamicPost(id: '1', text: '更新'),
        DynamicPost(id: '2'),
      ],
      hasMore: false,
    );
    await container.read(provider.notifier).loadMore();
    expect(repository.queries.last.cursor, '页?#12');
    expect(container.read(provider).posts.map((p) => p.id), ['1', '2']);
    expect(container.read(provider).posts.first.text, '更新');
    expect(container.read(provider).sorts, hasLength(2));
  });

  test('sort cancels the old page and ignores its late response', () async {
    repository.page = DynamicTopicPage(
      posts: [DynamicPost(id: '1')],
      hasMore: true,
      nextCursor: 'next',
      sorts: const [DynamicTopicSort(0, '综合'), DynamicTopicSort(2, '最新')],
    );
    await flush();
    final pending = Completer<DynamicTopicPage>();
    repository.onFeed = (q) => q.sort == 0
        ? pending.future
        : Future.value(
            DynamicTopicPage(posts: [DynamicPost(id: '3')], hasMore: false),
          );
    final old = container.read(provider.notifier).loadMore();
    await flush();
    final oldRequest = repository.queries.last;
    await container.read(provider.notifier).selectSort(2);
    expect(oldRequest.cancellation.isCancelled, isTrue);
    pending.complete(
      DynamicTopicPage(posts: [DynamicPost(id: '2')], hasMore: false),
    );
    await old;
    expect(container.read(provider).sort, 2);
    expect(container.read(provider).posts.single.id, '3');
    expect(repository.queries.last.cursor, isNull);
    expect(repository.details, hasLength(1));
  });

  test(
    'account changes discard pending public and private state and late results',
    () async {
      final pending = Completer<DynamicTopicPage>();
      repository.onFeed = (_) => pending.future;
      await flush();
      final old = repository.queries.single;
      repository.accountScope = 'user:8';
      repository.sessionEpoch++;
      repository.onFeed = (_) async =>
          DynamicTopicPage(posts: [DynamicPost(id: '8')], hasMore: false);
      auth.change(const AuthState(status: AuthStatus.signedIn, mid: '8'));
      await flush();
      expect(old.cancellation.isCancelled, isTrue);
      pending.complete(
        DynamicTopicPage(posts: [DynamicPost(id: '7')], hasMore: false),
      );
      await flush();
      expect(container.read(provider).posts.single.id, '8');
    },
  );

  test('repeated cursors and pages stop automatic loading and retain retry identity', () async {
    repository.page = DynamicTopicPage(
      posts: [DynamicPost(id: '1')],
      hasMore: true,
      nextCursor: 'same',
    );
    await flush();
    await container.read(provider.notifier).loadMore();
    expect(container.read(provider).error, isA<AppFailure>());
    expect(container.read(provider).posts.single.id, '1');
    repository.page = DynamicTopicPage(
      posts: [DynamicPost(id: '2')],
      hasMore: false,
    );
    await container.read(provider.notifier).retry();
    expect(repository.queries.last.cursor, 'same');
    expect(container.read(provider).posts.map((p) => p.id), ['1', '2']);
  });

  test(
    'classified read failure is visible and an initial retry reloads metadata',
    () async {
      repository.onFeed = (_) async =>
          throw const AppFailure(AppFailureKind.permission, '没有访问权限');
      await flush();
      expect(
        container.read(provider).error,
        isA<AppFailure>().having((e) => e.message, 'message', '没有访问权限'),
      );
      repository.onFeed = null;
      await container.read(provider.notifier).retry();
      expect(container.read(provider).error, isNull);
      expect(repository.details, hasLength(2));
      expect(container.read(provider).posts.single.text, '话题动态');
    },
  );

  test('folded content is explicitly requested once and merges without changing pagination', () async {
    repository.page = DynamicTopicPage(
      posts: [DynamicPost(id: '1')],
      hasMore: true,
      nextCursor: 'next',
      foldDescription: '展开折叠内容',
    );
    await flush();
    repository.onFeed = (q) async => DynamicTopicPage(
      posts: [DynamicPost(id: q.folded ? '2' : '3')],
      hasMore: false,
    );
    await container.read(provider.notifier).loadFolded();
    await container.read(provider.notifier).loadFolded();
    expect(repository.queries.where((q) => q.folded), hasLength(1));
    expect(container.read(provider).posts.map((p) => p.id), ['1', '2']);
    expect(container.read(provider).foldDescription, isEmpty);
    await container.read(provider.notifier).loadMore();
    expect(repository.queries.last.cursor, 'next');
  });

  test('capacity is bounded and disposing cancels unfinished reads', () async {
    repository.page = DynamicTopicPage(
      posts: List.generate(600, (i) => DynamicPost(id: '${i + 1}')),
      hasMore: true,
      nextCursor: 'next',
    );
    await flush();
    expect(container.read(provider).posts, hasLength(500));
    expect(container.read(provider).hasMore, isFalse);
    final pending = Completer<DynamicTopicPage>();
    repository.onFeed = (_) => pending.future;
    final refresh = container.read(provider.notifier).refresh();
    await flush();
    final request = repository.queries.last.cancellation;
    container.dispose();
    expect(request.isCancelled, isTrue);
    pending.complete(DynamicTopicPage(posts: [], hasMore: false));
    await refresh;
    // tearDown owns its own empty container after the explicit lifetime test.
    container = ProviderContainer();
  });
}
