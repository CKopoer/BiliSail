import 'content_link.dart';

enum ArticleKind { column, opus }

/// The legacy column ID and the newer opus ID identify different resources.
final class ArticleAddress {
  const ArticleAddress(this.kind, this.id);

  final ArticleKind kind;
  final String id;

  bool get isValid => RegExp(r'^[1-9][0-9]{0,127}$').hasMatch(id);
  String get location =>
      kind == ArticleKind.opus ? '/opus/$id' : '/article/$id';
  Uri get webUri => Uri.https(
    'www.bilibili.com',
    kind == ArticleKind.opus ? '/opus/$id' : '/read/cv$id',
  );

  static ArticleAddress? fromLocation(Uri uri) {
    if (uri.hasScheme || uri.hasAuthority) return null;
    return switch (uri.pathSegments) {
      ['article', final id] => ArticleAddress(ArticleKind.column, id),
      ['opus', final id] => ArticleAddress(ArticleKind.opus, id),
      _ => null,
    };
  }

  static ArticleAddress? fromWebUri(Uri uri) {
    if (!_trustedWebUri(uri)) return null;
    final column = RegExp(r'^/read/cv([1-9][0-9]{0,127})/?$')
        .firstMatch(uri.path)?[1];
    if (column != null) return ArticleAddress(ArticleKind.column, column);
    final opus = RegExp(r'^/(?:mobile/|h5/|v/)?opus/([1-9][0-9]{0,127})/?$')
        .firstMatch(uri.path)?[1];
    return opus == null ? null : ArticleAddress(ArticleKind.opus, opus);
  }

  static String? workspaceLocation(Uri uri) {
    if (_trustedWebUri(uri)) {
      final match = RegExp(
        r'^/read/(?:(?:mobile-)?readlist/)?rl([1-9][0-9]{0,127})/?$',
      ).firstMatch(uri.path);
      if (match != null) return ArticleCollectionId(match[1]!).location;
    }
    final article = fromWebUri(uri);
    if (article == null) return null;
    // Resource notifications use a business ID to look up the dynamic.
    final path =
        article.kind == ArticleKind.opus && uri.queryParameters['type'] == '2'
        ? '/dynamic/resource/${article.id}'
        : article.location;
    final comment = CommentLocation.fromWebUri(uri);
    return comment == null
        ? path
        : Uri(path: path, queryParameters: comment.queryParameters).toString();
  }

  @override
  bool operator ==(Object other) =>
      other is ArticleAddress && id == other.id && kind == other.kind;

  @override
  int get hashCode => Object.hash(kind, id);
}

extension type const ArticleCollectionId(String value) {
  bool get isValid => RegExp(r'^[1-9][0-9]{0,127}$').hasMatch(value);
  String get location => '/article-list/$value';
  Uri get webUri => Uri.https('www.bilibili.com', '/read/readlist/rl$value');
}

bool _trustedWebUri(Uri uri) =>
    uri.scheme == 'https' &&
    uri.port == 443 &&
    uri.userInfo.isEmpty &&
    const {
      'www.bilibili.com',
      'bilibili.com',
      'm.bilibili.com',
    }.contains(uri.host);
