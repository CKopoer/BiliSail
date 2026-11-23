import 'dart:async';
import 'dart:convert';
import 'decoding/pgc_season_decoder.dart';
import 'mappers/dash_audio_parser.dart';
import 'models.dart';
import 'models/pgc_models.dart';
import 'transport.dart';

/// Resolver regions in BBZQ's default trial order.
enum PgcResolverRegion {
  hk('hk'),
  tw('tw'),
  sea('th'),
  cn('cn');

  const PgcResolverRegion(this.areaCode);

  /// The area query value expected by the resolver server.
  final String areaCode;

  static PgcResolverRegion? tryParse(String? value) {
    switch (value?.trim().toUpperCase()) {
      case 'HK' || 'MO' || 'HK/MO':
        return PgcResolverRegion.hk;
      case 'TW':
        return PgcResolverRegion.tw;
      case 'SEA' || 'TH' || 'INTL':
        return PgcResolverRegion.sea;
      case 'CN':
        return PgcResolverRegion.cn;
      default:
        return null;
    }
  }
}

/// Anonymous, bounded access to user-configured PGC resolver servers.
///
/// A null result means that no configured candidate yielded valid media. The
/// caller can then retain the official refusal. Cancellation and an exhausted
/// operation deadline are thrown instead of being mistaken for an empty reply.
final class PgcResolver {
  PgcResolver({
    Map<PgcResolverRegion, Uri> servers = const {},
    this.defaultRegion,
    ApiTransport? transport,
    this.timeout = const Duration(seconds: 10),
    DateTime Function()? clock,
  }) : servers = _validateServers(servers),
       _transport = transport ?? DioApiTransport(),
       _ownsTransport = transport == null,
       _clock = clock ?? DateTime.now {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive');
    }
  }

  /// One base URL per region. HTTP is allowed for a user's local resolver.
  /// Embedded credentials, queries and fragments are deliberately rejected.
  final Map<PgcResolverRegion, Uri> servers;
  final PgcResolverRegion? defaultRegion;

  /// Total budget for one detail or play resolution, shared by all candidates.
  final Duration timeout;
  final ApiTransport _transport;
  final bool _ownsTransport;
  final DateTime Function() _clock;
  bool _closed = false;

  static const _seasonEndpoint = 'pgc_resolver_season';
  static const _playEndpoint = 'pgc_resolver_playurl';
  static const _seasonMaxBytes = 4 * 1024 * 1024;
  static const _playMaxBytes = 2 * 1024 * 1024;
  static const _anonymousHeaders = <String, String>{
    'Accept': 'application/json',
    'User-Agent': 'Mozilla/5.0',
    'Referer': 'https://www.bilibili.com/',
  };

  void close() {
    if (_closed) return;
    _closed = true;
    if (_ownsTransport && _transport is DioApiTransport) {
      (_transport).close();
    }
  }

  Future<ApiPgcSeason?> resolveSeason({
    String? seasonId,
    String? episodeId,
    bool requireEpisodes = false,
    ApiRequestContext? context,
  }) async {
    if (seasonId == null && episodeId == null) {
      throw ArgumentError('A season or episode ID is required');
    }
    if (seasonId != null) _validateId(seasonId);
    if (episodeId != null) _validateId(episodeId);
    final deadline = _deadline(context);
    for (final region in _orderedRegions()) {
      final parameters = <String, String>{
        'season_id': ?seasonId,
        'ep_id': ?episodeId,
        'area': region.areaCode,
      };
      for (final path in _seasonPaths(region)) {
        _checkActive(context, deadline, _seasonEndpoint);
        try {
          final data = await _requestEnvelope(
            _uriFor(servers[region]!, path, parameters),
            _seasonEndpoint,
            _seasonMaxBytes,
            context,
            deadline,
          );
          // App season responses can keep section episodes under modules.
          final modules = _mapOrEmpty(data['modules']);
          final sections = data['section'];
          final season = parsePgcSeasonData(<String, Object?>{
            ...data,
            'episodes': data['episodes'] ?? const <Object?>[],
            'section': sections is List && sections.isNotEmpty
                ? sections
                : modules['section'] ?? sections ?? const <Object?>[],
          });
          if (requireEpisodes && season.episodes.isEmpty) continue;
          _checkActive(context, deadline, _seasonEndpoint);
          return season;
        } on ApiFailure catch (error) {
          if (error.category == ApiFailureCategory.cancelled) rethrow;
          // A refused, malformed or unreachable candidate does not erase the
          // official error; the remaining paths and regions may still work.
        }
      }
    }
    _checkActive(context, deadline, _seasonEndpoint);
    return null;
  }

  Future<ApiPlayInfo?> resolvePlayInfo(
    String episodeId, {
    int qn = 80,
    ApiRequestContext? context,
  }) async {
    _validateId(episodeId);
    if (qn < 1 || qn > 30000) throw ArgumentError.value(qn, 'qn');
    final deadline = _deadline(context);
    for (final region in _orderedRegions()) {
      // These are the anonymous parameters used by BBZQ's resolver replay.
      // In particular, do not add access_key or copy the Web Cookie header.
      final parameters = <String, String>{
        'ep_id': episodeId,
        'qn': '$qn',
        'fnval': '4048',
        'fnver': '0',
        'fourk': '1',
        'force_host': '2',
        'module': 'bangumi',
        'platform': 'android',
        'mobi_app': 'android',
        'device': 'android',
        'area': region.areaCode,
      };
      for (final path in _playPaths(region)) {
        _checkActive(context, deadline, _playEndpoint);
        try {
          final data = await _requestEnvelope(
            _uriFor(servers[region]!, path, parameters),
            _playEndpoint,
            _playMaxBytes,
            context,
            deadline,
          );
          final info = parsePgcPlayInfo(data);
          _checkActive(context, deadline, _playEndpoint);
          return info;
        } on ApiFailure catch (error) {
          if (error.category == ApiFailureCategory.cancelled) rethrow;
        }
      }
    }
    _checkActive(context, deadline, _playEndpoint);
    return null;
  }

  List<PgcResolverRegion> _orderedRegions() {
    final regions = PgcResolverRegion.values
        .where((region) => servers.containsKey(region))
        .toList();
    final preferred = defaultRegion;
    if (preferred != null && regions.remove(preferred)) {
      regions.insert(0, preferred);
    }
    return regions;
  }

  DateTime _deadline(ApiRequestContext? context) {
    final own = _clock().add(timeout);
    final supplied = context?.deadline;
    return supplied != null && supplied.isBefore(own) ? supplied : own;
  }

  void _checkActive(
    ApiRequestContext? context,
    DateTime deadline,
    String endpoint,
  ) {
    if (context?.cancellation?.isCancelled == true) {
      throw ApiFailure(ApiFailureCategory.cancelled, endpoint);
    }
    if (!deadline.isAfter(_clock())) {
      throw ApiFailure(ApiFailureCategory.timeout, endpoint);
    }
  }

  Future<Map<String, Object?>> _requestEnvelope(
    Uri uri,
    String endpoint,
    int maxBytes,
    ApiRequestContext? context,
    DateTime deadline,
  ) async {
    final response = await _read(uri, endpoint, maxBytes, context, deadline);
    _checkActive(context, deadline, endpoint);
    if (response.body.length > maxBytes) {
      throw ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiFailure(
        response.statusCode == 429
            ? ApiFailureCategory.rateLimited
            : ApiFailureCategory.http,
        endpoint,
        httpStatus: response.statusCode,
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.body));
    } on FormatException {
      throw ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    final root = _map(decoded, endpoint);
    final code = _int(root['code']);
    if (code == null) {
      throw ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    if (code != 0) {
      throw ApiFailure(
        switch (code) {
          -101 || -111 || -400 => ApiFailureCategory.authentication,
          -403 ||
          -404 ||
          -10403 ||
          -10404 ||
          -10493 ||
          6002003 => ApiFailureCategory.permission,
          -412 || -352 || -509 || -799 => ApiFailureCategory.rateLimited,
          62002 || 62004 => ApiFailureCategory.notFound,
          _ => ApiFailureCategory.unavailable,
        },
        endpoint,
        businessCode: code,
      );
    }
    return _map(root['result'] ?? root['data'], endpoint);
  }

  Future<ApiHttpResponse> _read(
    Uri uri,
    String endpoint,
    int maxBytes,
    ApiRequestContext? context,
    DateTime deadline,
  ) async {
    _checkActive(context, deadline, endpoint);
    final remaining = deadline.difference(_clock());
    final attempt = ApiCancellation();
    final removeListener = context?.cancellation?.onCancel(attempt.cancel);
    try {
      final transport = _transport;
      final read = transport is ApiBoundedTransport
          ? (transport as ApiBoundedTransport).getBounded(
              uri,
              headers: _anonymousHeaders,
              timeout: remaining,
              maxBytes: maxBytes,
              cancellation: attempt,
            )
          : transport.get(
              uri,
              headers: _anonymousHeaders,
              timeout: remaining,
              cancellation: attempt,
            );
      return await Future.any<ApiHttpResponse>([
        read,
        attempt.whenCancelled.then<ApiHttpResponse>(
          (_) => throw ApiFailure(ApiFailureCategory.cancelled, endpoint),
        ),
      ]).timeout(remaining);
    } on TimeoutException {
      attempt.cancel();
      throw ApiFailure(ApiFailureCategory.timeout, endpoint);
    } on ApiFailure catch (error) {
      attempt.cancel();
      if (context?.cancellation?.isCancelled == true) {
        throw ApiFailure(ApiFailureCategory.cancelled, endpoint);
      }
      throw ApiFailure(
        error.category,
        endpoint,
        httpStatus: error.httpStatus,
        businessCode: error.businessCode,
        retryAfter: error.retryAfter,
        requiresVerification: error.requiresVerification,
      );
    } on Exception {
      attempt.cancel();
      if (context?.cancellation?.isCancelled == true) {
        throw ApiFailure(ApiFailureCategory.cancelled, endpoint);
      }
      throw ApiFailure(ApiFailureCategory.network, endpoint);
    } finally {
      removeListener?.call();
    }
  }

  static Map<PgcResolverRegion, Uri> _validateServers(
    Map<PgcResolverRegion, Uri> servers,
  ) {
    final normalized = <PgcResolverRegion, Uri>{};
    for (final entry in servers.entries) {
      final uri = entry.value;
      if (!uri.isAbsolute ||
          !(uri.scheme == 'https' || uri.scheme == 'http') ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment) {
        throw ArgumentError.value(
          uri,
          'servers',
          'Resolver URLs must be credential-free absolute HTTP(S) base URLs',
        );
      }
      final path = uri.path.isEmpty
          ? '/'
          : uri.path.endsWith('/')
          ? uri.path
          : '${uri.path}/';
      normalized[entry.key] = uri.replace(path: path);
    }
    return Map<PgcResolverRegion, Uri>.unmodifiable(normalized);
  }

  static Uri _uriFor(Uri base, String path, Map<String, String> parameters) =>
      base.replace(
        path: '${base.path}${path.replaceFirst(RegExp(r'^/+'), '')}',
        queryParameters: parameters,
      );

  static List<String> _seasonPaths(PgcResolverRegion region) =>
      region == PgcResolverRegion.sea
      ? const [
          '/pgc/view/v2/app/season',
          '/pgc/view/web/season',
          '/intl/gateway/v2/ogv/view/app/season',
        ]
      : const ['/pgc/view/v2/app/season', '/pgc/view/web/season'];

  static List<String> _playPaths(PgcResolverRegion region) =>
      region == PgcResolverRegion.sea
      ? const [
          '/pgc/player/web/playurl',
          '/intl/gateway/v2/ogv/playurl',
          '/pgc/player/api/playurl',
        ]
      : const ['/pgc/player/api/playurl', '/pgc/player/web/playurl'];

  static void _validateId(String value) {
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(value)) {
      throw ArgumentError('Invalid PGC ID');
    }
  }
}

