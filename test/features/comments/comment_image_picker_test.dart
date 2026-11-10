import 'dart:convert';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/core/platform/local_image_picker.dart';
import 'package:bilisail/features/comments/data/comment_image_picker.dart';
import 'package:bilisail/features/comments/domain/comment_composer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
);
XFile _image() => XFile.fromData(_png, name: 'photo.png');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      '$platform dynamic drafts request 18 slots without changing the comment default',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        final picker = _Picker(List.generate(18, (_) => _image()));
        expect(
          await pickLocalImages(18, imagePicker: picker, maxCount: 18),
          hasLength(18),
        );
        expect(picker.limit, 18);
        await expectLater(
          pickLocalImages(18, imagePicker: picker),
          throwsA(isA<AppFailure>()),
        );
        expect(picker.limit, 9);
      },
    );
    for (final remaining in [1, 2, 9]) {
      test('$platform opens the photo library with $remaining slots', () async {
        debugDefaultTargetPlatformOverride = platform;
        final picker = _Picker([_image()]);
        final images = await pickCommentImages(remaining, imagePicker: picker);
        expect(picker.limit, remaining);
        expect(picker.fullMetadata, isFalse);
        expect(images.single.mimeType, 'image/png');
        expect(images.single.bytes, orderedEquals(_png));
      });
    }

    test('$platform cancellation returns no attachments', () async {
      debugDefaultTargetPlatformOverride = platform;
      expect(await pickCommentImages(9, imagePicker: _Picker([])), isEmpty);
    });

    test('$platform rejects more images than remaining slots', () async {
      debugDefaultTargetPlatformOverride = platform;
      await expectLater(
        pickCommentImages(1, imagePicker: _Picker([_image(), _image()])),
        throwsA(isA<AppFailure>()),
      );
    });

    test(
      '$platform validates size and content after photo selection',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        for (final bytes in [
          Uint8List(0),
          Uint8List.fromList([1, 2, 3]),
          Uint8List(CommentLocalImage.maxBytes + 1),
        ]) {
          await expectLater(
            pickCommentImages(
              9,
              imagePicker: _Picker([
                XFile.fromData(bytes, name: 'misleading.jpg'),
              ]),
            ),
            throwsA(isA<AppFailure>()),
          );
        }
      },
    );

    test('$platform does not open a picker for a full draft', () async {
      debugDefaultTargetPlatformOverride = platform;
      final picker = _Picker([_image()]);
      expect(await pickCommentImages(0, imagePicker: picker), isEmpty);
      expect(picker.limit, isNull);
    });

    test('$platform picker errors never become empty success', () async {
      debugDefaultTargetPlatformOverride = platform;
      await expectLater(
        pickCommentImages(
          9,
          imagePicker: _Picker([])
            ..error = PlatformException(code: 'photo_access_denied'),
        ),
        throwsA(isA<PlatformException>()),
      );
    });
  }
}

class _Picker extends ImagePicker {
  _Picker(this.files);
  final List<XFile> files;
  int? limit;
  bool? fullMetadata;
  PlatformException? error;

  @override
  Future<List<XFile>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async {
    this.limit = limit;
    fullMetadata = requestFullMetadata;
    if (error case final error?) throw error;
    return files;
  }
}
