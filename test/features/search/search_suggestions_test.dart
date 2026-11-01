import 'dart:async';

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/search/application/search_discovery_controller.dart';
import 'package:bilisail/features/search/domain/search_discovery_repository.dart';
import 'package:bilisail/features/search/presentation/search_discovery_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'IME composition retains suggestions and requests only confirmed text',
    (tester) async {
      final repository = _Repository();
      final (text, _) = await _mountPanel(tester, repository);
      await tester.pump(const Duration(milliseconds: 300));
      repository.results[0].complete(['旧候选']);
      await tester.pumpAndSettle();
      text.value = const TextEditingValue(
        text: '旧词zhong',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 2, end: 7),
      );
      await tester.pumpAndSettle();
      expect(find.text('旧候选'), findsOneWidget);
      expect(find.text('搜索历史'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      text.value = const TextEditingValue(
        text: '旧词zhongw',
        selection: TextSelection.collapsed(offset: 8),
        composing: TextRange(start: 2, end: 8),
      );
      await tester.pumpAndSettle();
      expect(find.text('旧候选'), findsOneWidget);
      expect(repository.calls, ['旧词']);
      text.value = const TextEditingValue(
        text: '旧词中文',
        selection: TextSelection.collapsed(offset: 4),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 299));
      expect(repository.calls, ['旧词']);
      expect(find.text('旧候选'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(repository.calls, ['旧词', '旧词中文']);
      repository.results[1].complete(['中文候选']);
      await tester.pumpAndSettle();
      expect(find.text('中文候选'), findsOneWidget);
      expect(find.text('旧候选'), findsNothing);
    },
  );

  testWidgets(
    'IME composition cancels pending debounce and reads without losing suggestions',
    (tester) async {
      final repository = _Repository();
      final (text, _) = await _mountPanel(tester, repository);
      await tester.pump(const Duration(milliseconds: 300));
      repository.results[0].complete(['旧候选']);
      await tester.pumpAndSettle();
      text.text = '排队词';
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      text.value = const TextEditingValue(
        text: '排队词a',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 3, end: 4),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(repository.calls, ['旧词']);
      expect(find.text('旧候选'), findsOneWidget);

      text.value = const TextEditingValue(
        text: '新词',
        selection: TextSelection.collapsed(offset: 2),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.calls, ['旧词', '新词']);
      text.value = const TextEditingValue(
        text: '新词a',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 2, end: 3),
      );
      await tester.pumpAndSettle();
      expect(repository.cancellations[1].isCancelled, isTrue);
      repository.results[1].complete(['过期候选']);
      await tester.pumpAndSettle();
      expect(find.text('旧候选'), findsOneWidget);
      expect(find.text('过期候选'), findsNothing);
      text.clear();
      await tester.pumpAndSettle();
      expect(find.text('旧候选'), findsNothing);
      expect(find.text('搜索历史'), findsOneWidget);
    },
  );

  testWidgets(
    'panel retains suggestions through debounce, empty and failed reads until replacement',
    (tester) async {
      final repository = _Repository();
      final searches = <String>[];
      final (text, _) = await _mountPanel(
        tester,
        repository,
        searches: searches,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('暂无联想词，可直接提交搜索'), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      repository.results[0].complete(['旧候选']);
      await tester.pumpAndSettle();
      expect(find.text('旧候选'), findsOneWidget);

      text.text = '空词';
      await tester.pump();
      expect(find.text('旧候选'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.text('旧候选'));
      expect(searches, ['旧候选']);
      await tester.pump(const Duration(milliseconds: 299));
      expect(repository.calls, ['旧词']);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('旧候选'), findsOneWidget);
      repository.results[1].complete([]);
      await tester.pumpAndSettle();
      expect(find.text('旧候选'), findsOneWidget);
      expect(find.text('暂无联想词，可直接提交搜索'), findsNothing);

      text.text = '失败词';
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      repository.results[2].completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('旧候选'), findsOneWidget);
      expect(find.text('搜索联想暂时无法加载'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(find.text('旧候选'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      repository.results[3].complete(['新候选']);
      await tester.pumpAndSettle();
      expect(find.text('新候选'), findsOneWidget);
      expect(find.text('旧候选'), findsNothing);
      expect(find.text('搜索联想暂时无法加载'), findsNothing);
    },
  );

  testWidgets(
    'clearing input drops retained suggestions and cancels pending reads',
    (tester) async {
      final repository = _Repository();
      final (text, _) = await _mountPanel(tester, repository);
      await tester.pump(const Duration(milliseconds: 300));
      repository.results[0].complete(['旧候选']);
      await tester.pumpAndSettle();
      text.text = '未完成';
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      text.clear();
      await tester.pump();
      await tester.pump();
      expect(find.text('旧候选'), findsNothing);
      expect(find.text('搜索历史'), findsOneWidget);
      expect(repository.cancellations[1].isCancelled, isTrue);
      repository.results[1].complete(['迟到候选']);
      await tester.pumpAndSettle();
      text.text = '重新输入';
      await tester.pump();
      expect(find.text('旧候选'), findsNothing);
      expect(find.text('迟到候选'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      repository.results[2].complete([]);
      await tester.pumpAndSettle();
      expect(find.text('暂无联想词，可直接提交搜索'), findsOneWidget);
    },
  );

  testWidgets(
    'account switch clears retained suggestions and rejects late old-account results',
    (tester) async {
      final repository = _Repository();
      final scope = StateProvider<String>((ref) => 'guest');
      final (text, container) = await _mountPanel(
        tester,
        repository,
        scope: scope,
      );
      await tester.pump(const Duration(milliseconds: 300));
      repository.results[0].complete(['旧账号候选']);
      await tester.pumpAndSettle();
      text.text = '另一词';
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      container.read(scope.notifier).state = 'user:2';
      await tester.pump();
      expect(find.text('旧账号候选'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(repository.cancellations[1].isCancelled, isTrue);
      await tester.pump(const Duration(milliseconds: 300));
      repository.results[1].complete(['旧账号迟到候选']);
      await tester.pumpAndSettle();
      expect(find.text('旧账号迟到候选'), findsNothing);
      repository.results[2].complete(['新账号候选']);
      await tester.pumpAndSettle();
      expect(find.text('新账号候选'), findsOneWidget);
    },
  );

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
      await tester.pumpAndSettle();
      expect(next.read().requireValue.length, 10);
      expect(next.read().requireValue.first, '新候选');
      repository.results[0].complete(['旧候选']);
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
      expect(subscription.read().hasError, isTrue);
      container.invalidate(provider);
      await tester.pump(const Duration(milliseconds: 300));
      repository.results[2].complete(['新账号']);
      await tester.pumpAndSettle();
      expect(subscription.read().requireValue, ['新账号']);
      subscription.close();
      container.dispose();
    },
  );
}

Future<(TextEditingController, ProviderContainer)> _mountPanel(
  WidgetTester tester,
  _Repository repository, {
  List<String>? searches,
  StateProvider<String>? scope,
}) async {
  final text = TextEditingController(text: '旧词');
  final container = ProviderContainer(
    overrides: [
      searchDiscoveryRepositoryProvider.overrideWithValue(repository),
      if (scope != null)
        searchHistoryScopeProvider.overrideWith((ref) => ref.watch(scope)),
    ],
  );
  addTearDown(text.dispose);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SearchDiscoveryPanel(
            controller: text,
            onSearch: (query) => searches?.add(query),
          ),
        ),
      ),
    ),
  );
  return (text, container);
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