/// Shared official/resolver play mapping so both paths expose identical tracks.
ApiPlayInfo parsePgcPlayInfo(Map<String, Object?> data) {
  const endpoint = 'pgc_playurl';
  final wrapped = data['video_info'];
  final node = wrapped is Map<String, Object?> ? wrapped : data;
  final innerCode = _int(node['code']);
  if (innerCode != null && innerCode != 0) {
    throw ApiFailure(
      switch (innerCode) {
        -101 || -111 => ApiFailureCategory.authentication,
        -404 || 62002 || 62004 => ApiFailureCategory.notFound,
        -412 || -352 || -509 || -799 => ApiFailureCategory.rateLimited,
        _ => ApiFailureCategory.permission,
      },
      endpoint,
      businessCode: innerCode,
    );
  }
  final dash = _mapOrEmpty(node['dash']);
  if (dash.isEmpty) {
    throw const ApiFailure(ApiFailureCategory.unavailable, endpoint);
  }
  final videos = _list(
    dash['video'],
    endpoint,
  ).map((value) => _track(_map(value, endpoint))).toList();
  final audios = dashAudioEntries(dash, endpoint).map(_track).toList();
  if (videos.isEmpty || audios.isEmpty) {
    throw const ApiFailure(ApiFailureCategory.unavailable, endpoint);
  }
  final seconds = _double(dash['duration']);
  final durationMs = seconds == null
      ? _int(node['timelength']) ?? 0
      : (seconds * 1000).round();
  return ApiPlayInfo(
    pgcSkipSegments: _skipSegments(node, durationMs),
    duration: Duration(milliseconds: durationMs.clamp(0, 86400000)),
    dashVideo: List<ApiMediaTrack>.unmodifiable(videos),
    loudness: ApiAudioLoudness.parse(node['volume']),
    dashAudio: List<ApiMediaTrack>.unmodifiable(audios),
    isPreview: node['is_preview'] == true || _int(node['is_preview']) == 1,
    acceptQuality: List<int>.unmodifiable(
      _list(
        node['accept_quality'] ?? const <Object?>[],
        endpoint,
      ).map(_int).whereType<int>(),
    ),
  );
}

