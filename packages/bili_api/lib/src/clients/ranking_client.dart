import 'dart:convert';

import '../api_client.dart';
import '../models.dart';
import '../models/ranking_models.dart';

final class RankingClient {
  RankingClient(this.api);
  final BiliApiClient api;
  static const _endpoint = 'ranking_regions';

  Future<List<ApiRankingRegion>> getRegions({
    ApiRequestContext? context,
  }) async {
    final data = await api.requestJson(
      Uri.https('api.bilibili.com', '/x/kv-frontend/namespace/data', {
        'appKey': '333.1339',
        'nscode': '10',
      }),
      _endpoint,
      context: context,
    );
    final config = _map(data['data']);
    final order = _decode(config['channel_list.popular_page_sort']);
    if (order is! List<Object?> || order.length > 128) _fail();
    final regions = <ApiRankingRegion>[];
    final seen = <String>{};
    for (final key in order) {
      if (key is! String || !RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(key)) {
        _fail();
      }
      final encoded = config['channel_list.$key'];
      // The website skips missing configuration entries, preserving sort order.
      if (encoded == null) continue;
      final region = _map(_decode(encoded));
      // PGC entries use season ranking endpoints rather than UGC ranking/v2.
      if (_number(region['seasonType'] ?? 0) > 0) continue;
      final tid = _number(region['tid'] ?? 0);
      // The all-site entry is provided by the application.
      if (tid == 0) continue;
      final name = region['name'];
      if (name is! String || name.trim().isEmpty || name.length > 128) _fail();
      final id = '$tid';
      if (seen.add(id)) regions.add(ApiRankingRegion(id: id, name: name));
    }
    if (regions.isEmpty) _fail();
    return List.unmodifiable(regions);
  }

  static Object? _decode(Object? value) {
    if (value is! String || value.length > 65536) _fail();
    try {
      return jsonDecode(value);
    } on FormatException {
      _fail();
    }
  }

  static Map<String, Object?> _map(Object? value) =>
      value is Map<String, Object?> ? value : _fail();

  static int _number(Object? value) {
    final number =
        value is int
            ? value
            : value is String && RegExp(r'^\d+$').hasMatch(value)
            ? int.tryParse(value)
            : null;
    if (number == null || number < 0) _fail();
    return number;
  }

  static Never _fail() =>
      throw const ApiFailure(ApiFailureCategory.protocol, _endpoint);
}
