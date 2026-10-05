import '../api_client.dart';
import '../models.dart';
import '../models/pgc_models.dart';

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
    const endpoint = 'pgc_season';
    final data = await api.requestJson(
      Uri.https('api.bilibili.com', '/pgc/view/web/season', {
        if (seasonId != null) 'season_id': seasonId,
        if (episodeId != null) 'ep_id': episodeId,
      }),
      endpoint,
      context: context,
    );
    const maxEpisodes = 5000;
    final episodes = <ApiPgcEpisode>[];
    for (final value in _list(data['episodes'], endpoint).take(maxEpisodes)) {
      episodes.add(_episode(_map(value, endpoint), null));
    }
    for (final value in _list(data['section'] ?? const [], endpoint).take(30)) {
      if (episodes.length >= maxEpisodes) break;
      final section = _map(value, endpoint);
      final title = _text(section['title']);
      for (final item in _list(
        section['episodes'] ?? const [],
        endpoint,
      ).take(maxEpisodes - episodes.length)) {
        episodes.add(_episode(_map(item, endpoint), title));
      }
    }
    final related = <ApiPgcSeasonSummary>[];
    for (final value in _list(
      data['seasons'] ?? const [],
      endpoint,
    ).take(100)) {
      final item = _map(value, endpoint);
      related.add(
        ApiPgcSeasonSummary(
          seasonId: _id(item['season_id'], endpoint),
          title: _text(item['season_title'] ?? item['title']) ?? '',
          coverUrl: _uri(item['cover']),
        ),
      );
    }
    final rating = _mapOrEmpty(data['rating']);
    final stat = _mapOrEmpty(data['stat']);
    final publish = _mapOrEmpty(data['publish']);
    return ApiPgcSeason(
      seasonId: _id(data['season_id'], endpoint),
      title: _requiredText(data['title'] ?? data['season_title'], endpoint),
      coverUrl: _uri(data['cover']),
      description: _text(data['evaluate']) ?? '',
      type: _int(data['type'] ?? data['season_type']),
      episodes: List.unmodifiable(episodes),
      relatedSeasons: List.unmodifiable(related),
      rating: _double(rating['score']),
      playCount: _int(stat['views']),
      danmakuCount: _int(stat['danmakus']),
      followCount: _int(stat['favorites']),
      publishText: _text(publish['pub_time_show'] ?? publish['pub_time']),
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
    final videos =
        _list(
          dash['video'],
          endpoint,
        ).map((v) => _track(_map(v, endpoint))).toList();
    final audios =
        _list(dash['audio'], endpoint)
            .map((v) => _track(_map(v, endpoint)))
            .where((v) => v.codecs.toLowerCase().startsWith('mp4a'))
            .toList();
    if (videos.isEmpty || audios.isEmpty) {
      throw const ApiFailure(ApiFailureCategory.unavailable, endpoint);
    }
    final seconds = _double(dash['duration']);
    final durationMs =
        seconds == null
            ? _int(data['timelength']) ?? 0
            : (seconds * 1000).round();
    return ApiPlayInfo(
      duration: Duration(milliseconds: durationMs.clamp(0, 86400000)),
      dashVideo: List.unmodifiable(videos),
      dashAudio: List.unmodifiable(audios),
      acceptQuality: List.unmodifiable(
        _list(
          data['accept_quality'] ?? const [],
          endpoint,
        ).map(_int).whereType<int>(),
      ),
    );
  }

  static ApiPgcEpisode _episode(Map<String, Object?> data, String? section) {
    const endpoint = 'pgc_season';
    final status = _int(data['status']);
    final rights = _mapOrEmpty(data['rights']);
    final badge = _text(data['badge']);
    final areaLimited = _int(rights['area_limit']) == 1;
    // Status 13 can be a VIP episode. Playurl makes the entitlement decision.
    final listed = status != 0 && status != -1 && data['is_view_hide'] != true;
    return ApiPgcEpisode(
      episodeId: _optionalId(data['ep_id']) ?? _id(data['id'], endpoint),
      aid: _optionalId(data['aid']),
      bvid: _text(data['bvid']),
      cid: _optionalId(data['cid']),
      title: _text(data['title']) ?? '',
      longTitle: _text(data['long_title']) ?? '',
      coverUrl: _uri(data['cover']),
      // PGC listing duration is milliseconds, unlike UGC's seconds.
      duration: switch (_int(data['duration'])) {
        final int ms when ms >= 0 => Duration(milliseconds: ms),
        _ => null,
      },
      badge: badge,
      sectionTitle: section,
      playable: listed && !areaLimited,
      permissionText:
          areaLimited
              ? '地区限制'
              : !listed
              ? '暂不可播'
              : badge,
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
  static List<Object?> _list(Object? value, String endpoint) =>
      value is List
          ? value
          : throw ApiFailure(ApiFailureCategory.protocol, endpoint);
  static String _id(Object? value, String endpoint) {
    final id = _optionalId(value);
    if (id == null) throw ApiFailure(ApiFailureCategory.protocol, endpoint);
    return id;
  }

  static String? _optionalId(Object? value) {
    final text =
        value is int
            ? '$value'
            : value is String
            ? value
            : null;
    return text != null && RegExp(r'^[1-9][0-9]*$').hasMatch(text)
        ? text
        : null;
  }

  static int? _int(Object? value) =>
      value is int
          ? value
          : value is String
          ? int.tryParse(value)
          : null;
  static double? _double(Object? value) =>
      value is num
          ? value.toDouble()
          : value is String
          ? double.tryParse(value)
          : null;
  static String? _text(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
  static String _requiredText(Object? value, String endpoint) =>
      _text(value) ?? (throw ApiFailure(ApiFailureCategory.protocol, endpoint));
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
