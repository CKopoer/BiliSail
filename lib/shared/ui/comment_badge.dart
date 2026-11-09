import 'package:flutter/material.dart';

import 'comment_text_styles.dart';

class CommentBadge extends StatelessWidget {
  const CommentBadge({super.key, required this.label, this.outlined = false});

  final String label;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: outlined ? null : colors.primaryContainer,
        border: outlined ? Border.all(color: colors.primary) : null,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: CommentTextStyles(theme).badge.copyWith(
          color: outlined ? colors.primary : colors.onPrimaryContainer,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
