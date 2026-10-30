import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AndroidSystemUi extends StatelessWidget {
  const AndroidSystemUi({
    super.key,
    required this.child,
    this.backgroundColor,
    this.brightness,
  });

  final Widget child;
  final Color? backgroundColor;
  final Brightness? brightness;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (theme.platform != TargetPlatform.android) return child;
    final backgroundBrightness = brightness ?? theme.brightness;
    final dark = backgroundBrightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // MaterialApp's default styles both request a black navigation bar.
      // Android 15+ draws the gesture area transparently; older versions use
      // this surface color. Keep the annotation through route/theme changes.
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: backgroundBrightness,
        systemNavigationBarColor: backgroundColor ?? theme.colorScheme.surface,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: child,
    );
  }
}
