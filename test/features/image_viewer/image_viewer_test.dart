import '../../support/input_test_app.dart';

import 'dart:async';
import 'dart:ui' as ui;

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/image_export_service.dart';
import 'package:bilisail/features/image_viewer/application/image_viewer_controller.dart';
import 'package:bilisail/features/image_viewer/data/network_original_image_repository.dart';
import 'package:bilisail/features/image_viewer/domain/original_image.dart';
import 'package:bilisail/shared/ui/image_viewer.dart';
import 'package:flutter/gestures.dart';
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
    'Windows image wheel uses normal zoom after refocus with stale Control',
    (tester) async {
      final bytes = await tester.runAsync(png);
      if (bytes == null) throw StateError('PNG missing');
      final repository = _Repository(
        OriginalImage(bytes: bytes, width: 24, height: 16),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            originalImageRepositoryProvider.overrideWithValue(repository),
          ],
          child: InputTestApp(
            home: ImageViewer(
              request: ImageViewerRequest([
                Uri.parse('https://i0.hdslb.com/a.png'),
              ], 0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      final viewer = find.byType(InteractiveViewer);
      final transform = tester
          .widget<InteractiveViewer>(viewer)
          .transformationController;
      if (transform == null) throw StateError('Viewer transform missing');
      final initial = transform.value.clone();
      Future<void> wheel() async {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            kind: PointerDeviceKind.mouse,
            position: tester.getCenter(viewer),
            scrollDelta: const Offset(0, -40),
          ),
        );
        await tester.pump();
      }

      await wheel();
      final normalScale = transform.value.getMaxScaleOnAxis();
      expect(normalScale, greaterThan(initial.getMaxScaleOnAxis()));
      transform.value = initial.clone();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      for (final focused in [false, true]) {
        tester.binding.handleViewFocusChanged(
          ui.ViewFocusEvent(
            viewId: tester.view.viewId,
            state: focused
                ? ui.ViewFocusState.focused
                : ui.ViewFocusState.unfocused,
            direction: ui.ViewFocusDirection.undefined,
          ),
        );
        await tester.pump();
      }
      expect(HardwareKeyboard.instance.isControlPressed, isTrue);
      await wheel();
      expect(
        transform.value.getMaxScaleOnAxis(),
        closeTo(normalScale, .000001),
      );

      transform.value = initial.clone();
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlRight);
      await wheel();
      expect(transform.value.getMaxScaleOnAxis(), greaterThan(normalScale));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlRight);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
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
    testWidgets('viewer ${size.width} swipes between fitted images', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = await _swipeRepository(tester);
      final sources = await _openViewer(tester, repository);
      final viewport = find.byType(InteractiveViewer);
      final transform = tester
          .widget<InteractiveViewer>(viewport)
          .transformationController!;
      final fitted = transform.value.clone();
      expect(fitted.getMaxScaleOnAxis(), lessThan(1));

      Future<void> swipe(Offset delta) async {
        await tester.drag(viewport, delta);
        await tester.pumpAndSettle();
      }

      await swipe(const Offset(-120, 0));
      expect(find.text('3 / 3'), findsOneWidget);
      expect(repository.sources, [sources[1], sources[2]]);
      await swipe(const Offset(-120, 0));
      expect(find.text('3 / 3'), findsOneWidget);
      expect(repository.sources, hasLength(2));
      await swipe(const Offset(120, 0));
      expect(find.text('2 / 3'), findsOneWidget);
      await swipe(const Offset(120, 0));
      expect(find.text('1 / 3'), findsOneWidget);
      await swipe(const Offset(120, 0));
      expect(find.text('1 / 3'), findsOneWidget);
      expect(repository.sources, hasLength(4));

      for (final delta in [
        const Offset(-30, 0),
        const Offset(0, -140),
        const Offset(-100, -140),
      ]) {
        await swipe(delta);
        expect(find.text('1 / 3'), findsOneWidget);
        expect(transform.value, fitted);
      }
      final cancelled = await tester.startGesture(tester.getCenter(viewport));
      await cancelled.moveBy(const Offset(-120, 0));
      await cancelled.cancel();
      await tester.pumpAndSettle();
      expect(repository.sources, hasLength(4));
      expect(find.byType(ImageViewer), findsOneWidget);

      await swipe(const Offset(-120, 0));
      expect(find.text('2 / 3'), findsOneWidget);
      expect(transform.value, fitted);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'viewer ${size.width} preserves pinch zoom and enlarged panning',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = await _swipeRepository(tester);
        await _openViewer(tester, repository);
        final viewport = find.byType(InteractiveViewer);
        final transform = tester
            .widget<InteractiveViewer>(viewport)
            .transformationController!;
        final fitted = transform.value.clone();

        await tester.tap(find.byTooltip('放大'));
        await tester.pump();
        final enlarged = transform.value.clone();
        await tester.drag(viewport, const Offset(-120, 0));
        await tester.pumpAndSettle();
        expect(find.text('2 / 3'), findsOneWidget);
        expect(
          transform.value.getTranslation().x,
          lessThan(enlarged.getTranslation().x),
        );
        expect(
          transform.value.getMaxScaleOnAxis(),
          closeTo(enlarged.getMaxScaleOnAxis(), .000001),
        );
        await tester.tap(find.byTooltip('适应窗口'));
        await tester.pumpAndSettle();

        final center = tester.getCenter(viewport);
        final first = await tester.startGesture(center - const Offset(40, 0));
        final second = await tester.startGesture(
          center + const Offset(40, 0),
          pointer: 2,
        );
        await first.moveTo(center - const Offset(100, 0));
        await second.moveTo(center + const Offset(100, 0));
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          transform.value.getMaxScaleOnAxis(),
          greaterThan(fitted.getMaxScaleOnAxis()),
        );
        await first.moveTo(center - const Offset(20, 0));
        await second.moveTo(center + const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          transform.value.getMaxScaleOnAxis(),
          lessThan(fitted.getMaxScaleOnAxis()),
        );
        await second.up();
        await first.moveBy(const Offset(-120, 0));
        await first.up();
        await tester.pumpAndSettle();
        expect(find.text('2 / 3'), findsOneWidget);
        expect(repository.sources, hasLength(1));

        await tester.drag(viewport, const Offset(-120, 0));
        await tester.pumpAndSettle();
        expect(find.text('3 / 3'), findsOneWidget);
        expect(transform.value, fitted);
        expect(tester.takeException(), isNull);
      },
    );

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
        final exporter = _ExportService();
        final sources = [
          Uri.parse('https://i0.hdslb.com/a.png'),
          Uri.parse('https://i0.hdslb.com/b.png'),
        ];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              originalImageRepositoryProvider.overrideWithValue(repository),
              imageExportServiceProvider.overrideWithValue(exporter),
            ],
            child: InputTestApp(
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
        await tester.tap(find.byTooltip('保存图片'));
        await tester.pumpAndSettle();
        expect(find.text('已保存到 Pictures/BiliSail/test.png'), findsOneWidget);
        await tester.tap(find.byTooltip('复制图片'));
        await tester.pumpAndSettle();
        expect(find.text('图片已复制到剪贴板'), findsOneWidget);
        expect(exporter.saved, [bytes]);
        expect(exporter.copied, [bytes]);
        expect(repository.sources, hasLength(1));
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

  testWidgets('swiping during loading or failure cancels stale originals', (
    tester,
  ) async {
    final repository = _PendingRepository();
    await _openViewer(tester, repository, pending: true);
    final loading = find.text('正在加载原图…');
    await tester.drag(loading, const Offset(-120, 0));
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget);
    expect(repository.reads.first.cancellation.isCancelled, isTrue);
    final image = (await _swipeRepository(tester)).image;
    repository.reads.first.result.complete(image);
    await tester.pump();
    expect(loading, findsOneWidget);
    repository.reads[1].result.completeError(StateError('failed image'));
    await tester.pump();
    final failure = find.text('原图无法读取，请重试');
    expect(failure, findsOneWidget);
    await tester.drag(failure, const Offset(120, 0));
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);
    repository.reads[2].result.complete(image);
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(loading, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single original remains pannable without image paging', (
    tester,
  ) async {
    final repository = await _swipeRepository(tester);
    await _openViewer(tester, repository, count: 1, index: 0);
    final viewport = find.byType(InteractiveViewer);
    final transform = tester
        .widget<InteractiveViewer>(viewport)
        .transformationController!;
    final initial = transform.value.clone();
    await tester.drag(viewport, const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(
      transform.value.getTranslation().x,
      lessThan(initial.getTranslation().x),
    );
    expect(find.text('1 / 1'), findsOneWidget);
    expect(repository.sources, hasLength(1));
  });
}

