import 'package:flutter/widgets.dart';

import 'danmaku_controller.dart';
import 'danmaku_layers.dart';

/// Shares one frame clock between independently retained moving and fixed text.
final class DanmakuOverlay extends StatelessWidget {
  const DanmakuOverlay({
    super.key,
    required this.controller,
    this.bottomInset = 0,
  });
  final DanmakuController controller;
  final double bottomInset;

  @override
  Widget build(BuildContext context) =>
      LayeredDanmakuOverlay(controller: controller, bottomInset: bottomInset);
}
