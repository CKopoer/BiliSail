import 'package:flutter/material.dart';

import '../../core/presentation/public_image_variant.dart';
import '../../domain/dynamic_post.dart';
import '../../domain/user.dart';
import '../../domain/video.dart';
import '../../features/dynamic/domain/dynamic_link.dart';
import 'image_viewer.dart';
import 'dynamic_content_card.dart';
import 'dynamic_post_text.dart';
export 'dynamic_post_text.dart' show DynamicPostExpansionState;
import 'network_avatar.dart';
import 'bili_icons.dart';
import 'video_card.dart';
import 'app_network_image.dart';

/// Dynamic content; navigation and account actions belong to the owning feature.
class DynamicPostCard extends StatelessWidget {
  const DynamicPostCard({
    super.key,
    required this.post,
    this.onOpenUser,
    this.onOpenVideo,
    this.onOpenLink,
    this.onOpenDetail,
    this.onShare,
    this.onComment,
    this.onLike,
    this.onMore,
    this.liked,
    this.likeCount,
    this.repostCount,
    this.busy = false,
    this.expansionState,
    this.inDetail = false,
    this.contentCardBuilder,
  }) : _layoutOnly = false;

  /// Uses the same layout without image requests or account state subscriptions.
  /// Only the detached extent measurement tree should use this constructor.
  const DynamicPostCard.forLayout({
    super.key,
    required this.post,
    this.onOpenLink,
    this.expansionState,
  }) : _layoutOnly = true,
       inDetail = false,
       onOpenUser = null,
       onOpenVideo = null,
       onOpenDetail = null,
       onShare = null,
       onComment = null,
       onLike = null,
       onMore = null,
       liked = null,
       likeCount = null,
       repostCount = null,
       busy = false,
       contentCardBuilder = null;

  final bool _layoutOnly;
  final bool inDetail;
  final DynamicPostExpansionState? expansionState;
  final DynamicPost post;
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<VideoSummary>? onOpenVideo;
  final ValueChanged<Uri>? onOpenLink;
  final VoidCallback? onOpenDetail;
  final VoidCallback? onShare, onComment, onLike;
  final VoidCallback? onMore;
  final bool? liked;
  final int? likeCount, repostCount;
  final bool busy;
  final Widget Function(DynamicPost, DynamicContentCard)? contentCardBuilder;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(12),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onOpenDetail,
      onLongPress: onMore,
      onSecondaryTap: onMore,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _PostBody(
          post: post,
          contentCardBuilder: contentCardBuilder,
          inDetail: inDetail,
          onOpenDetail: onOpenDetail,
          layoutOnly: _layoutOnly,
          expansionState: expansionState,
          onOpenUser: onOpenUser,
          onOpenVideo: onOpenVideo,
          onOpenLink: onOpenLink,
          onMore: onMore,
          actions: _DynamicActions(
            post: post,
            onShare: onShare,
            onComment: onComment,
            onLike: onLike,
            liked: liked ?? post.liked,
            likeCount: likeCount ?? post.likeCount,
            repostCount: repostCount ?? post.repostCount,
            busy: busy,
          ),
        ),
      ),
    ),
  );
}

