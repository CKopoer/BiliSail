import 'package:flutter/material.dart';

/// Typography from the official desktop client's comment components.
final class CommentTextStyles {
  CommentTextStyles(ThemeData theme)
    : _base = theme.textTheme.bodyMedium ?? const TextStyle(),
      _small = theme.textTheme.bodySmall ?? const TextStyle(),
      _label = theme.textTheme.labelMedium ?? const TextStyle(),
      _title = theme.textTheme.titleSmall ?? const TextStyle(),
      _dark = theme.brightness == Brightness.dark;

  final TextStyle _base;
  final TextStyle _small, _label, _title;
  final bool _dark;

  Color get _text => _dark ? const Color(0xFFE7E9EB) : const Color(0xFF18191C);
  Color get _secondary =>
      _dark ? const Color(0xFFA2A7AE) : const Color(0xFF61666D);
  Color get _muted => _dark ? const Color(0xFF757A81) : const Color(0xFF9499A0);
  Color get linkColor =>
      _dark ? const Color(0xFF2C9CC8) : const Color(0xFF008AC5);
  Color get _placeholder =>
      _dark ? const Color(0xFF46494D) : const Color(0xFFC9CCD0);

  TextStyle get body => _style(15, 25, _text);
  TextStyle get previewBody => _style(14, 20, _text);
  TextStyle get author => _style(13, 16.25, _secondary);
  TextStyle get previewAuthor => _style(14, 20, _secondary);
  TextStyle get metadata => _style(12, 15, _muted);
  TextStyle get action => _style(13, 16, _muted);
  TextStyle get sort => _style(12, 15, _text);
  TextStyle get link => _style(12, 15, linkColor);

  TextStyle get detailTitle =>
      _inherited(_title, 16, 20, _text, weight: FontWeight.w600);
  TextStyle get sectionTitle => _inherited(_title, 14, 17.5, _text);
  TextStyle get input => _inherited(_base, 14, 20, _text);
  TextStyle get inputHint => input.copyWith(color: _placeholder);
  TextStyle get disabledInput => _inherited(_base, 12, 15, _muted);
  TextStyle get submit => _inherited(_label, 14, 20, Colors.white);
  TextStyle get counter => _inherited(_label, 12, 15, _muted);
  TextStyle get badge => _inherited(_label, 12, 14, _secondary);
  TextStyle get footer => _inherited(_small, 13, 16.25, _muted);
  TextStyle get empty => _inherited(_base, 14, 17.5, _muted);

  // Preserve each component's inherited Material tracking, as requested.
  TextStyle _inherited(
    TextStyle base,
    double size,
    double lineHeight,
    Color color, {
    FontWeight weight = FontWeight.w400,
  }) => base.copyWith(
    fontSize: size,
    fontWeight: weight,
    height: lineHeight / size,
    color: color,
  );

  TextStyle _style(double size, double lineHeight, Color color) =>
      _base.copyWith(
        fontSize: size,
        fontWeight: FontWeight.w400,
        height: lineHeight / size,
        letterSpacing: 0,
        color: color,
      );
}
