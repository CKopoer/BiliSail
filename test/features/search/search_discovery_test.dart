import 'dart:async';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/search/application/search_discovery_controller.dart';
import 'package:bilisail/features/search/data/search_discovery_repository.dart';
import 'package:bilisail/features/search/domain/search_discovery_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('history persists, normalizes, bounds and isolates accounts; logout clears private history', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = SqliteSearchDiscoveryRepository(
      database,
      SearchClient(BiliApiClient()),
      ApiRequests(),
    );
    await repository.saveHistory('guest', [
      ' 游客 ',
      '游客',
      '',
      ...List.generate(60, (i) => '$i'),
    ]);
    expect((await repository.loadHistory('guest')).length, 50);
    expect((await repository.loadHistory('guest')).first, '游客');
    expect(await repository.loadHistory('user:1'), isEmpty);
    await repository.saveHistory('user:1', ['私有']);
    final reopened = SqliteSearchDiscoveryRepository(
      database,
      SearchClient(BiliApiClient()),
      ApiRequests(),
    );
    expect(await reopened.loadHistory('user:1'), ['私有']);
    await database.clearPrivateHistory('user:1');
    expect(await reopened.loadHistory('user:1'), isEmpty);
    expect((await reopened.loadHistory('guest')).first, '游客');
    final scoped = SqliteSearchDiscoveryRepository(
      database,
      SearchClient(BiliApiClient()),
      ApiRequests(),
      accountScope: () => 'guest',
    );
    expect(() => scoped.saveHistory('user:1', ['迟到写入']), throwsA(anything));
    expect(await scoped.loadHistory('user:1'), isEmpty);
  });

  test('concurrent submissions and clear serialize; failed save retains saved history', () async {
    final repository = _Repository();
    final container = ProviderContainer(
      overrides: [
        searchDiscoveryRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(
      searchDiscoveryControllerProvider.notifier,
    );
    await Future.wait([
      controller.remember(' 一 '),
      controller.remember('二'),
      controller.remember('一'),
    ]);
    expect(container.read(searchDiscoveryControllerProvider).history, [
      '一',
      '二',
    ]);
    repository.failSave = true;
    await controller.remember('失败');
    expect(container.read(searchDiscoveryControllerProvider).history, [
      '一',
      '二',
    ]);
    expect(
      container.read(searchDiscoveryControllerProvider).historyError,
      isTrue,
    );
    repository.failSave = false;
    await Future.wait([controller.remember('三'), controller.clearHistory()]);
    expect(container.read(searchDiscoveryControllerProvider).history, isEmpty);
    expect(await repository.loadHistory('guest'), isEmpty);
  });

  test(
    'account switch rejects late history and trends and cancels old request',
    () async {
      final scope = StateProvider<String>((ref) => 'guest');
      final repository = _Repository()..delayed = true;
      final container = ProviderContainer(
        overrides: [
          searchHistoryScopeProvider.overrideWith((ref) => ref.watch(scope)),
          searchDiscoveryRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(
        searchDiscoveryControllerProvider.notifier,
      );
      final loading = controller.loadTrending();
      await Future<void>.delayed(Duration.zero);
      container.read(scope.notifier).state = 'user:2';
      expect(
        container.read(searchDiscoveryControllerProvider).history,
        isEmpty,
      );
      await Future<void>.delayed(Duration.zero);
      expect(repository.cancellation?.isCancelled, isTrue);
      repository.oldHistory.complete(['旧账号']);
      repository.oldTrending.complete([
        const SearchTrend(keyword: '旧', label: '旧'),
      ]);
      await loading;
      expect(
        container.read(searchDiscoveryControllerProvider).history,
        isEmpty,
      );
      expect(
        container.read(searchDiscoveryControllerProvider).trending.value,
        isNull,
      );
    },
  );

  test('trends single flight, cache, failure and explicit retry', () async {
    final repository = _Repository()..failTrending = true;
    final container = ProviderContainer(
      overrides: [
        searchDiscoveryRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(
      searchDiscoveryControllerProvider.notifier,
    );
    await controller.loadTrending();
    expect(
      container.read(searchDiscoveryControllerProvider).trending.hasError,
      isTrue,
    );
    repository.failTrending = false;
    await Future.wait([
      controller.loadTrending(force: true),
      controller.loadTrending(force: true),
    ]);
    expect(
      container
          .read(searchDiscoveryControllerProvider)
          .trending
          .requireValue
          .single
          .keyword,
      '真实关键词',
    );
    await controller.loadTrending();
    expect(repository.trendCalls, 2);
  });

  test('failed history read cannot silently overwrite saved terms', () async {
    final repository = _Repository()..failLoad = true;
    await repository.memory.saveHistory('guest', ['原有历史']);
    final container = ProviderContainer(
      overrides: [
        searchDiscoveryRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(
      searchDiscoveryControllerProvider.notifier,
    );
    await controller.remember('新词');
    expect(await repository.memory.loadHistory('guest'), ['原有历史']);
    expect(
      container.read(searchDiscoveryControllerProvider).historyError,
      isTrue,
    );
    repository.failLoad = false;
    await controller.remember('新词');
    expect(container.read(searchDiscoveryControllerProvider).history, [
      '新词',
      '原有历史',
    ]);
  });
}

final class _Repository implements SearchDiscoveryRepository {
  final memory = MemorySearchDiscoveryRepository();
  bool failSave = false,
      failTrending = false,
      delayed = false,
      failLoad = false;
  int trendCalls = 0;
  RequestCancellation? cancellation;
  final oldHistory = Completer<List<String>>();
  final oldTrending = Completer<List<SearchTrend>>();
  @override
  Future<List<String>> loadHistory(String scope) {
    if (failLoad) throw StateError('disk read');
    return delayed && scope == 'guest'
        ? oldHistory.future
        : memory.loadHistory(scope);
  }

  @override
  Future<void> saveHistory(String scope, List<String> history) {
    if (failSave) throw StateError('disk');
    return memory.saveHistory(scope, history);
  }

  @override
  Future<List<SearchTrend>> loadTrending(
    RequestCancellation cancellation,
  ) async {
    this.cancellation = cancellation;
    trendCalls++;
    if (delayed) return oldTrending.future;
    if (failTrending) throw StateError('offline');
    return [const SearchTrend(keyword: '真实关键词', label: '展示标题')];
  }
}
