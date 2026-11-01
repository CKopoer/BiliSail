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
      // Keep the annotation through route/theme changes and let edge-to-edge
      // content paint behind the gesture/navigation bar on older Android
      // versions too — including route barriers and image-preview backgrounds.
      // Android 15+ enforces this for gesture navigation anyway; a transparent
      // bar also lets the liquid dock blur real content instead of a painted
      // surface strip.
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: backgroundBrightness,
        systemNavigationBarColor: backgroundColor ?? Colors.transparent,
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
