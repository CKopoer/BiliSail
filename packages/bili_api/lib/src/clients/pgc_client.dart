import '../api_client.dart';
import '../models.dart';
import '../models/pgc_models.dart';
import '../mappers/dash_audio_parser.dart';

/// Web Cookie PGC reads. Entitlement decisions remain with the playurl API.
final class PgcClient {
  const PgcClient(this.api);
  final BiliApiClient api;

  Future<ApiPgcSeason> getSeason({
    String? seasonId,
    String? episodeId,
    ApiRequestContext? context,
  }) async {
    if (seasonId == null && episodeId == null) {
      throw ArgumentError('A season or episode ID is required');
    }
    if (seasonId != null) _validateId(seasonId);
    if (episodeId != null) _validateId(episodeId);
    return api.requestPgcSeason(
      Uri.https('api.bilibili.com', '/pgc/view/web/season', {
        'season_id': ?seasonId,
        'ep_id': ?episodeId,
      }),
      context: context,
    );
  }

  Future<ApiPlayInfo> getPlayInfo(
    String episodeId, {
    int qn = 80,
    ApiRequestContext? context,
  }) async {
    _validateId(episodeId);
    if (qn < 1 || qn > 30000) throw ArgumentError.value(qn, 'qn');
    const endpoint = 'pgc_playurl';
    late final Map<String, Object?> data;
    try {
      data = await api.requestJson(
        Uri.https('api.bilibili.com', '/pgc/player/web/playurl', {
          'ep_id': episodeId,
          'qn': '$qn',
          'fnver': '0',
          'fnval': '4048',
          'fourk': '1',
          'module': 'bangumi',
          'voice_balance': '1',
        }),
        endpoint,
        context: context,
      );
    } on ApiFailure catch (error) {
      if (const {-10403, -10404}.contains(error.businessCode)) {
        throw ApiFailure(
          ApiFailureCategory.permission,
          endpoint,
          businessCode: error.businessCode,
        );
      }
      rethrow;
    }
    final innerCode = _int(data['code']);
    if (innerCode != null && innerCode != 0) {
      throw ApiFailure(
        switch (innerCode) {
          -101 || -111 => ApiFailureCategory.authentication,
          -404 || 62002 || 62004 => ApiFailureCategory.notFound,
          -412 || -352 => ApiFailureCategory.rateLimited,
          _ => ApiFailureCategory.permission,
        },
        endpoint,
        businessCode: innerCode,
      );
    }
    final dash = _mapOrEmpty(data['dash']);
    if (dash.isEmpty) {
      throw const ApiFailure(ApiFailureCategory.unavailable, endpoint);
    }
    final videos = _list(
      dash['video'],
      endpoint,
    ).map((v) => _track(_map(v, endpoint))).toList();
    final audios = dashAudioEntries(dash, endpoint).map(_track).toList();
    if (videos.isEmpty || audios.isEmpty) {
      throw const ApiFailure(ApiFailureCategory.unavailable, endpoint);
    }
    final seconds = _double(dash['duration']);
    final durationMs = seconds == null
        ? _int(data['timelength']) ?? 0
        : (seconds * 1000).round();
    return ApiPlayInfo(
      duration: Duration(milliseconds: durationMs.clamp(0, 86400000)),
      dashVideo: List.unmodifiable(videos),
      loudness: ApiAudioLoudness.parse(data['volume']),
      dashAudio: List.unmodifiable(audios),
      isPreview: data['is_preview'] == true || _int(data['is_preview']) == 1,
      acceptQuality: List.unmodifiable(
        _list(
          data['accept_quality'] ?? const [],
          endpoint,
        ).map(_int).whereType<int>(),
      ),
    );
  }

  static ApiMediaTrack _track(Map<String, Object?> data) {
    const endpoint = 'pgc_playurl';
    final uri = _uri(data['baseUrl'] ?? data['base_url']);
    if (uri == null) {
      throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    return ApiMediaTrack(
      id:
          _int(data['id']) ??
          (throw const ApiFailure(ApiFailureCategory.protocol, endpoint)),
      url: uri,
      backupUrls: List.unmodifiable(
        _list(
          data['backupUrl'] ?? data['backup_url'] ?? const [],
          endpoint,
        ).map(_uri).whereType<Uri>(),
      ),
      bandwidth: _int(data['bandwidth']) ?? 0,
      mimeType: _text(data['mimeType'] ?? data['mime_type']) ?? '',
      codecs: _text(data['codecs']) ?? '',
    );
  }

  static void _validateId(String value) {
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(value)) {
      throw ArgumentError('Invalid PGC ID');
    }
  }

  static Map<String, Object?> _map(Object? value, String endpoint) =>
      value is Map<String, Object?>
      ? value
      : throw ApiFailure(ApiFailureCategory.protocol, endpoint);
  static Map<String, Object?> _mapOrEmpty(Object? value) =>
      value is Map<String, Object?> ? value : const {};
  static List<Object?> _list(Object? value, String endpoint) => value is List
      ? value
      : throw ApiFailure(ApiFailureCategory.protocol, endpoint);
  static int? _int(Object? value) => value is int
      ? value
      : value is String
      ? int.tryParse(value)
      : null;
  static double? _double(Object? value) => value is num
      ? value.toDouble()
      : value is String
      ? double.tryParse(value)
      : null;
  static String? _text(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
  static Uri? _uri(Object? value) {
    if (value is! String || value.isEmpty || value.length > 8192) return null;
    final uri = Uri.tryParse(value.startsWith('//') ? 'https:$value' : value);
    if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
    if (uri.scheme == 'https') return uri;
    if (uri.scheme == 'http' &&
        (uri.host == 'hdslb.com' || uri.host.endsWith('.hdslb.com'))) {
      return uri.replace(scheme: 'https');
    }
    return null;
  }
}
