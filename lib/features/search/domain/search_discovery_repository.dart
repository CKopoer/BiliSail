import '../../../domain/request_cancellation.dart';

final class SearchTrend {
  const SearchTrend({required this.keyword, required this.label});
  final String keyword;
  final String label;
}

abstract interface class SearchDiscoveryRepository {
  Future<List<String>> loadHistory(String scope);
  Future<void> saveHistory(String scope, List<String> history);
  Future<List<SearchTrend>> loadTrending(RequestCancellation cancellation);
}

List<String> normalizeSearchHistory(Iterable<String> values) {
  final unique = <String>{};
  for (final value in values) {
    final text = value.trim();
    if (text.isNotEmpty && text.length <= 200) unique.add(text);
    if (unique.length == 50) break;
  }
  return List.unmodifiable(unique);
}
