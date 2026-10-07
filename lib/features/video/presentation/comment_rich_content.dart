import 'package:flutter/material.dart';

import '../../../core/presentation/public_image_variant.dart';
import '../../../domain/user.dart';
import '../domain/video_comments_repository.dart';
import '../../../shared/ui/app_network_image.dart';
import '../../../shared/ui/bili_badges.dart';
import '../../../shared/ui/image_viewer.dart';
import 'comment_text_styles.dart';

TextEditingValue insertCommentEmote(TextEditingValue value, String token) {
  final selection = value.selection;
  final start = selection.isValid
      ? selection.start.clamp(0, value.text.length)
      : value.text.length;
  final end = selection.isValid
      ? selection.end.clamp(start, value.text.length)
      : start;
  final text = value.text.replaceRange(start, end, token);
  if (text.length > 1000) return value;
  return TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: start + token.length),
  );
}

class CommentRichContent extends StatelessWidget {
  const CommentRichContent({
    super.key,
    required this.comment,
    this.prefix = '',
    this.compact = false,
  });
  final CommentEntry comment;
  final String prefix;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final styles = CommentTextStyles(Theme.of(context));
    final spans = <InlineSpan>[if (prefix.isNotEmpty) TextSpan(text: prefix)];
    final text = comment.message;
    final keys = comment.emotes.keys.where((k) => k.isNotEmpty).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    var cursor = 0;
    while (cursor < text.length) {
      String? token;
      var position = text.length;
      for (final k in keys) {
        final at = text.indexOf(k, cursor);
        if (at >= 0 && at < position) {
          token = k;
          position = at;
        }
      }
      if (token == null) {
        spans.add(TextSpan(text: text.substring(cursor)));
        break;
      }
      if (position > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, position)));
      }
      final selected = token;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Semantics(
            label: selected,
            child: Image.network(
              comment.emotes[selected].toString(),
              cacheWidth: 84,
              cacheHeight: 84,
              width: 28,
              height: 28,
              errorBuilder: (_, error, stack) => Text(selected),
            ),
          ),
        ),
      );
      cursor = position + selected.length;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (prefix.isNotEmpty)
          Wrap(
            spacing: 4,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (comment.level != null &&
                  comment.level! >= 0 &&
                  comment.level! <= 6)
                BiliLevelBadge(level: comment.level!),
              if (comment.verifyType == 0 || comment.verifyType == 1)
                BiliVerifyBadge(type: comment.verifyType!),
              if (comment.vipLabel != null)
                Text(
                  comment.vipLabel!,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              if (comment.medalName != null)
                Text(
                  '${comment.medalName} ${comment.medalLevel ?? ''}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ),
        SelectionArea(
          child: Text.rich(
            TextSpan(children: spans),
            style: compact ? styles.previewBody : styles.body,
          ),
        ),
        if (comment.pictures.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var index = 0; index < comment.pictures.length; index++)
                  Semantics(
                    label: '查看评论图片',
                    button: true,
                    child: InkWell(
                      onTap: () =>
                          showImageViewer(context, comment.pictures, index),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: AppNetworkImage(
                          url: publicImageThumbnail(
                            comment.pictures[index],
                            width: 264,
                          ).toString(),
                          cacheWidth: 264,
                          cacheHeight: 264,
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                          errorBuilder: (_, error, stack) => const SizedBox(
                            width: 88,
                            height: 88,
                            child: Center(child: Text('图片加载失败')),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class CommentAuthorHeader extends StatelessWidget {
  const CommentAuthorHeader({
    super.key,
    required this.comment,
    this.onOpenUser,
  });
  final CommentEntry comment;
  final ValueChanged<UserId>? onOpenUser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), c = comment;
    final styles = CommentTextStyles(theme);
    final time = c.publishedAt?.toLocal();
    final location = c.ipLocation?.trim();
    final hasLocation = location != null && location.isNotEmpty;
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 5,
          runSpacing: 3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            InkWell(
              onTap: c.authorId?.isValid == true && onOpenUser != null
                  ? () => onOpenUser!(c.authorId!)
                  : null,
              child: Text(
                c.author,
                style: styles.author.copyWith(
                  color: c.vipLabel != null
                      ? theme.colorScheme.primary
                      : styles.author.color,
                ),
              ),
            ),
            if (c.level != null && c.level! >= 0 && c.level! <= 6)
              BiliLevelBadge(level: c.level!),
            if (c.verifyType == 0 || c.verifyType == 1)
              BiliVerifyBadge(type: c.verifyType!),
            if (c.vipLabel != null)
              Text(
                c.vipLabel!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            if (c.medalName != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.primary),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '${c.medalName} ${c.medalLevel ?? ''}',
                  style: theme.textTheme.labelSmall,
                ),
              ),
          ],
        ),
        if (time != null || hasLocation)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Wrap(
              spacing: 8,
              runSpacing: 2,
              children: [
                if (time != null)
                  Text('${time.month}-${time.day}', style: styles.metadata),
                if (hasLocation) Text(location, style: styles.metadata),
              ],
            ),
          ),
      ],
    );
    if (c.decorationImageUrl == null) return identity;
    final decoration = CommentAuthorDecoration(comment: c);
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 220
          ? Row(
              children: [
                Expanded(child: identity),
                const SizedBox(width: 8),
                decoration,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                identity,
                const SizedBox(height: 2),
                Align(alignment: Alignment.centerRight, child: decoration),
              ],
            ),
    );
  }
}

class CommentAuthorDecoration extends StatelessWidget {
  const CommentAuthorDecoration({super.key, required this.comment});
  final CommentEntry comment;

  @override
  Widget build(BuildContext context) {
    final url = comment.decorationImageUrl;
    if (url == null) return const SizedBox.shrink();
    final number = comment.decorationFanNumber;
    final rgb = comment.decorationFanColor;
    final color = rgb != null && rgb >= 0 && rgb <= 0xffffff
        ? Color(0xff000000 | rgb)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      label:
          '${comment.decorationName ?? '评论装扮'}${number == null ? '' : '，粉丝编号 $number'}',
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        width: 112,
        height: 40,
        child: ClipRect(
          child: Stack(
            children: [
              // 装扮画布右侧带留白；平移画布并裁剪，让可见图案靠右。
              Positioned(
                left: 40,
                right: -40,
                top: 0,
                bottom: 0,
                child: AppNetworkImage(
                  url: publicImageThumbnail(
                    url,
                    width: 336,
                    height: 120,
                  ).toString(),
                  cacheWidth: 336,
                  cacheHeight: 120,
                  fit: BoxFit.cover,
                  alignment: Alignment.centerRight,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              if (number != null && number.isNotEmpty)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 60,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'NO.\n$number',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(fontSize: 10, height: 1.1, color: color),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
