import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../domain/comment_video_link.dart';

final commentVideoLinkRepositoryProvider = Provider<CommentVideoLinkRepository>(
  (ref) => throw UnimplementedError('CommentVideoLinkRepository'),
);

/// Navigation is supplied by the app so all shared comment panels use the same
/// workspace and playback lifecycle, including dynamic and PGC comments.
final commentVideoNavigatorProvider = Provider<void Function(VideoId)?>(
  (ref) => null,
);

final commentLinkResolverProvider = Provider<CommentLinkResolver>(
  (ref) =>
      CommentLinkResolver(() => ref.read(commentVideoLinkRepositoryProvider)),
);

final class CommentLinkResolver {
  CommentLinkResolver(this._repository);
  final CommentVideoLinkRepository Function() _repository;

  Future<VideoId?> resolve(Uri uri, RequestCancellation cancellation) async {
    if (cancellation.isCancelled) return null;
    final link = parseCommentVideoLink(uri);
    if (link?.video case final video?) return video;
    if (link == null && !isBilibiliShortLink(uri)) return null;
    return _repository().resolve(uri, cancellation: cancellation);
  }
}
