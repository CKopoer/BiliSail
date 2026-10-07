import '../../domain/comment_target.dart';

import 'package:bili_api/bili_api.dart';

import '../../domain/dynamic_post.dart';
import '../../domain/user.dart';
import '../../domain/video.dart';

DynamicPost mapDynamicPost(ApiDynamicPost p) {
  final v = p.video;
  final original = p.original;
  return DynamicPost(
    id: p.id,
    title: p.title,
    authorName: p.authorName,
    authorId: UserId.tryParse(p.authorId),
    authorAvatarUrl: p.authorAvatarUrl,
    publishedAt: p.publishedAt,
    publishText: p.publishText,
    actionText: p.actionText,
    text: p.text,
    spans: p.spans
        .map(
          (s) => DynamicTextSpan(
            kind: DynamicTextKind.values.byName(s.kind.name),
            text: s.text,
            imageUrl: s.imageUrl,
            linkUrl: s.linkUrl,
            userId: UserId.tryParse(s.userId),
            emojiSize: s.emojiSize,
          ),
        )
        .toList(),
    imageUrls: p.imageUrls,
    imageAspectRatios: p.imageAspectRatios,
    video: v == null
        ? null
        : VideoSummary(
            id: VideoId(v.bvid),
            title: v.title,
            coverUrl: v.coverUrl?.toString() ?? '',
            author: v.ownerName,
            duration: v.duration,
            playCount: v.playCount,
            danmakuCount: v.danmakuCount,
            publishedAt: v.publishedAt,
            authorAvatarUrl: v.ownerAvatarUrl,
            authorId: UserId.tryParse(v.ownerMid),
          ),
    original: original == null ? null : mapDynamicPost(original),
    repostCount: p.repostCount,
    commentCount: p.commentCount,
    likeCount: p.likeCount,
    typeLabel: p.typeLabel,
    linkTitle: p.linkTitle,
    linkDescription: p.linkDescription,
    linkCoverUrl: p.linkCoverUrl,
    linkUrl: p.linkUrl,
    commentTarget: p.commentOid == null || p.commentType == null
        ? null
        : _target(p.commentOid!, p.commentType!),
    liked: p.liked,
    commentForbidden: p.commentForbidden,
    repostForbidden: p.repostForbidden,
    likeForbidden: p.likeForbidden,
    unavailable: p.unavailable,
  );
}

CommentTarget? _target(String oid, int value) {
  for (final type in CommentTargetType.values) {
    if (type.value == value) return CommentTarget(oid, type);
  }
  return null;
}
