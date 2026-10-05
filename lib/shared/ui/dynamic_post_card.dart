import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../../core/presentation/public_image_variant.dart';
import '../../domain/dynamic_post.dart';
import '../../domain/user.dart';
import '../../domain/video.dart';
import 'image_viewer.dart';
import 'network_avatar.dart';
import 'bili_icons.dart';
import 'video_card.dart';
import 'app_network_image.dart';

/// Read-only dynamic content. Navigation is supplied by the owning page.
class DynamicPostCard extends StatelessWidget {
  const DynamicPostCard({
    super.key,
    required this.post,
    this.onOpenUser,
    this.onOpenVideo,
    this.onOpenLink,
  });
  final DynamicPost post;
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<VideoSummary>? onOpenVideo;
  final ValueChanged<Uri>? onOpenLink;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: _PostBody(
        post: post,
        onOpenUser: onOpenUser,
        onOpenVideo: onOpenVideo,
        onOpenLink: onOpenLink,
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
    this.depth = 0,
  });
  final DynamicPost post;
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<VideoSummary>? onOpenVideo;
  final ValueChanged<Uri>? onOpenLink;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final userId = post.authorId;
    final video = post.video;
    final original = post.original;
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
                      url: post.authorAvatarUrl,
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
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          if (time.isNotEmpty || post.actionText.isNotEmpty)
                            Text(
                              [
                                time,
                                post.actionText,
                              ].where((s) => s.isNotEmpty).join(' · '),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (onOpenLink != null)
              IconButton(
                tooltip: depth == 0 ? '在浏览器打开动态' : '在浏览器打开原动态',
                onPressed: () =>
                    onOpenLink!(Uri.https('t.bilibili.com', '/${post.id}')),
                icon: const Icon(Icons.open_in_new, size: 18),
              ),
          ],
        ),
        if (post.title.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(post.title, style: Theme.of(context).textTheme.titleSmall),
        ],
        if (post.text.isNotEmpty || post.spans.isNotEmpty) ...[
          const SizedBox(height: 12),
          _DynamicText(
            post: post,
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
          InkWell(
            onTap: onOpenVideo == null ? null : () => onOpenVideo!(video),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final coverWidth = constraints.maxWidth < 360 ? 112.0 : 160.0;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: coverWidth,
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _image(
                              Uri.tryParse(video.coverUrl),
                              fit: BoxFit.cover,
                              decodeWidth: 480,
                            ),
                            Positioned(
                              right: 4,
                              bottom: 4,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: .7),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  child: Text(
                                    durationLabel(video.duration),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            video.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${compactCount(video.playCount)}播放 · ${compactCount(video.danmakuCount)}弹幕',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
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
                child: _picture(
                  context,
                  post.imageUrls.first,
                  images: post.imageUrls,
                  imageIndex: 0,
                  decodeWidth: 960,
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
                            in post.imageUrls.take(9).indexed)
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
        if (post.linkTitle.isNotEmpty) ...[
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
                      child: _image(post.linkCoverUrl, fit: BoxFit.cover),
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
              onOpenUser: onOpenUser,
              onOpenVideo: onOpenVideo,
              onOpenLink: onOpenLink,
              depth: depth + 1,
            ),
          ),
        ],
        if (depth == 0) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 28,
            runSpacing: 8,
            children: [
              _stat(BiliIcons.share, '转发', post.repostCount),
              _stat(BiliIcons.comment, '评论', post.commentCount),
              _stat(BiliIcons.like, '点赞', post.likeCount),
            ],
          ),
        ],
      ],
    );
  }

  Widget _stat(IconData icon, String label, int? count) => Semantics(
    label: '$label ${compactCount(count)}',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Text(count == null ? label : compactCount(count)),
      ],
    ),
  );
}

Widget _image(Uri? url, {BoxFit fit = BoxFit.contain, int decodeWidth = 256}) {
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

Widget _picture(
  BuildContext context,
  Uri url, {
  required List<Uri> images,
  required int imageIndex,
  BoxFit fit = BoxFit.contain,
  int decodeWidth = 256,
}) => Semantics(
  label: '查看动态图片',
  button: true,
  child: InkWell(
    onTap: () => showImageViewer(context, images, imageIndex),
    child: _image(url, fit: fit, decodeWidth: decodeWidth),
  ),
);

class _DynamicText extends StatefulWidget {
  const _DynamicText({required this.post, this.onOpenUser, this.onOpenLink});
  final DynamicPost post;
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<Uri>? onOpenLink;
  @override
  State<_DynamicText> createState() => _DynamicTextState();
}

class _DynamicTextState extends State<_DynamicText> {
  bool _expanded = false;
  final _recognizers = <TapGestureRecognizer>[];
  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  void didUpdateWidget(_DynamicText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5);
    _disposeRecognizers();
    final parts = widget.post.spans;
    final length = parts.isEmpty
        ? widget.post.text.length
        : parts.fold<int>(0, (sum, span) => sum + span.text.length);
    final canExpand = length > 300 || widget.post.text.contains('\n');
    // Even expanded text remains bounded for malformed upstream payloads.
    var remaining = _expanded ? 12000 : 1000;
    final children = <InlineSpan>[];
    for (final part in parts) {
      if (remaining <= 0) break;
      final text = part.text.length > remaining
          ? '${part.text.substring(0, remaining)}…'
          : part.text;
      remaining -= part.text.length;
      final image = part.imageUrl;
      if (part.kind == DynamicTextKind.emoji &&
          image != null &&
          ['http', 'https'].contains(image.scheme)) {
        final size =
            MediaQuery.textScalerOf(context).scale(24) *
            part.emojiSize.clamp(1, 2);
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Semantics(
              label: part.text,
              image: true,
              child: AppNetworkImage(
                url: image.toString(),
                width: size,
                height: size,
                cacheWidth: (size * 3).ceil(),
                errorBuilder: (_, _, _) => Text(part.text, style: style),
              ),
            ),
          ),
        );
      } else if ((part.userId != null && widget.onOpenUser != null) ||
          (part.linkUrl != null && widget.onOpenLink != null)) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () {
            final userId = part.userId;
            final link = part.linkUrl;
            if (userId != null && widget.onOpenUser != null) {
              widget.onOpenUser!(userId);
            } else if (link != null) {
              widget.onOpenLink?.call(link);
            }
          };
        _recognizers.add(recognizer);
        children.add(
          TextSpan(
            text: text,
            recognizer: recognizer,
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
        );
      } else {
        children.add(
          TextSpan(
            text: text,
            style: part.kind == DynamicTextKind.plain
                ? null
                : TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
        );
      }
    }
    final plain = widget.post.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: parts.isEmpty
                ? [
                    TextSpan(
                      text: plain.length > remaining
                          ? '${plain.substring(0, remaining)}…'
                          : plain,
                    ),
                  ]
                : children,
          ),
          style: style,
          maxLines: canExpand && !_expanded ? 8 : null,
          softWrap: true,
          overflow: canExpand && !_expanded
              ? TextOverflow.ellipsis
              : TextOverflow.clip,
        ),
        if (canExpand)
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(_expanded ? '收起' : '展开全文'),
          ),
      ],
    );
  }
}
