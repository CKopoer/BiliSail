import 'dart:convert';
import 'dart:typed_data';

import '../models.dart';
import '../models/pgc_models.dart';
import '../risk_control.dart';

/// Pure bounded PGC metadata decoding, safe to run in a worker isolate.
ApiPgcSeason decodePgcSeasonBytes(Uint8List bytes) {
  const endpoint = 'pgc_season';
  if (bytes.length > 4 * 1024 * 1024) {
    throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
  }
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
  }
  final root = _map(decoded, endpoint);
  if (hasRiskVoucher(root)) {
    throw const ApiFailure(
      ApiFailureCategory.rateLimited,
      endpoint,
      requiresVerification: true,
    );
  }
  final code = _int(root['code']);
  if (code == null) {
    throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
  }
  if (code != 0) {
    throw ApiFailure(
      switch (code) {
        -101 || -111 || -400 => ApiFailureCategory.authentication,
        -403 || -404 => ApiFailureCategory.permission,
        -412 || -352 || -509 || -799 => ApiFailureCategory.rateLimited,
        62002 || 62004 => ApiFailureCategory.notFound,
        _ => ApiFailureCategory.unavailable,
      },
      endpoint,
      businessCode: code,
    );
  }
  return parsePgcSeasonData(_map(root['data'] ?? root['result'], endpoint));
}

ApiPgcSeason parsePgcSeasonData(Map<String, Object?> data) {
  const endpoint = 'pgc_season';
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
  for (final value in _list(data['seasons'] ?? const [], endpoint).take(100)) {
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
  final progress = _mapOrEmpty(_mapOrEmpty(data['user_status'])['progress']);
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
    lastEpisodeId: _optionalId(progress['last_ep_id']),
    // Season history uses seconds, unlike player/v2's milliseconds.
    lastPosition: switch (_int(progress['last_time'])) {
      final seconds? when seconds >= -1 && seconds <= 7 * 24 * 60 * 60 =>
        Duration(seconds: seconds < 0 ? 0 : seconds),
      _ => null,
    },
  );
}

ApiPgcEpisode _episode(Map<String, Object?> data, String? section) {
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
    permissionText: areaLimited
        ? '地区限制'
        : !listed
        ? '暂不可播'
        : badge,
  );
}

Map<String, Object?> _map(Object? value, String endpoint) =>
    value is Map<String, Object?>
    ? value
    : throw ApiFailure(ApiFailureCategory.protocol, endpoint);
Map<String, Object?> _mapOrEmpty(Object? value) =>
    value is Map<String, Object?> ? value : const {};
List<Object?> _list(Object? value, String endpoint) => value is List
    ? value
    : throw ApiFailure(ApiFailureCategory.protocol, endpoint);
String _id(Object? value, String endpoint) {
  final id = _optionalId(value);
  if (id == null) throw ApiFailure(ApiFailureCategory.protocol, endpoint);
  return id;
}

String? _optionalId(Object? value) {
  final text = value is int
      ? '$value'
      : value is String
      ? value
      : null;
  return text != null && RegExp(r'^[1-9][0-9]*$').hasMatch(text) ? text : null;
}

int? _int(Object? value) => value is int
    ? value
    : value is String
    ? int.tryParse(value)
    : null;
double? _double(Object? value) => value is num
    ? value.toDouble()
    : value is String
    ? double.tryParse(value)
    : null;
String? _text(Object? value) =>
    value is String && value.isNotEmpty ? value : null;
String _requiredText(Object? value, String endpoint) =>
    _text(value) ?? (throw ApiFailure(ApiFailureCategory.protocol, endpoint));
Uri? _uri(Object? value) {
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
