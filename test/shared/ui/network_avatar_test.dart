import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilisail/core/presentation/app_image_provider.dart';
import 'package:bilisail/core/storage/image_byte_cache.dart';
import 'package:bilisail/shared/ui/app_network_image.dart';
import 'package:bilisail/shared/ui/network_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'avatar fallback uses first complete character and stable dimensions',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(child: NetworkAvatar(name: '👩‍💻开发者', radius: 19)),
        ),
      );
      expect(find.text('👩‍💻'), findsOneWidget);
      expect(tester.getSize(find.byType(NetworkAvatar)), const Size(38, 38));
    },
  );
  testWidgets(
    'avatar image failure shows name and never receives account credentials',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: NetworkAvatar(
            url: Uri.parse('http://i0.hdslb.com/fail.jpg'),
            name: '作者',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('作'), findsOneWidget);
      final image = tester.widget<Image>(find.byType(Image));
      final provider =
          (image.image as ResizeImage).imageProvider as NetworkImage;
      expect(provider.url, 'https://i0.hdslb.com/fail.jpg@48w_48h_0e.webp');
      expect(
        provider.headers?.keys.map((key) => key.toLowerCase()),
        isNot(contains('cookie')),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('unsupported image scheme uses person fallback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: NetworkAvatar(url: Uri.parse('file:///private.jpg'))),
    );
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets(
    'avatars request display-sized thumbnails and reuse nearby sizes',
    (tester) async {
      final bytes = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 200, 200),
          Paint()..color = Colors.blue,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(200, 200);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        if (data == null) throw StateError('Missing PNG');
        return data.buffer.asUint8List();
      });
      if (bytes == null) throw StateError('Missing PNG');
      final loaded = <Uri>[];
      final cache = AppImageCache(
        ImageByteCache(
          directory: () async => throw const FileSystemException('optional'),
          loader: (uri, _) async {
            loaded.add(uri);
            return bytes;
          },
        ),
      );
      Widget page(double dpr, List<double> radii) => AppImageCacheScope(
        cache: cache,
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(devicePixelRatio: dpr),
            child: Row(
              children: [
                for (final radius in radii)
                  NetworkAvatar(
                    url: Uri.parse('https://i0.hdslb.com/avatar.jpg'),
                    radius: radius,
                  ),
              ],
            ),
          ),
        ),
      );
      Future<void> settled() async {
        for (var attempt = 0; attempt < 80; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
          final images = tester
              .widgetList<RawImage>(find.byType(RawImage))
              .toList();
          if (images.isNotEmpty &&
              images.every((image) => image.image != null)) {
            return;
          }
        }
        fail('Avatar did not settle');
      }

      await tester.pumpWidget(page(1, [17, 18]));
      await settled();
      expect(loaded.map((uri) => uri.path), ['/avatar.jpg@48w_48h_0e.webp']);
      expect(
        tester
            .widgetList<RawImage>(find.byType(RawImage))
            .map((image) => image.image?.width),
        [48, 48],
      );
      await tester.pumpWidget(page(3, [18, 19]));
      await settled();
      expect(loaded.last.path, '/avatar.jpg@128w_128h_0e.webp');
      expect(loaded.length, 2);
      expect(
        tester
            .widgetList<RawImage>(find.byType(RawImage))
            .map((image) => image.image?.width),
        [128, 128],
      );
      await tester.pumpWidget(page(1, [18]));
      expect(tester.widget<RawImage>(find.byType(RawImage)).image?.width, 48);
      expect(loaded.length, 2);
      await tester.pumpWidget(const SizedBox());
      await cache.close();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'avatar thumbnails preserve signed, animated and transformed URLs',
    (tester) async {
      for (final url in [
        'https://i0.hdslb.com/avatar.jpg?signature=example',
        'https://i0.hdslb.com/avatar.gif',
        'https://i0.hdslb.com/avatar.jpg@96w.jpg',
        'https://example.test/avatar.jpg',
      ]) {
        await tester.pumpWidget(
          MaterialApp(home: NetworkAvatar(url: Uri.parse(url))),
        );
        await tester.pumpAndSettle();
        final provider =
            tester.widget<Image>(find.byType(Image)).image as ResizeImage;
        expect((provider.imageProvider as NetworkImage).url, url);
      }
    },
  );
}
