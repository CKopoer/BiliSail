import 'package:flutter/widgets.dart';

import '../../features/live/application/live_card_preview_controller.dart';

class LiveCardPreviewScope extends InheritedWidget {
  const LiveCardPreviewScope({
    super.key,
    required this.controller,
    required this.enabled,
    required super.child,
  });

  final LiveCardPreviewController controller;
  final bool enabled;

  static LiveCardPreviewScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LiveCardPreviewScope>();

  @override
  bool updateShouldNotify(LiveCardPreviewScope oldWidget) =>
      controller != oldWidget.controller || enabled != oldWidget.enabled;
}
