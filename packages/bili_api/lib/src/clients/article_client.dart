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
    final redirect = opus
        ? null
        : await api.articleRedirect(id, context: active);
    final opusId = opus ? id : _redirectOpusId(redirect);
    if (opusId == null) return _readCv(id, active);

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
      context: active,
    );
    final fallback = articleMap(data['fallback'])['id'];
    if (fallback != null) {
      final cvId = articleId(fallback);
      if (cvId == null) {
        throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
      }
      // A fallback is already a resolved legacy identity. Do not probe again.
      return _readCv(cvId, active);
    }
    return ArticleParser(
      Uri.https('www.bilibili.com', '/opus/$opusId'),
      endpoint,
    ).opus(data, opusId);
  }

  Future<ApiArticle> _readCv(String id, ApiRequestContext context) async {
    const endpoint = 'article_view';
    final data = await api.requestWbiJson(
      '/x/article/view',
      {'id': id, 'gaia_source': 'main_web', 'web_location': '333.976'},
      endpoint,
      context: context,
    );
    return ArticleParser(
      Uri.https('www.bilibili.com', '/read/cv$id'),
      endpoint,
    ).legacy(data, id);
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
