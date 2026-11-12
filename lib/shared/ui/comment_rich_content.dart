import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/presentation/public_image_variant.dart';
import '../../domain/user.dart';
import 'app_network_image.dart';
import 'bili_badges.dart';
import 'image_viewer.dart';
import '../../features/comments/domain/comment_text.dart';
import '../../features/comments/domain/comment_time.dart';
import '../../features/comments/domain/comments_repository.dart';
import 'comment_text_styles.dart';
import 'user_decoration_image.dart';
import 'comment_badge.dart';
import 'network_avatar.dart';

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

class CommentRichContent extends StatefulWidget {
  const CommentRichContent({
    super.key,
    required this.comment,
    this.prefix = '',
    this.compact = false,
    this.onOpenLink,
    this.onSeek,
    this.onOpenUser,
  });
  final CommentEntry comment;
  final String prefix;
  final bool compact;
  final ValueChanged<Uri>? onOpenLink;
  final ValueChanged<Duration>? onSeek;
  final ValueChanged<UserId>? onOpenUser;
  @override
  State<CommentRichContent> createState() => _CommentRichContentState();
}

class _CommentRichContentState extends State<CommentRichContent> {
  List<CommentTextPart> _parts = const [];
  final _recognizers = <int, TapGestureRecognizer>{};

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(covariant CommentRichContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comment.message != widget.comment.message ||
        !identical(oldWidget.comment.emotes, widget.comment.emotes) ||
        !identical(
          oldWidget.comment.mentionedUsers,
          widget.comment.mentionedUsers,
        )) {
      _parse();
    }
  }

  void _parse() {
    _disposeRecognizers();
    _parts = parseCommentText(
      widget.comment.message,
      emoteTokens: widget.comment.emotes.keys,
      mentionedUsers: widget.comment.mentionedUsers,
    );
    for (var i = 0; i < _parts.length; i++) {
      final part = _parts[i];
      if (part.kind == CommentTextKind.link ||
          part.kind == CommentTextKind.timestamp ||
          part.kind == CommentTextKind.mention) {
        _recognizers[i] = TapGestureRecognizer();
      }
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers.values) {
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
  Widget build(BuildContext context) {
    final comment = widget.comment, prefix = widget.prefix;
    final styles = CommentTextStyles(Theme.of(context));
    final spans = <InlineSpan>[if (prefix.isNotEmpty) TextSpan(text: prefix)];
    for (var i = 0; i < _parts.length; i++) {
      final part = _parts[i];
      if (part.kind != CommentTextKind.emote) {
        final recognizer = _recognizers[i];
        final url = part.url, position = part.position;
        final open = widget.onOpenLink, seek = widget.onSeek;
        final userId = part.userId, openUser = widget.onOpenUser;
        final VoidCallback? onTap = url != null && open != null
            ? () => open(url)
            : position != null && seek != null
            ? () => seek(position)
            : userId != null && openUser != null
            ? () => openUser(userId)
            : null;
        recognizer?.onTap = onTap;
        spans.add(
          TextSpan(
            text: part.text,
            style:
                recognizer == null ||
                    (part.kind == CommentTextKind.mention && onTap == null)
                ? null
                : TextStyle(color: styles.linkColor),
            recognizer: onTap == null ? null : recognizer,
            mouseCursor: onTap == null ? null : SystemMouseCursors.click,
          ),
        );
        continue;
      }
      final selected = part.text;
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
                Text(comment.vipLabel!, style: styles.badge),
              if (comment.medalName != null)
                Text(
                  '${comment.medalName} ${comment.medalLevel ?? ''}',
                  style: styles.badge,
                ),
            ],
          ),
        SelectionArea(
          // 回复预览外层的 InkWell 会让正文继承按钮光标。
          child: DefaultSelectionStyle.merge(
            mouseCursor: SystemMouseCursors.text,
            child: Text.rich(
              TextSpan(children: spans),
              style: widget.compact ? styles.previewBody : styles.body,
            ),
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
                            // Resizing decoded pixels alone still downloads the
                            // full GIF, which can exceed the byte-cache limit.
                            resizeAnimated: true,
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
        if (comment.upLiked || comment.upReplied)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                if (comment.upLiked)
                  Text(
                    'UP 主觉得很赞',
                    style: styles.badge.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                if (comment.upReplied)
                  Text(
                    'UP 主回复过',
                    style: styles.badge.copyWith(
                      color: Theme.of(context).colorScheme.primary,
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

  // Body starts after the 30px avatar and 12px gap.
  static const contentIndent = 42.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), c = comment;
    final styles = CommentTextStyles(theme);
    final time = commentTimeLabel(c.publishedAt);
    final location = c.ipLocation?.trim();
    final hasLocation = location != null && location.isNotEmpty;
    final identity = Column(
      mainAxisSize: MainAxisSize.min,
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
                  color: c.nicknameColor != null
                      ? Color(0xFF000000 | c.nicknameColor!)
                      : styles.author.color,
                ),
              ),
            ),
            if (c.isUpAuthor) const CommentBadge(label: 'UP'),
            if (c.isPinned) const CommentBadge(label: '置顶', outlined: true),
            if (c.level != null && c.level! >= 0 && c.level! <= 6)
              BiliLevelBadge(level: c.level!),
            if (c.verifyType == 0 || c.verifyType == 1)
              BiliVerifyBadge(type: c.verifyType!),
            if (c.vipLabel != null)
              Text(
                c.vipLabel!,
                style: styles.badge.copyWith(
                  color: c.nicknameColor != null
                      ? Color(0xFF000000 | c.nicknameColor!)
                      : theme.colorScheme.primary,
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
                  style: styles.badge,
                ),
              ),
          ],
        ),
        if (time.isNotEmpty || hasLocation)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Wrap(
              spacing: 8,
              runSpacing: 2,
              children: [
                if (time.isNotEmpty) Text(time, style: styles.metadata),
                if (hasLocation) Text(location, style: styles.metadata),
              ],
            ),
          ),
      ],
    );
    final author = Row(
      children: [
        InkWell(
          onTap: c.authorId?.isValid == true && onOpenUser != null
              ? () => onOpenUser!(c.authorId!)
              : null,
          child: NetworkAvatar(
            url: c.avatarUrl,
            pendantUrl: c.pendantUrl,
            name: c.author,
            radius: 15,
          ),
        ),
        const SizedBox(width: contentIndent - 30),
        Expanded(child: identity),
      ],
    );
    if (c.decorationImageUrl == null) return author;
    final decoration = CommentAuthorDecoration(comment: c);
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = (constraints.maxWidth - contentIndent).clamp(
          0.0,
          double.infinity,
        );
        final spacing = contentWidth.clamp(0.0, 8.0);
        final decorationWidth = ((contentWidth - spacing) * .4).clamp(
          0.0,
          112.0,
        );
        return Row(
          children: [
            // Keep the avatar, name and metadata on one center with the card.
            Expanded(child: author),
            SizedBox(width: spacing),
            // Keep the art beside the avatar and leave most of the row for
            // readable author metadata, scaling the art and serial together.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: decorationWidth),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: decoration,
              ),
            ),
          ],
        );
      },
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
        height: 52,
        child: Stack(
          // Wide canvases include transparent left margins. Keep their natural
          // width instead of shrinking the character to fit the reserved slot.
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: UserDecorationImage(url: url, height: 52),
            ),
            if (number != null && number.isNotEmpty)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 92,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'NO.\n$number',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.1,
                      fontWeight: FontWeight.bold,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: color,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
