import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MobilePlaybackStatusBar extends StatelessWidget {
  const MobilePlaybackStatusBar({
    super.key,
    required this.enabled,
    required this.builder,
  });

  final bool enabled;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final child = builder(context);
    if (!enabled ||
        (platform != TargetPlatform.android &&
            platform != TargetPlatform.iOS)) {
      return child;
    }
    // Edge-to-edge Android ignores the requested status bar color. Paint the
    // existing safe area without changing the content's insets or bottom bar.
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: MediaQuery.paddingOf(context).top,
          child: const IgnorePointer(
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark,
                systemStatusBarContrastEnforced: false,
              ),
              child: ColoredBox(color: Colors.black),
            ),
          ),
        ),
      ],
    );
  }
}
