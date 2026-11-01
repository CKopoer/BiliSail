import 'dart:async';

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/search/application/search_discovery_controller.dart';
import 'package:bilisail/features/search/domain/search_discovery_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'suggestions debounce, cancel obsolete input and ignore late responses',
    (tester) async {
      final repository = _Repository();
      final container = ProviderContainer(
        overrides: [
          searchDiscoveryRepositoryProvider.overrideWithValue(repository),
        ],
      );
      final first = container.listen(
        searchSuggestionsProvider('旧词'),
        (_, _) {},
      );
      await tester.pump(const Duration(milliseconds: 299));
      expect(repository.calls, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(repository.calls, ['旧词']);
      first.close();
      final next = container.listen(searchSuggestionsProvider('新词'), (_, _) {});
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.cancellations.first.isCancelled, isTrue);
      expect(repository.calls, ['旧词', '新词']);
      repository.results[1].complete([
        ' 新候选 ',
        '新候选',
        ...List.generate(20, (i) => '$i'),
      ]);
      await tester.pump();
      expect(next.read().requireValue.length, 10);
      expect(next.read().requireValue.first, '新候选');
      repository.results[0].complete(['旧候选']);
      await tester.pump();
      expect(next.read().requireValue.first, '新候选');
      next.close();
      container.dispose();
    },
  );

  testWidgets(
    'clearing or dismissing within debounce prevents network access',
    (tester) async {
      final repository = _Repository();
      final container = ProviderContainer(
        overrides: [
          searchDiscoveryRepositoryProvider.overrideWithValue(repository),
        ],
      );
      final pending = container.listen(
        searchSuggestionsProvider('未完成'),
        (_, _) {},
      );
      pending.close();
      final empty = container.listen(
        searchSuggestionsProvider('  '),
        (_, _) {},
      );
      await tester.pump(const Duration(seconds: 1));
      expect(repository.calls, isEmpty);
      expect(empty.read().requireValue, isEmpty);
      empty.close();
      container.dispose();
    },
  );

  testWidgets(
    'account changes cancel old suggestions; failures can be retried',
    (tester) async {
      final repository = _Repository();
      final scope = StateProvider<String>((ref) => 'guest');
      final container = ProviderContainer(
        overrides: [
          searchHistoryScopeProvider.overrideWith((ref) => ref.watch(scope)),
          searchDiscoveryRepositoryProvider.overrideWithValue(repository),
        ],
      );
      final provider = searchSuggestionsProvider('词');
      final subscription = container.listen(provider, (_, _) {});
      await tester.pump(const Duration(milliseconds: 300));
      container.read(scope.notifier).state = 'user:2';
      container.read(provider);
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.cancellations.first.isCancelled, isTrue);
      repository.results.first.complete(['旧账号']);
      repository.results[1].completeError(StateError('offline'));
      await tester.pump();
      expect(subscription.read().hasError, isTrue);
      container.invalidate(provider);
      await tester.pump(const Duration(milliseconds: 300));
      repository.results[2].complete(['新账号']);
      await tester.pump();
      expect(subscription.read().requireValue, ['新账号']);
      subscription.close();
      container.dispose();
    },
  );
}

final class _Repository implements SearchDiscoveryRepository {
  final calls = <String>[];
  final cancellations = <RequestCancellation>[];
  final results = <Completer<List<String>>>[];

  @override
  Future<List<String>> loadSuggestions(
    String query,
    RequestCancellation cancellation,
  ) {
    calls.add(query);
    cancellations.add(cancellation);
    final result = Completer<List<String>>();
    results.add(result);
    return result.future;
  }

  @override
  Future<List<String>> loadHistory(String scope) async => [];
  @override
  Future<void> saveHistory(String scope, List<String> history) async {}
  @override
  Future<List<SearchTrend>> loadTrending(
    RequestCancellation cancellation,
  ) async => [];
}
