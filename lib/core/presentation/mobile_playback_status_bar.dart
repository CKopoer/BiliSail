import 'dart:ui' show FlutterView;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/window_size_policy.dart';

class MobilePlaybackStatusBar extends StatefulWidget {
  const MobilePlaybackStatusBar({
    super.key,
    required this.enabled,
    required this.builder,
  });

  final bool enabled;
  final WidgetBuilder builder;

  @override
  State<MobilePlaybackStatusBar> createState() =>
      _MobilePlaybackStatusBarState();
}

class _MobilePlaybackStatusBarState extends State<MobilePlaybackStatusBar>
    with WidgetsBindingObserver {
  FlutterView? _view;
  bool _compactDisplay = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final view = _view = View.of(context);
    _compactDisplay = WindowSizePolicy.compactDisplay(
      WindowSizePolicy.displaySize(view),
    );
  }

  @override
  void didChangeMetrics() {
    final view = _view;
    if (view == null) return;
    final compact = WindowSizePolicy.compactDisplay(
      WindowSizePolicy.displaySize(view),
    );
    // Folding can change only the display while a split window stays the same
    // size, in which case MediaQuery alone does not rebuild this widget.
    if (compact != _compactDisplay) setState(() => _compactDisplay = compact);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final padding = MediaQuery.paddingOf(context);
    final child = widget.builder(context);
    if (!widget.enabled || !WindowSizePolicy.isMobile(platform)) {
      return child;
    }
    // Edge-to-edge Android ignores the requested status bar color. Paint the
    // existing safe area without changing the content's insets or bottom bar.
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (_compactDisplay)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            // Hidden bars report zero padding. Keep the style at the top sample
            // point so showing them during rotation cannot restore dark icons.
            height: padding.top > 0 ? padding.top : 1,
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
