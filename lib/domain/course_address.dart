/// Public PUGV links use their own episode and season ID namespaces.
final class CourseAddress {
  const CourseAddress(this.id, {this.season = false});
  final String id;
  final bool season;

  String get location => '/course/${season ? 'season' : 'episode'}/$id';
  String get webUrl =>
      'https://www.bilibili.com/cheese/play/${season ? 'ss' : 'ep'}$id';

  static CourseAddress? parse(Uri? uri) {
    if (uri == null || uri.userInfo.isNotEmpty) return null;
    if (uri.scheme == 'bilibili' && uri.host == 'cheese' && !uri.hasPort) {
      final match = RegExp(r'^/(season|episode)/([1-9][0-9]{0,18})/?$')
          .firstMatch(uri.path);
      return match == null
          ? null
          : CourseAddress(match[2]!, season: match[1] == 'season');
    }
    if (uri.scheme != 'https' ||
        uri.port != 443 ||
        !const {
          'www.bilibili.com',
          'm.bilibili.com',
          'bilibili.com',
        }.contains(uri.host)) {
      return null;
    }
    final match = RegExp(r'^/cheese/play/(ss|ep)([1-9][0-9]{0,18})/?$')
        .firstMatch(uri.path);
    return match == null
        ? null
        : CourseAddress(match[2]!, season: match[1] == 'ss');
  }
}
