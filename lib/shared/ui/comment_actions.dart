import 'package:flutter/material.dart';

import '../../features/comments/domain/comments_repository.dart';
import 'bili_icons.dart';
import 'comment_text_styles.dart';

class CommentActions extends StatelessWidget {
  const CommentActions({
    super.key,
    required this.comment,
    required this.busy,
    required this.onLike,
    required this.onReply,
  });

  final CommentEntry comment;
  final bool busy;
  final VoidCallback onLike, onReply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = CommentTextStyles(theme).action;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Row(
        children: [
          Flexible(
            child: _CommentActionButton(
              icon: comment.liked
                  ? Icons.thumb_up_alt
                  : Icons.thumb_up_alt_outlined,
              label: '${comment.likeCount}',
              semanticLabel: comment.liked ? '取消点赞评论' : '点赞评论',
              selected: comment.liked,
              style: comment.liked
                  ? style.copyWith(color: theme.colorScheme.primary)
                  : style,
              onPressed: busy ? null : onLike,
            ),
          ),
          const SizedBox(width: 12),
          _CommentActionButton(
            icon: BiliIcons.reply,
            label: '回复',
            semanticLabel: '回复评论',
            style: style,
            onPressed: busy ? null : onReply,
          ),
        ],
      ),
    );
  }
}

class _CommentActionButton extends StatelessWidget {
  const _CommentActionButton({
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.style,
    required this.onPressed,
    this.selected,
  });

  final IconData icon;
  final String label, semanticLabel;
  final TextStyle style;
  final VoidCallback? onPressed;
  final bool? selected;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    value: selected == null ? null : label,
    button: true,
    selected: selected,
    enabled: onPressed != null,
    onTap: onPressed,
    excludeSemantics: true,
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(48, 32),
        alignment: Alignment.centerLeft,
        visualDensity: VisualDensity.standard,
        tapTargetSize: Theme.of(context).materialTapTargetSize,
        foregroundColor: style.color,
        textStyle: style,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    ),
  );
}
