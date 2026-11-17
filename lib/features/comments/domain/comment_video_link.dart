import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';

/// A public video reference, before resolving an AV identifier to a BV identifier.
final class CommentVideoLink {
  const CommentVideoLink.bv(this.video) : aid = null;
  const CommentVideoLink.av(this.aid) : video = null;
  final VideoId? video;
  final String? aid;
}

bool isPublicBilibiliLink(Uri uri) =>
    uri.userInfo.isEmpty &&
    ((uri.scheme == 'https' && uri.port == 443) ||
        (uri.scheme == 'http' && uri.port == 80)) &&
    const {
      'b23.tv',
      'bilibili.com',
      'www.bilibili.com',
      'm.bilibili.com',
    }.contains(uri.host);

bool isBilibiliShortLink(Uri uri) =>
    isPublicBilibiliLink(uri) && uri.host == 'b23.tv';

CommentVideoLink? parseCommentVideoLink(Uri uri) {
  if (uri.scheme == 'bilibili') {
    if (uri.host != 'video' || uri.userInfo.isNotEmpty || uri.hasPort) {
      return null;
    }
    final match = RegExp(r'^/([^/]+)/?$').firstMatch(uri.path);
    final id = match?.group(1);
    if (id == null) return null;
    return _videoIdentifier(id) ??
        (RegExp(r'^[1-9][0-9]*$').hasMatch(id)
            ? CommentVideoLink.av(id)
            : null);
  }
  if (!isPublicBilibiliLink(uri)) return null;
  final match = RegExp(
    uri.host == 'b23.tv'
        ? r'^/((?:BV[0-9A-Za-z]{10})|(?:av[1-9][0-9]*))/?$'
        : r'^/video/((?:BV[0-9A-Za-z]{10})|(?:av[1-9][0-9]*))(?:\.html)?/?$',
    caseSensitive: false,
  ).firstMatch(uri.path);
  if (match == null) return null;
  final id = match.group(1);
  if (id == null) return null;
  return _videoIdentifier(id);
}

CommentVideoLink? _videoIdentifier(String id) {
  if (RegExp(r'^[bB][vV][0-9A-Za-z]{10}$').hasMatch(id)) {
    // Only the prefix is case insensitive; the BV payload keeps its case.
    return CommentVideoLink.bv(VideoId('BV${id.substring(2)}'));
  }
  if (RegExp(r'^[aA][vV][1-9][0-9]*$').hasMatch(id)) {
    return CommentVideoLink.av(id.substring(2));
  }
  return null;
}

/// Normalize recognized references to safe web targets for shared navigation.
Uri? parseCommentLinkUri(String text) {
  Uri videoUri(CommentVideoLink link) => Uri.https(
    'www.bilibili.com',
    '/video/${link.video?.value ?? 'av${link.aid}'}',
  );
  final identifier = _videoIdentifier(text);
  if (identifier != null) return videoUri(identifier);
  final normalized = text.startsWith('//')
      ? 'https:$text'
      : RegExp(
          r'^(?:(?:www|m)\.)?bilibili\.com/|^b23\.tv/',
          caseSensitive: false,
        ).hasMatch(text)
      ? 'https://$text'
      : text;
  final uri = Uri.tryParse(normalized);
  if (uri == null || uri.userInfo.isNotEmpty) return null;
  if (uri.scheme == 'bilibili') {
    final link = parseCommentVideoLink(uri);
    return link == null
        ? null
        : videoUri(link).replace(query: uri.hasQuery ? uri.query : null);
  }
  return (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty
      ? uri
      : null;
}

abstract interface class CommentVideoLinkRepository {
  Future<VideoId?> resolve(
    Uri uri, {
    required RequestCancellation cancellation,
  });
}
