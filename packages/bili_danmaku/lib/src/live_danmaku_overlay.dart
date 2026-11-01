import 'package:flutter/widgets.dart';

import 'live_danmaku_controller.dart';
import 'danmaku_layers.dart';

/// Shares one frame clock between independently retained moving and fixed text.
final class LiveDanmakuOverlay extends StatelessWidget {
  const LiveDanmakuOverlay({
    super.key,
    required this.controller,
    this.bottomInset = 64,
  });
  final LiveDanmakuController controller;
  final double bottomInset;

  @override
  Widget build(BuildContext context) =>
      LayeredDanmakuOverlay(controller: controller, bottomInset: bottomInset);
}
