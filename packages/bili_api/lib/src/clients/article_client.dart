import '../api_client.dart';
import '../mappers/article_parser.dart';
import '../models.dart';
import '../models/article_models.dart';

final class ArticleClient {
  const ArticleClient(this.api);

  final BiliApiClient api;

  Future<ApiArticle> read(
    String id, {
    required bool opus,
    ApiRequestContext? context,
  }) async {
    if (!isArticleId(id)) throw ArgumentError('Invalid article ID');
    final active = api.boundedReadContext(context);
    if (opus) return _readOpus(id, active);
    final redirect = await api.articleRedirect(id, context: active);
    final redirectedId = _redirectOpusId(redirect);
    if (redirectedId != null) return _readMigratedCv(id, redirectedId, active);

    final data = await _loadCv(id, active);
    // The legacy response can identify a migrated work even when the site
    // omits the redirect. Its embedded paragraphs can have missing text.
    final opusId = articleId(articleMap(data['opus'])['opus_id']);
    return opusId == null
        ? _parseCv(id, data)
        : _readMigratedCv(id, opusId, active, data: data);
  }

  Future<ApiArticle> _readMigratedCv(
    String cvId,
    String opusId,
    ApiRequestContext context, {
    Map<String, Object?>? data,
  }) async {
    try {
      return await _readOpus(
        opusId,
        context,
        legacy: data == null ? null : (id: cvId, data: data),
      );
    } on ApiFailure catch (error) {
      if (error.category != ApiFailureCategory.rateLimited ||
          error.endpointId != 'opus_detail' ||
          error.requiresVerification) {
        rethrow;
      }
      // Some migrated columns still publish structured paragraphs via CV.
      final legacy = data ?? await _loadCv(cvId, context);
      final opus = articleMap(legacy['opus']);
      if (articleId(opus['opus_id']) != opusId ||
          articleMap(opus['content'])['paragraphs'] is! List<Object?>) {
        rethrow;
      }
      return _parseCv(cvId, legacy);
    }
  }

  Future<ApiArticle> _readOpus(
    String opusId,
    ApiRequestContext context, {
    ({String id, Map<String, Object?> data})? legacy,
  }) async {
    const endpoint = 'opus_detail';
    final data = await api.requestWbiJson(
      '/x/polymer/web-dynamic/v1/opus/detail',
      {
        'id': opusId,
        'timezone_offset': '-480',
        'features':
            'onlyfansVote,onlyfansAssetsV2,onlyfansOpusCard,'
            'decorationCard,htmlNewStyle,ugcDelete,editable,opusPrivateVisible,'
            'opusTribeeApprovedThread,opusTribeeRejectThread,'
            'opusTribeeFeatured,opusTribeeModifyCategory,'
            'opusTribeeRemoveThread,opusTribeeCoin,tribeeEdit,avatarAutoTheme,'
            'avatarTypeOpus,sunflowerStyle,articleEnhance,cardsEnhance,'
            'eva3CardOpus,eva3CardVideo,eva3CardComment,eva3CardVote,eva3CardUser',
      },
      endpoint,
      context: context,
    );
    final fallback = articleMap(data['fallback'])['id'];
    if (fallback != null) {
      final cvId = articleId(fallback);
      if (cvId == null) {
        throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
      }
      // A fallback is already resolved. Reuse the same CV response if we
      // have it, without probing or resolving its opus identity again.
      final cvData = legacy != null && legacy.id == cvId
          ? legacy.data
          : await _loadCv(cvId, context);
      return _parseCv(cvId, cvData);
    }
    return ArticleParser(
      Uri.https('www.bilibili.com', '/opus/$opusId'),
      endpoint,
    ).opus(data, opusId);
  }

  Future<Map<String, Object?>> _loadCv(
    String id,
    ApiRequestContext context,
  ) async {
    const endpoint = 'article_view';
    final data = await api.requestWbiJson(
      '/x/article/view',
      {'id': id, 'gaia_source': 'main_web', 'web_location': '333.976'},
      endpoint,
      context: context,
    );
    if (data['id'] != null && articleId(data['id']) != id) {
      throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    return data;
  }

  ApiArticle _parseCv(String id, Map<String, Object?> data) => ArticleParser(
    Uri.https('www.bilibili.com', '/read/cv$id'),
    'article_view',
  ).legacy(data, id);

  Future<ApiArticleCollection> collection(
    String id, {
    ApiRequestContext? context,
  }) async {
    if (!isArticleId(id)) throw ArgumentError('Invalid article collection ID');
    const endpoint = 'article_list';
    final uri = Uri.https('api.bilibili.com', '/x/article/list/web/articles', {
      'id': id,
      'web_location': '333.1400',
    });
    final data = await api.requestJson(uri, endpoint, context: context);
    return ArticleParser(uri, endpoint).collection(data, id);
  }

  Future<ApiArticleStats> viewInfo(
    String cvId, {
    ApiRequestContext? context,
  }) async {
    if (!isArticleId(cvId)) throw ArgumentError('Invalid article ID');
    final data = await api.requestWbiJson(
      '/x/article/viewinfo',
      {'id': cvId, 'mobi_app': 'pc', 'from': 'web', 'gaia_source': 'main_web'},
      'article_viewinfo',
      context: context,
    );
    return ArticleParser.viewInfo(data);
  }

  Future<void> setFavorite(
    String id, {
    required bool opus,
    required bool favorite,
    ApiRequestContext? context,
  }) async {
    if (!isArticleId(id)) throw ArgumentError('Invalid article ID');
    if (opus) {
      await api.submitDynamicJson(
        '/x/community/cosmo/interface/simple_action',
        'opus_favorite',
        {
          'entity': {
            'object_id_str': id,
            'type': {'biz': 2},
          },
          'action': favorite ? 3 : 4,
        },
        context: context,
      );
    } else {
      await api.submitForm(
        favorite ? '/x/article/favorites/add' : '/x/article/favorites/del',
        'article_favorite',
        {'id': id},
        context: context,
      );
    }
  }

  static String? _redirectOpusId(Uri? uri) {
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        !const {
          'www.bilibili.com',
          'bilibili.com',
          'm.bilibili.com',
        }.contains(uri.host)) {
      return null;
    }
    return RegExp(r'^/opus/([1-9][0-9]{0,127})/?$').firstMatch(uri.path)?[1];
  }
}
