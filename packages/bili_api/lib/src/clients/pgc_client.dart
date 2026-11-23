import '../api_client.dart';
import '../models.dart';
import '../models/pgc_models.dart';
import '../pgc_resolver.dart';

/// Web Cookie PGC metadata and follows. Playurl decides viewing entitlement.
final class PgcClient {
  const PgcClient(this.api, {this.resolver, this.resolverProvider});
  final BiliApiClient api;
  final PgcResolver? resolver;

  /// Optional live configuration source used by app settings. Fixed resolver
  /// injection remains convenient for tests and long-lived configurations.
  final Future<PgcResolver?> Function()? resolverProvider;

  Future<PgcResolver?> _resolver() async {
    final provider = resolverProvider;
    return provider == null ? resolver : await provider();
  }

  Future<bool> isFollowed(String seasonId, {ApiRequestContext? context}) async {
    _validateId(seasonId);
    const endpoint = 'pgc_follow_state';
    final data = await api.requestJson(
      Uri.https('api.bilibili.com', '/pgc/view/web/season/user/status', {
        'season_id': seasonId,
      }),
      endpoint,
      context: context,
    );
    return switch (data['follow']) {
      true || 1 || '1' => true,
      false || 0 || '0' => false,
      _ => throw const ApiFailure(ApiFailureCategory.protocol, endpoint),
    };
  }

  /// One explicit click sends one CSRF form; unknown results need a state read.
  Future<void> setFollowed(
    String seasonId,
    bool followed, {
    ApiRequestContext? context,
  }) async {
    _validateId(seasonId);
    await api.submitForm(
      followed ? '/pgc/web/follow/add' : '/pgc/web/follow/del',
      'pgc_follow_write',
      {'season_id': seasonId},
      context: context,
    );
  }

  // Require episodes for a detail page opened with a specific episode. Other
  // callers can use the season metadata even when it has no episode list.
  Future<ApiPgcSeason> getSeason({
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
    try {
      return await api.requestPgcSeason(
        Uri.https('api.bilibili.com', '/pgc/view/web/season', {
          'season_id': ?seasonId,
          'ep_id': ?episodeId,
        }),
        requireEpisodes: requireEpisodes,
        context: context,
      );
    } on ApiFailure catch (error) {
      final fallback = await _resolver();
      if (fallback == null || !_isRegionRefusal(error)) rethrow;
      return _preserveOfficialError(
        error,
        () => fallback.resolveSeason(
          seasonId: seasonId,
          episodeId: episodeId,
          requireEpisodes: requireEpisodes,
          context: context,
        ),
      );
    }
  }

  Future<ApiPlayInfo> getPlayInfo(
    String episodeId, {
    int qn = 80,
    ApiRequestContext? context,
  }) async {
    _validateId(episodeId);
    if (qn < 1 || qn > 30000) throw ArgumentError.value(qn, 'qn');
    try {
      return await _officialPlayInfo(episodeId, qn, context);
    } on ApiFailure catch (error) {
      final fallback = await _resolver();
      if (fallback == null || !_isRegionRefusal(error)) rethrow;
      return _preserveOfficialError(
        error,
        () => fallback.resolvePlayInfo(episodeId, qn: qn, context: context),
      );
    }
  }

  Future<ApiPlayInfo> _officialPlayInfo(
    String episodeId,
    int qn,
    ApiRequestContext? context,
  ) async {
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
    return parsePgcPlayInfo(data);
  }

  static bool _isRegionRefusal(ApiFailure error) =>
      error.category == ApiFailureCategory.permission ||
      error.category == ApiFailureCategory.notFound ||
      const {-10403, 6002003, -10493}.contains(error.businessCode);

  static Future<T> _preserveOfficialError<T>(
    ApiFailure officialError,
    Future<T?> Function() resolve,
  ) async {
    try {
      final result = await resolve();
      if (result != null) return result;
    } on ApiFailure catch (error) {
      if (error.category == ApiFailureCategory.cancelled) rethrow;
      // Resolver timeout/protocol/network errors do not replace the refusal
      // that triggered fallback. Cancellation remains a caller-owned result.
    }
    throw officialError;
  }

  static void _validateId(String value) {
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(value)) {
      throw ArgumentError('Invalid PGC ID');
    }
  }
}
