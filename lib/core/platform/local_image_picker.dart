import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/app_failure.dart';
import '../../domain/local_image.dart';

Future<List<LocalImage>> pickLocalImages(
  int remaining, {
  ImagePicker? imagePicker,
  String label = '图片',
  int maxCount = LocalImage.maxCount,
}) async {
  final limit = remaining.clamp(0, maxCount.clamp(1, 18));
  if (limit == 0) return const [];
  final mobile =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  final files = mobile
      ? await (imagePicker ?? ImagePicker()).pickMultiImage(
          limit: limit,
          // Only selected image contents are needed, not the complete library
          // or extra metadata permissions on iOS.
          requestFullMetadata: false,
        )
      : await openFiles(
          acceptedTypeGroups: [
            XTypeGroup(
              label: label,
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
  if (files.length > limit) {
    throw AppFailure(AppFailureKind.storage, '本次最多可添加 $limit 张图片，请重新选择');
  }
  final images = <LocalImage>[];
  for (final file in files) {
    if (await file.length() > LocalImage.maxBytes) {
      throw const AppFailure(AppFailureKind.storage, '每张图片不能超过 10 MB');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > LocalImage.maxBytes) {
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
    images.add(LocalImage(bytes, mime));
  }
  return List.unmodifiable(images);
}
