import 'dart:ui' as ui;

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/image_viewer/application/image_viewer_controller.dart';
import 'package:bilisail/features/image_viewer/data/network_original_image_repository.dart';
import 'package:bilisail/features/image_viewer/domain/original_image.dart';
import 'package:bilisail/shared/ui/image_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> png() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(24, 16);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (data == null) throw StateError('PNG encoding failed');
  return data.buffer.asUint8List();
}

void main() {
  testWidgets(
    'original data exceeds thumbnail cap, remains full size and is cancelled on close',
    (tester) async {
      final bytes = await tester.runAsync(png);
      if (bytes == null) throw StateError('PNG missing');
      final padded = Uint8List(5 * 1024 * 1024)..setAll(0, bytes);
      var maxBytes = 0;
      final repository = NetworkOriginalImageRepository(
        loader: (_, request) async {
          maxBytes = request.maxBytes;
          return padded;
        },
      );
      final result = await tester.runAsync(
        () => repository.load(
          Uri.parse('https://i0.hdslb.com/original.png'),
          RequestCancellation(),
        ),
      );
      expect(result?.bytes, padded);
      expect(result?.width, 24);
      expect(result?.height, 16);
      expect(maxBytes, NetworkOriginalImageRepository.maxBytes);
      final cancellation = RequestCancellation()..cancel();
      await expectLater(
        repository.load(
          Uri.parse('https://i0.hdslb.com/original.png'),
          cancellation,
        ),
        throwsException,
      );
    },
  );

  for (final size in [const Size(1100, 740), const Size(360, 640)]) {
    testWidgets(
      'viewer ${size.width} supports zoom and original image navigation',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final bytes = await tester.runAsync(png);
        if (bytes == null) throw StateError('PNG missing');
        final repository = _Repository(
          OriginalImage(bytes: bytes, width: 24, height: 16),
        );
        final sources = [
          Uri.parse('https://i0.hdslb.com/a.png'),
          Uri.parse('https://i0.hdslb.com/b.png'),
        ];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              originalImageRepositoryProvider.overrideWithValue(repository),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showImageViewer(context, sources, 0),
                    child: const Text('查看'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('查看'));
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
        expect(find.text('1 / 2'), findsOneWidget);
        expect(find.text('100%'), findsOneWidget);
        final viewer = find.byType(InteractiveViewer);
        final viewport = tester.getRect(viewer);
        await tester.tapAt(viewport.center);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        await tester.dragFrom(viewport.center, const Offset(40, 20));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        await tester.tap(find.byTooltip('适应窗口'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('放大'));
        await tester.pump();
        expect(find.text('125%'), findsOneWidget);
        await tester.tap(find.byTooltip('缩小'));
        await tester.pump();
        expect(find.text('100%'), findsOneWidget);
        await tester.tap(find.byTooltip('下一张'));
        await tester.pumpAndSettle();
        expect(find.text('2 / 2'), findsOneWidget);
        expect(repository.sources, sources);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(find.text('1 / 2'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tapAt(viewport.topLeft + const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        await tester.tap(find.text('查看'));
        await tester.pumpAndSettle();
        await tester.tapAt(Offset(4, size.height - 4));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        await tester.tap(find.text('查看'));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
      },
    );
  }
}

class _Repository implements OriginalImageRepository {
  _Repository(this.image);
  final OriginalImage image;
  final sources = <Uri>[];
  @override
  Future<OriginalImage> load(
    Uri source,
    RequestCancellation cancellation,
  ) async {
    sources.add(source);
    return image;
  }
}