List<ApiPgcSkipSegment> _skipSegments(
  Map<String, Object?> data,
  int durationMs,
) {
  // Optional metadata must never prevent an otherwise playable DASH source.
  final raw = data['clip_info_list'];
  if (raw is! List ||
      data['is_preview'] == true ||
      _int(data['is_preview']) == 1) {
    return const [];
  }
  final result = <ApiPgcSkipSegment>[];
  for (final entry in raw.take(64)) {
    final clip = _mapOrEmpty(entry);
    final type = switch (clip['clipType']) {
      'CLIP_TYPE_OP' => ApiPgcSkipType.intro,
      'CLIP_TYPE_ED' => ApiPgcSkipType.outro,
      _ => null,
    };
    final start = _double(clip['start']);
    final end = _double(clip['end']);
    if (type == null ||
        start == null ||
        end == null ||
        !start.isFinite ||
        !end.isFinite ||
        start < 0 ||
        end <= start ||
        end * 1000 > durationMs) {
      continue;
    }
    final from = Duration(milliseconds: (start * 1000).round());
    final to = Duration(milliseconds: (end * 1000).round());
    if (to > from) result.add(ApiPgcSkipSegment(type, from, to));
  }
  return List<ApiPgcSkipSegment>.unmodifiable(result);
}

ApiMediaTrack _track(Map<String, Object?> data) {
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
    backupUrls: List<Uri>.unmodifiable(
      _list(
        data['backupUrl'] ?? data['backup_url'] ?? const <Object?>[],
        endpoint,
      ).map(_uri).whereType<Uri>(),
    ),
    bandwidth: _int(data['bandwidth']) ?? 0,
    mimeType: _text(data['mimeType'] ?? data['mime_type']) ?? '',
    codecs: _text(data['codecs']) ?? '',
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