Future<_Repository> _swipeRepository(WidgetTester tester) async {
  final bytes = await tester.runAsync(png);
  if (bytes == null) throw StateError('PNG missing');
  return _Repository(OriginalImage(bytes: bytes, width: 1200, height: 800));
}

Future<List<Uri>> _openViewer(
  WidgetTester tester,
  OriginalImageRepository repository, {
  int count = 3,
  int index = 1,
  bool pending = false,
}) async {
  final sources = List.generate(
    count,
    (index) => Uri.https('i0.hdslb.com', '/$index.png'),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        originalImageRepositoryProvider.overrideWithValue(repository),
      ],
      child: InputTestApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showImageViewer(context, sources, index),
              child: const Text('查看'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('查看'));
  if (pending) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  } else {
    await tester.pumpAndSettle();
  }
  return sources;
}

class _PendingRepository implements OriginalImageRepository {
  final reads =
      <({RequestCancellation cancellation, Completer<OriginalImage> result})>[];

  @override
  Future<OriginalImage> load(Uri source, RequestCancellation cancellation) {
    final result = Completer<OriginalImage>();
    reads.add((cancellation: cancellation, result: result));
    return result.future;
  }
}

class _ExportService implements ImageExportService {
  final saved = <Uint8List>[];
  final copied = <Uint8List>[];
  @override
  bool get supported => true;
  @override
  Future<String> save(Uint8List data) async {
    saved.add(data);
    return 'Pictures/BiliSail/test.png';
  }

  @override
  Future<void> copy(Uint8List data) async {
    copied.add(data);
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
