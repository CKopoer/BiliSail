import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilisail/core/presentation/app_image_provider.dart';
import 'package:bilisail/core/storage/image_byte_cache.dart';
import 'package:bilisail/features/comments/domain/comments_repository.dart';
import 'package:bilisail/shared/ui/app_network_image.dart';
import 'package:bilisail/shared/ui/comment_rich_content.dart';
import 'package:bilisail/shared/ui/network_avatar.dart';
import 'package:bilisail/shared/ui/user_decoration_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('card keeps transparent canvas ratio and decodes for each DPI', (
    tester,
  ) async {
    final bytes = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(1200, 0, 300, 300),
        Paint()..color = Colors.blue,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(1800, 300);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      return data!.buffer.asUint8List();
    });
    final loaded = <Uri>[];
    final cache = AppImageCache(
      ImageByteCache(
        directory: () async => throw const FileSystemException('optional'),
        loader: (uri, _) async {
          loaded.add(uri);
          return bytes!;
        },
      ),
    );
    final url = Uri.https('i0.hdslb.com', '/card.png');
    for (final dpr in [1.0, 1.25, 3.0, 4.0]) {
      await tester.pumpWidget(
        AppImageCacheScope(
          cache: cache,
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(devicePixelRatio: dpr),
              child: Center(
                child: CommentAuthorDecoration(
                  comment: CommentEntry(
                    id: '1',
                    author: 'a',
                    message: '',
                    decorationImageUrl: url,
                    decorationFanNumber: '000123',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      for (var attempt = 0; attempt < 80; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        final raw = tester.widgetList<RawImage>(find.byType(RawImage));
        if (raw.isNotEmpty && raw.single.image?.height == (52 * dpr).ceil()) {
          break;
        }
      }
      final decoded = tester.widget<RawImage>(find.byType(RawImage)).image!;
      expect(decoded.height, (52 * dpr).ceil());
      expect(decoded.width, decoded.height * 6);
      final imageRect = tester.getRect(find.byType(UserDecorationImage));
      expect(imageRect.size, const Size(312, 52));
      expect(tester.getRect(find.text('NO.\n000123')).right, imageRect.right);
      // Wide card canvases have a large transparent left margin. The art
      // stays left of the serial, which overlays the transparent right.
      final pixels = await tester.runAsync(() => decoded.toByteData());
      expect(pixels!.getUint8(3), 0);
      expect(pixels.getUint8((decoded.width * 3 ~/ 4) * 4 + 3), 255);
      expect(pixels.getUint8((decoded.width - 1) * 4 + 3), 0);
      expect(tester.takeException(), isNull);
    }
    expect(loaded.toSet(), {url});
    await tester.pumpWidget(const SizedBox());
    await cache.close();
  });

  testWidgets('pendant surrounds the avatar without changing its tap area', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: GestureDetector(
            onTap: () => taps++,
            child: NetworkAvatar(
              radius: 20,
              name: '作者',
              pendantUrl: Uri.https('i0.hdslb.com', '/pendant.gif'),
            ),
          ),
        ),
      ),
    );
    final avatar = tester.getRect(find.byType(NetworkAvatar));
    final portrait = tester.getRect(find.byType(ClipOval));
    final pendant = tester.getRect(find.byType(UserDecorationImage));
    expect(avatar.size, const Size.square(40));
    expect(portrait.size, const Size.square(34));
    expect(pendant.size, const Size.square(59.5));
    expect(pendant.center, avatar.center);
    final image = tester.widget<AppNetworkImage>(find.byType(AppNetworkImage));
    expect(image.url, 'https://i0.hdslb.com/pendant.gif');
    expect(image.cacheWidth, isNull);
    await tester.tap(find.byType(NetworkAvatar));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
