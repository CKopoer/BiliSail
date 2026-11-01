import 'dart:convert';

import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../core/storage/app_database.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/search_discovery_repository.dart';

final class SqliteSearchDiscoveryRepository
    implements SearchDiscoveryRepository {
  SqliteSearchDiscoveryRepository(
    this.database,
    this.client,
    this.requests, {
    this.accountScope,
  });
  final AppDatabase database;
  final SearchClient client;
  final ApiRequests requests;
  final String Function()? accountScope;

  @override
  Future<List<String>> loadHistory(String scope) async {
    final raw = await database.readSetting('search_history.v1.$scope');
    if (raw == null) return const [];
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List<Object?>) {
      throw const FormatException('Invalid search history');
    }
    return normalizeSearchHistory(decoded.whereType<String>());
  }

  @override
  Future<void> saveHistory(String scope, List<String> history) {
    final currentScope = accountScope?.call();
    if (currentScope != null && currentScope != scope) {
      throw const AppFailure(AppFailureKind.cancelled, '账号已切换');
    }
    return database.writeSetting(
      'search_history.v1.$scope',
      jsonEncode(normalizeSearchHistory(history)),
    );
  }

  @override
  Future<List<SearchTrend>> loadTrending(RequestCancellation cancellation) =>
      requests.run(
        (context) async => [
          for (final item in await client.trending(context: context))
            SearchTrend(keyword: item.keyword, label: item.label),
        ],
        cancellation: cancellation,
      );
}

// Also provides a local-only host for isolated workspaces and widget tests.
final class MemorySearchDiscoveryRepository
    implements SearchDiscoveryRepository {
  final _history = <String, List<String>>{};
  @override
  Future<List<String>> loadHistory(String scope) async =>
      _history[scope] ?? const [];
  @override
  Future<void> saveHistory(String scope, List<String> history) async {
    _history[scope] = normalizeSearchHistory(history);
  }

  @override
  Future<List<SearchTrend>> loadTrending(
    RequestCancellation cancellation,
  ) async => const [];
}
