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

  static ArticleAddress? fromWebUri(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        !const {
          'www.bilibili.com',
          'bilibili.com',
          'm.bilibili.com',
        }.contains(uri.host)) {
      return null;
    }
    final column = RegExp(r'^/read/cv([1-9][0-9]{0,127})/?$')
        .firstMatch(uri.path)?[1];
    if (column != null) return ArticleAddress(ArticleKind.column, column);
    final opus = RegExp(r'^/(?:mobile/|h5/|v/)?opus/([1-9][0-9]{0,127})/?$')
        .firstMatch(uri.path)?[1];
    return opus == null ? null : ArticleAddress(ArticleKind.opus, opus);
  }

  @override
  bool operator ==(Object other) =>
      other is ArticleAddress && id == other.id && kind == other.kind;

  @override
  int get hashCode => Object.hash(kind, id);
}
