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
  if (!isPublicBilibiliLink(uri)) return null;
  final match = RegExp(
    uri.host == 'b23.tv'
        ? r'^/((?:BV[0-9A-Za-z]{10})|(?:av[1-9][0-9]*))/?$'
        : r'^/video/((?:BV[0-9A-Za-z]{10})|(?:av[1-9][0-9]*))(?:\.html)?/?$',
  ).firstMatch(uri.path);
  if (match == null) return null;
  final id = match.group(1);
  if (id == null) return null;
  return id.startsWith('BV')
      ? CommentVideoLink.bv(VideoId(id))
      : CommentVideoLink.av(id.substring(2));
}

abstract interface class CommentVideoLinkRepository {
  Future<VideoId?> resolve(
    Uri uri, {
    required RequestCancellation cancellation,
  });
}
