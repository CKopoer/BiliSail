import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../image_viewer/application/image_viewer_controller.dart';

typedef CommentImageSaver = Future<String?> Function(Uint8List png);

final commentImageSaverProvider = Provider<CommentImageSaver?>((ref) {
  final exporter = ref.watch(imageExportServiceProvider);
  return exporter.supported ? exporter.save : null;
});
