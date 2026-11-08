import 'package:flutter/material.dart';

abstract final class PageTabStyle {
  static const barHeight = 58.0;
  static const iconSize = 16.0;
  static const iconGap = 5.0;

  static ButtonStyle buttonStyle(
    BuildContext context, {
    double fontSize = 16,
  }) => TextButton.styleFrom(
    minimumSize: const Size(48, 42),
    padding: const EdgeInsets.symmetric(horizontal: 7),
    textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      height: 20 / fontSize,
    ),
  );

  static Widget label(String text, {IconData? icon}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (icon != null) ...[
        Icon(icon, size: iconSize),
        const SizedBox(width: iconGap),
      ],
      Text(text),
    ],
  );
}
