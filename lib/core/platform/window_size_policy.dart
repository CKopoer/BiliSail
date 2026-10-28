import 'dart:ui' show FlutterView, Size;

import 'package:flutter/foundation.dart';

abstract final class WindowSizePolicy {
  static const expandedWidth = 600.0;

  static bool isMobile(TargetPlatform platform) =>
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;

  static Size displaySize(FlutterView view) =>
      view.display.size / view.display.devicePixelRatio;

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
