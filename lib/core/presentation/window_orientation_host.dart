import 'dart:async';
import 'dart:ui' show FlutterView;

import 'package:flutter/widgets.dart';

import '../../domain/app_orientation.dart';
import '../platform/window_service.dart';
import '../platform/window_size_policy.dart';

class WindowOrientationHost extends StatefulWidget {
  const WindowOrientationHost({
    super.key,
    required this.window,
    this.orientation = AppOrientationPreference.automatic,
    required this.child,
  });

  final WindowService window;
  final AppOrientationPreference orientation;
  final Widget child;

  @override
  State<WindowOrientationHost> createState() => _WindowOrientationHostState();
}

class _WindowOrientationHostState extends State<WindowOrientationHost>
    with WidgetsBindingObserver {
  FlutterView? _view;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _view = View.of(context);
    _updateDisplay();
  }

  @override
  void didChangeMetrics() => _updateDisplay();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _updateDisplay();
  }

  void _updateDisplay() {
    final view = _view;
    if (view == null) return;
    final size = WindowSizePolicy.displaySize(view);
    if (size.isEmpty || !size.isFinite) return;
    unawaited(
      widget.window.updateDisplaySize(size, orientation: widget.orientation),
    );
  }

  @override
  void didUpdateWidget(covariant WindowOrientationHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.window, widget.window)) {
      unawaited(oldWidget.window.clearDisplayOrientationPolicy());
    }
    if (!identical(oldWidget.window, widget.window) ||
        oldWidget.orientation != widget.orientation) {
      _updateDisplay();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.window.clearDisplayOrientationPolicy());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
