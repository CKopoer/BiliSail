import 'dart:ui' show FlutterView, Size;

import 'package:flutter/foundation.dart';

abstract final class WindowSizePolicy {
  static const expandedWidth = 600.0;

  static bool isMobile(TargetPlatform platform) =>
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;

  static Size displaySize(FlutterView view) {
    final display = view.display;
    final size = _logicalSize(display.size, display.devicePixelRatio);
    if (!size.isEmpty) return size;
    // A cached Android engine can report -1 for both size and density before
    // its Activity publishes display metrics. Dividing those first yields 1dp.
    return _logicalSize(view.physicalSize, view.devicePixelRatio);
  }

  static Size _logicalSize(Size physicalSize, double density) {
    if (physicalSize.isEmpty ||
        !physicalSize.isFinite ||
        !density.isFinite ||
        density <= 0) {
      return Size.zero;
    }
    final size = physicalSize / density;
    return size.isFinite ? size : Size.zero;
  }

  static double availableWidth(FlutterView view) =>
      (view.physicalSize.width - view.padding.left - view.padding.right) /
      view.devicePixelRatio;

  static bool compactDisplay(Size size) => size.shortestSide < expandedWidth;

  static bool compactLayout({
    required bool mobile,
    required Size displaySize,
    required double availableWidth,
  }) =>
      availableWidth < expandedWidth || (mobile && compactDisplay(displaySize));
}
