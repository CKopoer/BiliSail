import '../../domain/comment_target.dart';

import 'package:bili_api/bili_api.dart';

import 'video_access_mapper.dart';

import '../../domain/dynamic_post.dart';
import '../../domain/user.dart';
import '../../domain/video.dart';

DynamicPost mapDynamicPost(ApiDynamicPost p) {
  final v = p.video;
  final original = p.original;
  final topic = p.topic;
  return DynamicPost(
    id: p.id,
    pinned: p.pinned,
    onlySelf: p.onlySelf,
    editable: p.editable,
    title: p.title,
    authorName: p.authorName,
    authorId: UserId.tryParse(p.authorId),
    authorAvatarUrl: p.authorAvatarUrl,
    authorPendantUrl: p.authorPendantUrl,
    publishedAt: p.publishedAt,
    publishText: p.publishText,
    actionText: p.actionText,
    text: p.text,
    topic: topic == null
        ? null
        : DynamicTopic(name: topic.name, id: topic.id, url: topic.url),
    badge: p.badge,
    notice: p.notice,
    contentCards: p.contentCards
        .map(
          (card) => DynamicContentCard(
            kind: DynamicCardKind.values.byName(card.kind.name),
            title: card.title,
            description: card.description,
            detail: card.detail,
            badge: card.badge,
            coverUrl: card.coverUrl,
            url: card.url,
            actionLabel: card.actionLabel,
            actionUrl: card.actionUrl,
            reservation: switch (card.reservation) {
              final r? => DynamicReservation(
                id: r.id,
                status: r.status,
                type: r.type,
                total: r.total,
                description: r.description,
                checkedText: r.checkedText,
                uncheckedText: r.uncheckedText,
                disabled: r.disabled,
                ended: r.ended,
                hasJump: r.hasJump,
              ),
              _ => null,
            },
          ),
        )
        .toList(),
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
            access: mapVideoAccess(v.access),
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