class _PostBody extends StatelessWidget {
  const _PostBody({
    required this.post,
    this.onOpenUser,
    this.onOpenVideo,
    this.onOpenLink,
    this.onOpenDetail,
    this.onMore,
    this.depth = 0,
    this.actions,
    this.layoutOnly = false,
    this.inDetail = false,
    this.expansionState,
    this.contentCardBuilder,
  });
  final DynamicPost post;
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<VideoSummary>? onOpenVideo;
  final ValueChanged<Uri>? onOpenLink;
  final VoidCallback? onOpenDetail;
  final VoidCallback? onMore;
  final int depth;
  final Widget? actions;
  final bool layoutOnly, inDetail;
  final DynamicPostExpansionState? expansionState;
  final Widget Function(DynamicPost, DynamicContentCard)? contentCardBuilder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final userId = post.authorId;
    final video = post.video;
    final original = post.original;
    final topic = post.topic;
    final topicTarget = topic == null
        ? null
        : dynamicTopicDestination(
            id: topic.id,
            name: topic.name,
            url: topic.url,
          );
    final time = post.publishText.isNotEmpty
        ? post.publishText
        : post.publishedAt?.toLocal().toString().split('.').first ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: InkWell(
                onTap: userId != null && onOpenUser != null
                    ? () => onOpenUser!(userId)
                    : null,
                child: Row(
                  children: [
                    NetworkAvatar(
                      url: layoutOnly ? null : post.authorAvatarUrl,
                      pendantUrl: layoutOnly ? null : post.authorPendantUrl,
                      name: post.authorName,
                      radius: depth == 0 ? 20 : 14,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            post.authorName.isEmpty ? '动态' : post.authorName,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  height: 1.25,
                                ),
                          ),
                          if (time.isNotEmpty || post.actionText.isNotEmpty)
                            Text(
                              [
                                time,
                                post.actionText,
                              ].where((s) => s.isNotEmpty).join(' · '),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(height: 1.25),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (depth == 0 && !inDetail)
              IconButton(
                tooltip: '查看动态详情',
                onPressed: onOpenDetail,
                icon: const Icon(Icons.chevron_right, size: 20),
              ),
            if (depth == 0)
              IconButton(
                tooltip: '更多动态操作',
                onPressed: onMore,
                icon: const Icon(Icons.more_horiz, size: 20),
              ),
          ],
        ),
        if (topic != null) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              label: '查看话题 ${topic.name}',
              button: true,
              // RawChip's Ink decoration requires a mounted render tree.
              // Keep this pill safe for the detached list extent measurement.
              child: Material(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: topicTarget == null || onOpenLink == null
                      ? null
                      : () => onOpenLink!(topicTarget),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tag, size: 18, color: scheme.primary),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            topic.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: scheme.primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        if (post.badge.isNotEmpty || post.typeLabel.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            [post.badge, post.typeLabel].where((s) => s.isNotEmpty).join(' · '),
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: scheme.primary),
          ),
        ],
        if (post.pinned || post.onlySelf)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              [if (post.pinned) '置顶', if (post.onlySelf) '仅自己可见'].join(' · '),
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: scheme.primary),
            ),
          ),
        if (post.title.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(post.title, style: Theme.of(context).textTheme.titleSmall),
        ],
        if (post.text.isNotEmpty || post.spans.isNotEmpty) ...[
          const SizedBox(height: 12),
          DynamicPostText(
            post: post,
            inDetail: inDetail,
            layoutOnly: layoutOnly,
            expansionState: expansionState,
            onOpenUser: onOpenUser,
            onOpenLink: onOpenLink,
          ),
        ],
        if (post.unavailable && post.text.isEmpty && post.spans.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('原动态已不可用'),
          ),
        if (video != null) ...[
          const SizedBox(height: 12),
          Material(
            color: scheme.surfaceContainerHighest.withValues(alpha: .55),
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onOpenVideo == null ? null : () => onOpenVideo!(video),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _image(
                          Uri.tryParse(video.coverUrl),
                          layoutOnly: layoutOnly,
                          fit: BoxFit.cover,
                          decodeWidth: 960,
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black87],
                              ),
                            ),
                            child: Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              spacing: 8,
                              children: [
                                Text(
                                  '${compactCount(video.playCount)}播放 · ${compactCount(video.danmakuCount)}弹幕',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  durationLabel(video.duration),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      video.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (post.imageUrls.isNotEmpty) ...[
          const SizedBox(height: 12),
          if (post.imageUrls.length == 1)
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 320,
                  maxHeight: 360,
                ),
                // Image loading and visibility must never change the sliver's
                // geometry. Missing metadata keeps a square slot even after
                // decoding; the contained image can still use its own ratio.
                child: AspectRatio(
                  aspectRatio: _pictureAspectRatio(post, post.imageUrls.first),
                  child: _picture(
                    context,
                    post.imageUrls.first,
                    images: post.imageUrls,
                    imageIndex: 0,
                    decodeWidth: 960,
                    layoutOnly: layoutOnly,
                  ),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = post.imageUrls.length == 4 ? 2 : 3;
                final gridWidth = constraints.maxWidth.clamp(
                  0.0,
                  columns == 2 ? 300.0 : 400.0,
                );
                final width = (gridWidth - (columns - 1) * 6) / columns;
                return Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: gridWidth,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final (index, image)
                            in post.imageUrls.take(18).indexed)
                          SizedBox.square(
                            dimension: width,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: _picture(
                                context,
                                image,
                                images: post.imageUrls,
                                imageIndex: index,
                                fit: BoxFit.cover,
                                decodeWidth: 520,
                                layoutOnly: layoutOnly,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
        for (final card in post.contentCards) ...[
          const SizedBox(height: 10),
          contentCardBuilder?.call(post, card) ??
              DynamicContentCardView(
                card: card,
                onOpenLink: onOpenLink,
                layoutOnly: layoutOnly,
              ),
        ],
        if (post.notice.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            post.notice,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        if (post.contentCards.isEmpty && post.linkTitle.isNotEmpty) ...[
          const SizedBox(height: 12),
          InkWell(
            onTap: post.linkUrl != null && onOpenLink != null
                ? () => onOpenLink!(post.linkUrl!)
                : null,
            child: Container(
              padding: const EdgeInsets.all(12),
              color: scheme.surfaceContainerHighest,
              child: Row(
                children: [
                  if (post.linkCoverUrl != null) ...[
                    SizedBox.square(
                      dimension: 64,
                      child: _image(
                        post.linkCoverUrl,
                        fit: BoxFit.cover,
                        layoutOnly: layoutOnly,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.linkTitle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (post.linkDescription.isNotEmpty)
                          Text(
                            post.linkDescription,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (original != null && depth >= 2)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextButton(
              onPressed: onOpenLink == null
                  ? null
                  : () => onOpenLink!(
                      Uri.https('t.bilibili.com', '/${original.id}'),
                    ),
              child: const Text('更多转发内容请在原动态查看'),
            ),
          ),
        if (original != null && depth < 2) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: _PostBody(
              post: original,
              contentCardBuilder: contentCardBuilder,
              inDetail: inDetail,
              layoutOnly: layoutOnly,
              expansionState: expansionState,
              onOpenUser: onOpenUser,
              onOpenVideo: onOpenVideo,
              onOpenLink: onOpenLink,
              depth: depth + 1,
            ),
          ),
        ],
        if (depth == 0) ...[const SizedBox(height: 16), ?actions],
      ],
    );
  }
}

class _DynamicActions extends StatelessWidget {
  const _DynamicActions({
    required this.post,
    required this.liked,
    required this.likeCount,
    required this.repostCount,
    required this.busy,
    this.onShare,
    this.onComment,
    this.onLike,
  });
  final DynamicPost post;
  final bool liked, busy;
  final int? likeCount, repostCount;
  final VoidCallback? onShare, onComment, onLike;

  @override
  Widget build(BuildContext context) {
    Widget action(
      IconData icon,
      String label,
      int? count,
      VoidCallback? callback, {
      bool selected = false,
    }) => Tooltip(
      message: label,
      child: Semantics(
        label: '$label ${compactCount(count)}',
        button: callback != null,
        selected: selected,
        child: InkWell(
          onTap: busy ? null : callback,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                const SizedBox(width: 6),
                Text(
                  count == null ? label : compactCount(count),
                  style: selected
                      ? TextStyle(color: Theme.of(context).colorScheme.primary)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        action(BiliIcons.share, '分享动态', repostCount, onShare),
        action(
          BiliIcons.comment,
          post.commentForbidden ? '评论已关闭' : '查看评论',
          post.commentCount,
          onComment,
        ),
        action(
          BiliIcons.like,
          liked ? '取消点赞动态' : '点赞动态',
          likeCount,
          onLike,
          selected: liked,
        ),
      ],
    );
  }
}

Widget _image(
  Uri? url, {
  BoxFit fit = BoxFit.contain,
  int decodeWidth = 256,
  bool layoutOnly = false,
}) {
  if (layoutOnly) return const SizedBox.expand();
  if (url == null || !['http', 'https'].contains(url.scheme)) {
    return const Icon(Icons.image_outlined);
  }
  return AppNetworkImage(
    url: publicImageThumbnail(url, width: decodeWidth).toString(),
    cacheWidth: decodeWidth,
    fit: fit,
    errorBuilder: (_, _, _) =>
        const Center(child: Icon(Icons.image_not_supported_outlined)),
  );
}

double _pictureAspectRatio(DynamicPost post, Uri image) {
  final ratio = post.imageAspectRatios[image];
  return ratio != null && ratio.isFinite && ratio > 0 ? ratio : 1;
}

Widget _picture(
  BuildContext context,
  Uri url, {
  required List<Uri> images,
  required int imageIndex,
  BoxFit fit = BoxFit.contain,
  int decodeWidth = 256,
  bool layoutOnly = false,
}) => Semantics(
  label: '查看动态图片',
  button: true,
  child: InkWell(
    onTap: () => showImageViewer(context, images, imageIndex),
    child: _image(
      url,
      fit: fit,
      decodeWidth: decodeWidth,
      layoutOnly: layoutOnly,
    ),
  ),
);
