import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';

import '../../../domain/app_failure.dart';
import '../domain/comment_composer.dart';

Future<List<CommentLocalImage>> pickCommentImages(int remaining) async {
  final files = await openFiles(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: '评论图片',
        extensions: ['jpg', 'jpeg', 'png', 'gif'],
        mimeTypes: ['image/jpeg', 'image/png', 'image/gif'],
        uniformTypeIdentifiers: [
          'public.jpeg',
          'public.png',
          'com.compuserve.gif',
        ],
      ),
    ],
  );
  if (files.length > remaining) {
    throw const AppFailure(AppFailureKind.storage, '评论最多可添加 9 张图片，请重新选择');
  }
  final images = <CommentLocalImage>[];
  for (final file in files) {
    if (await file.length() > CommentLocalImage.maxBytes) {
      throw const AppFailure(AppFailureKind.storage, '每张图片不能超过 10 MB');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > CommentLocalImage.maxBytes) {
      throw const AppFailure(AppFailureKind.storage, '图片为空或超过 10 MB');
    }
    final mime =
        bytes.length >= 8 &&
            bytes[0] == 137 &&
            bytes[1] == 80 &&
            bytes[2] == 78 &&
            bytes[3] == 71
        ? 'image/png'
        : bytes.length >= 3 &&
              bytes[0] == 255 &&
              bytes[1] == 216 &&
              bytes[2] == 255
        ? 'image/jpeg'
        : bytes.length >= 6 &&
              String.fromCharCodes(bytes.take(6)).startsWith('GIF8')
        ? 'image/gif'
        : null;
    if (mime == null) {
      throw const AppFailure(AppFailureKind.storage, '请选择 JPG、PNG 或 GIF 图片');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width > 20000 ||
          descriptor.height > 20000 ||
          descriptor.width * descriptor.height > 40000000) {
        throw const AppFailure(AppFailureKind.storage, '图片尺寸过大，请缩小后添加');
      }
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
    images.add(CommentLocalImage(bytes, mime));
  }
  return List.unmodifiable(images);
}
