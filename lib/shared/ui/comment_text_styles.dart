import 'package:flutter/material.dart';

/// Typography from the official desktop client's comment components.
final class CommentTextStyles {
  CommentTextStyles(ThemeData theme)
    : _base = theme.textTheme.bodyMedium ?? const TextStyle(),
      _dark = theme.brightness == Brightness.dark;

  final TextStyle _base;
  final bool _dark;

  Color get _text => _dark ? const Color(0xFFE7E9EB) : const Color(0xFF18191C);
  Color get _secondary =>
      _dark ? const Color(0xFFA2A7AE) : const Color(0xFF61666D);
  Color get _muted => _dark ? const Color(0xFF757A81) : const Color(0xFF9499A0);

  TextStyle get body => _style(15, 25, _text);
  TextStyle get previewBody => _style(14, 20, _text);
  TextStyle get author => _style(13, 16.25, _secondary);
  TextStyle get previewAuthor => _style(14, 20, _secondary);
  TextStyle get metadata => _style(12, 15, _muted);
  TextStyle get action => _style(13, 16, _muted);
  TextStyle get sort => _style(12, 15, _text);

  TextStyle _style(double size, double lineHeight, Color color) =>
      _base.copyWith(
        fontSize: size,
        fontWeight: FontWeight.w400,
        height: lineHeight / size,
        letterSpacing: 0,
        color: color,
      );
}
