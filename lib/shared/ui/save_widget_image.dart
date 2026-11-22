import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

Future<Uint8List> captureWidgetPng(
  GlobalKey key, {
  double pixelRatio = 1,
}) async {
  final boundary = key.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary) throw StateError('Missing preview');
  final size = boundary.size * pixelRatio;
  if (size.height > 20000 || size.width * size.height > 40000000) {
    throw StateError('Preview too large');
  }
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null || data.lengthInBytes > 32 * 1024 * 1024) {
      throw StateError('Snapshot too large');
    }
    return Uint8List.sublistView(data);
  } finally {
    image.dispose();
  }
}
