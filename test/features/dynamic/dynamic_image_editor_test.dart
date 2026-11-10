import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bilisail/domain/local_image.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:bilisail/shared/ui/dynamic_image_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<Uint8List> image() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 100, 50),
      Paint()..color = const Color(0xFFFF0000),
    );
    canvas.drawRect(
      const Rect.fromLTWH(50, 0, 50, 50),
      Paint()..color = const Color(0xFF0000FF),
    );
    final picture = recorder.endRecording();
    final source = await picture.toImage(100, 50);
    final data = await source.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    source.dispose();
    return data!.buffer.asUint8List();
  }

  testWidgets(
    'preview keeps non-square geometry and crop returns the selected original pixels',
    (tester) async {
      final bytes = await tester.runAsync(image);
      LocalImage? result;
      await tester.pumpWidget(
        MaterialApp(
          home: AppNoticeHost(
            child: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await showDialog<LocalImage>(
                      context: context,
                      builder: (_) => DynamicImageEditor(
                        image: LocalImage(bytes!, 'image/png'),
                      ),
                    );
                  },
                  child: const Text('预览'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('预览'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('裁剪'));
      await tester.pumpAndSettle();
      final box = tester.getRect(
        find.byKey(const ValueKey('dynamic-crop-surface')),
      );
      expect(box.width / box.height, closeTo(2, .01));
      await tester.runAsync(() async {
        await tester.tap(find.text('应用裁剪'));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      expect(result?.mimeType, 'image/png');
      final codec = await tester.runAsync(
        () => ui.instantiateImageCodec(result!.bytes),
      );
      final frame = await tester.runAsync(codec!.getNextFrame);
      expect((frame!.image.width, frame.image.height), (80, 40));
      final pixels = await tester.runAsync(frame.image.toByteData);
      expect(
        pixels!.getUint8(0),
        255,
      ); // Red at left; the crop was not rescaled.
      expect(pixels.getUint8((80 - 1) * 4 + 2), 255); // Blue at right.
      frame.image.dispose();
      codec.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'animated images stay available for preview without flattening crop',
    (tester) async {
      final bytes = await tester.runAsync(image);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DynamicImageEditor(image: LocalImage(bytes!, 'image/gif')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('裁剪'), findsNothing);
      expect(find.byType(InteractiveViewer), findsOneWidget);
    },
  );
}
