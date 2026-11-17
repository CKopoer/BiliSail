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

  static AppOrientationPreference orientationOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_WindowOrientationPreference>()
          ?.orientation ??
      AppOrientationPreference.automatic;

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
    widget.window.fullScreenOrientation.addListener(_presentationChanged);
  }

  void _presentationChanged() {
    _updateDisplay();
    setState(() {});
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
      widget.window.updateDisplaySize(
        size,
        orientation: widget.orientation,
        logicalWindowSize: view.physicalSize / view.devicePixelRatio,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant WindowOrientationHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.window, widget.window)) {
      oldWidget.window.fullScreenOrientation.removeListener(
        _presentationChanged,
      );
      widget.window.fullScreenOrientation.addListener(_presentationChanged);
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
    widget.window.fullScreenOrientation.removeListener(_presentationChanged);
    unawaited(widget.window.clearDisplayOrientationPolicy());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _WindowOrientationPreference(
      orientation: widget.orientation,
      child: widget.window.hasDesktopWindow ? _desktopViewport() : widget.child,
    );
  }

  Widget _desktopViewport() {
    // Keep this wrapper in automatic mode too, so choosing a direction never
    // reparents the Navigator, retained pages, or the active video surface.
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.biggest;
        var viewport = available;
        final display = WindowSizePolicy.displaySize(View.of(context));
        if (available.isFinite &&
            !available.isEmpty &&
            !display.isEmpty &&
            display.isFinite) {
          final portrait = switch (widget.window.fullScreenOrientation.value ??
              widget.orientation) {
            AppOrientationPreference.automatic => null,
            AppOrientationPreference.portrait => true,
            AppOrientationPreference.landscape => false,
          };
          if (portrait != null &&
              (portrait
                  ? available.width >= available.height
                  : available.width <= available.height)) {
            final displayRatio = display.shortestSide / display.longestSide;
            final portraitRatio = displayRatio < 1 ? displayRatio : 9 / 16;
            final ratio = portrait ? portraitRatio : 1 / portraitRatio;
            viewport = available.aspectRatio > ratio
                ? Size(available.height * ratio, available.height)
                : Size(available.width, available.width / ratio);
          }
        }
        return ColoredBox(
          color: const Color(0xFF000000),
          child: Center(
            child: SizedBox.fromSize(
              size: viewport,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(size: viewport),
                child: widget.child,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WindowOrientationPreference extends InheritedWidget {
  const _WindowOrientationPreference({
    required this.orientation,
    required super.child,
  });

  final AppOrientationPreference orientation;

  @override
  bool updateShouldNotify(_WindowOrientationPreference oldWidget) =>
      orientation != oldWidget.orientation;
}
