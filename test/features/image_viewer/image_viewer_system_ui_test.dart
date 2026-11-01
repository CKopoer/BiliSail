import 'dart:async';
import 'dart:ui' as ui;

import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/presentation/android_system_ui.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/image_viewer/application/image_viewer_controller.dart';
import 'package:bilisail/features/image_viewer/domain/original_image.dart';
import 'package:bilisail/shared/ui/image_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/input_test_app.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(900, 600)]) {
    for (final dark in [false, true]) {
      testWidgets(
        'image preview paints behind system bars at $size, dark=$dark',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          const padding = FakeViewPadding(
            top: 24,
            bottom: 24,
            left: 16,
            right: 16,
          );
          tester.view.padding = padding;
          tester.view.viewPadding = padding;
          addTearDown(tester.view.reset);
          final theme = dark ? BiliTheme.dark() : BiliTheme.light();
          final repository = _PendingRepository();
          final boundary = GlobalKey();
          final styles = <Map<Object?, Object?>>[];
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'SystemChrome.setSystemUIOverlayStyle') {
                styles.add(call.arguments as Map<Object?, Object?>);
              }
              return null;
            },
          );
          addTearDown(() {
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              SystemChannels.platform,
              null,
            );
          });
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                originalImageRepositoryProvider.overrideWithValue(repository),
              ],
              child: RepaintBoundary(
                key: boundary,
                child: InputTestApp(
                  theme: theme,
                  builder: (_, child) => AndroidSystemUi(child: child!),
                  home: Builder(
                    builder: (context) => Scaffold(
                      backgroundColor: Colors.orange,
                      body: Center(
                        child: TextButton(
                          onPressed: () => showImageViewer(context, [
                            Uri.https('i0.hdslb.com', '/original.png'),
                          ], 0),
                          child: const Text('查看'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('查看'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('正在加载原图…'), findsOneWidget);
          expect(tester.getRect(find.byType(Dialog)), Offset.zero & size);
          final close = tester.getRect(find.byTooltip('关闭图片'));
          expect(close.top, greaterThanOrEqualTo(24));
          expect(close.right, lessThanOrEqualTo(size.width - 16));
          expect(
            tester.getRect(find.byTooltip('放大')).bottom,
            lessThanOrEqualTo(size.height - 24),
          );
          await _expectInsetPixels(tester, boundary, theme.colorScheme.surface);

          repository.result.completeError(StateError('image unavailable'));
          await tester.pumpAndSettle();
          expect(find.text('原图无法读取，请重试'), findsOneWidget);
          await _expectInsetPixels(tester, boundary, theme.colorScheme.surface);
          await tester.tap(find.text('重试'));
          await tester.pump();
          final image = await tester.runAsync(() async {
            final recorder = ui.PictureRecorder();
            Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
            final picture = recorder.endRecording();
            final image = await picture.toImage(32, 32);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            image.dispose();
            picture.dispose();
            return OriginalImage(
              bytes: bytes!.buffer.asUint8List(),
              width: 32,
              height: 32,
            );
          });
          repository.result.complete(image);
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pumpAndSettle();
          expect(find.byType(InteractiveViewer), findsOneWidget);
          await _expectInsetPixels(
            tester,
            boundary,
            theme.colorScheme.surface,
            tint: Colors.blue.withValues(alpha: .14),
          );
          expect(styles.last['systemNavigationBarColor'], 0);
          expect(styles.last['systemNavigationBarContrastEnforced'], false);
          expect(
            styles.last['systemNavigationBarIconBrightness'],
            '${dark ? Brightness.light : Brightness.dark}',
          );
          await tester.tap(find.byTooltip('关闭图片'));
          await tester.pumpAndSettle();
          expect(find.byType(ImageViewer), findsNothing);
          expect(find.text('查看'), findsOneWidget);
          expect(styles.last['systemNavigationBarColor'], 0);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.android),
      );
    }
  }
}

Future<void> _expectInsetPixels(
  WidgetTester tester,
  GlobalKey boundary,
  Color expected, {
  Color? tint,
}) async {
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = (await tester.runAsync(() => render.toImage()))!;
  final pixels = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  for (final (x, y) in [
    (image.width ~/ 2, 0),
    (image.width ~/ 2, image.height - 1),
    (0, image.height ~/ 2),
    (image.width - 1, image.height ~/ 2),
  ]) {
    final offset = (y * image.width + x) * 4;
    final actual = [for (var i = 0; i < 4; i++) pixels.getUint8(offset + i)];
    List<int> rgba(Color color) {
      final argb = color.toARGB32();
      return [argb >> 16 & 255, argb >> 8 & 255, argb & 255, argb >> 24 & 255];
    }

    final base = rgba(expected);
    final blended = rgba(
      Color.alphaBlend(tint ?? Colors.transparent, expected),
    );
    // Blur fades at image edges. Every inset must still contain the preview's
    // tint, rather than an uncovered strip of the page or modal barrier.
    for (var i = 0; i < 4; i++) {
      final low = base[i] < blended[i] ? base[i] : blended[i];
      final high = base[i] > blended[i] ? base[i] : blended[i];
      expect(
        actual[i],
        inInclusiveRange(low - 1, high + 1),
        reason: 'inset pixel ($x, $y)',
      );
    }
    if (tint != null) expect(actual, isNot(orderedEquals(base)));
  }
  image.dispose();
}

class _PendingRepository implements OriginalImageRepository {
  var result = Completer<OriginalImage>();

  @override
  Future<OriginalImage> load(Uri source, RequestCancellation cancellation) {
    result = Completer<OriginalImage>();
    return result.future;
  }
}
