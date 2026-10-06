import '../api_client.dart';
import '../models.dart';

/// One Web history snapshot; progress and duration use seconds on the wire.
final class ApiWatchHistoryEntry {
  const ApiWatchHistoryEntry({
    required this.bvid,
    required this.title,
    required this.coverUrl,
    required this.author,
    required this.duration,
    required this.cid,
    required this.page,
    required this.partTitle,
    required this.position,
    required this.watchedAt,
    this.authorMid,
    this.authorAvatarUrl,
    this.episodeId,
  });
  final String bvid, title, author, cid, partTitle;
  final Uri? coverUrl, authorAvatarUrl;
  final String? authorMid, episodeId;
  final int page;
  final Duration duration, position;
  final DateTime watchedAt;
}

final class WatchHistoryClient {
  const WatchHistoryClient(this.api);
  final BiliApiClient api;
  static const _endpoint = 'watch_history';

  Future<ApiPage<ApiWatchHistoryEntry>> load({
    String? cursor,
    ApiRequestContext? context,
  }) async {
    final parts = cursor?.split(':');
    if (parts != null &&
        (parts.length != 3 ||
            !_decimal.hasMatch(parts[0]) ||
            !_decimal.hasMatch(parts[1]) ||
            !RegExp(r'^[a-z_]*$').hasMatch(parts[2]))) {
      throw ArgumentError.value(cursor, 'cursor');
    }
    final data = await api.requestJson(
      Uri.https('api.bilibili.com', '/x/web-interface/history/cursor', {
        'ps': '20',
        'max': parts?[0] ?? '0',
        'view_at': parts?[1] ?? '0',
        'business': parts?[2] ?? '',
      }),
      _endpoint,
      context: context,
    );
    final list = data['list'];
    if (list is! List<Object?> || list.length > 20) _protocol();
    final items = <ApiWatchHistoryEntry>[];
    for (final raw in list) {
      final item = _map(raw);
      final history = _map(item['history']);
      final business = history['business'];
      // Live/article histories have their own destinations, outside this page.
      if (business != 'archive' && business != 'pgc') continue;
      final bvid = history['bvid'] is String ? history['bvid'] as String : '';
      final episodeId = business == 'pgc' ? _id(history['epid']) : null;
      if (business == 'pgc' && episodeId == null ||
          business == 'archive' &&
              !RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(bvid)) {
        _protocol();
      }
      final title = item['title'];
      final timestamp = _integer(item['view_at']);
      final seconds = _integer(item['duration']);
      final progress = _integer(item['progress']);
      if (title is! String ||
          title.trim().isEmpty ||
          timestamp == null ||
          timestamp <= 0 ||
          timestamp > 253402300799 ||
          seconds == null ||
          seconds < 0 ||
          progress == null ||
          progress < -1) {
        _protocol();
      }
      final duration = Duration(seconds: seconds);
      final cid = _id(history['cid']) ?? '';
      items.add(
        ApiWatchHistoryEntry(
          bvid: bvid,
          title: title,
          coverUrl: _uri(item['cover']),
          author: item['author_name'] is String
              ? item['author_name'] as String
              : '',
          authorMid: _id(item['author_mid']),
          authorAvatarUrl: _uri(item['author_face']),
          duration: duration,
          cid: cid,
          page: (_integer(history['page']) ?? 1).clamp(1, 100000),
          partTitle: history['part'] is String ? history['part'] as String : '',
          position: progress == -1
              ? duration
              : Duration(seconds: progress.clamp(0, seconds)),
          watchedAt: DateTime.fromMillisecondsSinceEpoch(
            timestamp * 1000,
            isUtc: true,
          ),
          episodeId: episodeId,
        ),
      );
    }
    if (list.isEmpty) return const ApiPage([], hasMore: false);
    final next = _map(data['cursor']);
    final max = _decimalId(next['max']);
    final viewAt = _decimalId(next['view_at']);
    final business = next['business'];
    if (max == null ||
        viewAt == null ||
        business is! String ||
        !RegExp(r'^[a-z_]*$').hasMatch(business)) {
      _protocol();
    }
    final nextCursor = '$max:$viewAt:$business';
    final hasMore = max != '0';
    if (hasMore && nextCursor == cursor) _protocol();
    return ApiPage(
      List.unmodifiable(items),
      hasMore: hasMore,
      nextCursor: hasMore ? nextCursor : null,
    );
  }

  static final _decimal = RegExp(r'^(0|[1-9][0-9]*)$');
  static String? _decimalId(Object? value) {
    final text = value is String
        ? value
        : value is int
        ? '$value'
        : null;
    return text != null && _decimal.hasMatch(text) ? text : null;
  }

  static String? _id(Object? value) {
    final text = _decimalId(value);
    return text == '0' ? null : text;
  }

  static int? _integer(Object? value) => value is int
      ? value
      : value is String
      ? int.tryParse(value)
      : null;
  static Uri? _uri(Object? value) {
    if (value is! String || value.isEmpty) return null;
    final uri = Uri.tryParse(value.startsWith('//') ? 'https:$value' : value);
    return uri != null &&
            (uri.scheme == 'https' || uri.scheme == 'http') &&
            uri.host.isNotEmpty
        ? uri
        : null;
  }

  static Map<String, Object?> _map(Object? value) =>
      value is Map<String, Object?> ? value : _protocol();
  static Never _protocol() =>
      throw const ApiFailure(ApiFailureCategory.protocol, _endpoint);
}
