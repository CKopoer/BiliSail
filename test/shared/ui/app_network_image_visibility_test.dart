import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bilisail/core/presentation/app_image_provider.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/core/storage/image_byte_cache.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/shared/ui/app_network_image.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:bilisail/shared/ui/video_grid.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(const Rect.fromLTWH(0, 0, 24, 24), Paint()..color = Colors.blue);
  final picture = recorder.endRecording();
  final image = await picture.toImage(24, 24);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (data == null) throw StateError('Missing PNG');
  return data.buffer.asUint8List();
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (ready()) return;
  }
  fail('Image state did not settle');
}

Widget _image(int index) => AppNetworkImage(
  url: 'https://i0.hdslb.com/visibility-$index.jpg',
  width: 40,
  height: 40,
  errorBuilder: (_, _, _) => const Text('failed'),
);

Widget _app(AppImageCache cache, Widget child) => AppImageCacheScope(
  cache: cache,
  child: MaterialApp(home: Scaffold(body: child)),
);

final class _CountingImageBinding extends AutomatedTestWidgetsFlutterBinding {
  int decodes = 0;
  int visibilityBatches = 0;

  @override
  void addPostFrameCallback(
    FrameCallback callback, {
    String debugLabel = 'callback',
  }) {
    super.addPostFrameCallback((time) {
      if (debugLabel == 'AppNetworkImage.visibility') visibilityBatches++;
      callback(time);
    }, debugLabel: debugLabel);
  }

  @override
  Future<ui.Codec> instantiateImageCodecWithSize(
    ui.ImmutableBuffer buffer, {
    ui.TargetImageSizeCallback? getTargetSize,
  }) {
    decodes++;
    return super.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: getTargetSize,
    );
  }
}

final class _FastScrollActivity extends ScrollActivity {
  _FastScrollActivity(super.delegate);

  @override
  bool get shouldIgnorePointer => false;
  @override
  bool get isScrolling => true;
  @override
  double get velocity => 5000;
}

final class _ManualImageCompleter extends ImageStreamCompleter {
  void emit(ui.Image image) => setImage(ImageInfo(image: image));

  void fail() => reportError(
    exception: StateError('Frame decode failed'),
    context: ErrorDescription('decoding a test frame'),
  );
}

void main() {
  final binding = _CountingImageBinding();
  testWidgets('unchanged image configuration does not schedule viewport work', (
    tester,
  ) async {
    final bytes = await tester.runAsync(_png);
    if (bytes == null) throw StateError('Missing PNG');
    final cache = AppImageCache(
      ImageByteCache(
        directory: () async => throw const FileSystemException('optional'),
        loader: (_, _) async => bytes,
      ),
    );
    late StateSetter update;
    var label = 'first';
    await tester.pumpWidget(
      _app(
        cache,
        StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return SingleChildScrollView(
              child: AppNetworkImage(
                url: 'https://i0.hdslb.com/unchanged.png',
                width: 40,
                height: 40,
                semanticLabel: label,
              ),
            );
          },
        ),
      ),
    );
    await _until(
      tester,
      () => tester
          .widgetList<RawImage>(find.byType(RawImage))
          .any((image) => image.image != null),
    );
    await tester.pumpAndSettle();
    binding.visibilityBatches = 0;
    update(() => label = 'updated');
    await tester.pumpAndSettle();
    expect(binding.visibilityBatches, 0);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    await tester.pumpWidget(const SizedBox());
    await cache.close();
    expect(tester.takeException(), isNull);
  });
  testWidgets('a failed visibility check reports its error without starving '
      'other images in the batch', (tester) async {
    final bytes = await tester.runAsync(_png);
    if (bytes == null) throw StateError('Missing PNG');
    final loaded = <String>[];
    final cache = AppImageCache(
      ImageByteCache(
        directory: () async => throw const FileSystemException('optional'),
        loader: (uri, _) async {
          loaded.add(uri.path);
          return bytes;
        },
      ),
    );
    var failNext = true;
    await tester.pumpWidget(
      _app(
        cache,
        SingleChildScrollView(
          child: Column(
            children: [
              _TransformCounter(
                onTransform: () {
                  if (failNext) {
                    failNext = false;
                    throw StateError('synthetic viewport failure');
                  }
                },
                child: _image(0),
              ),
              _image(1),
              const SizedBox(height: 1600),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isA<StateError>());
    await _until(tester, () => loaded.contains('/visibility-1.jpg'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await cache.close();
  });
  testWidgets('nested images share listeners, a visibility batch and outer '
      'viewport geometry; hidden images detach', (tester) async {
    final bytes = await tester.runAsync(_png);
    if (bytes == null) throw StateError('Missing PNG');
    final cache = AppImageCache(
      ImageByteCache(
        directory: () async => throw const FileSystemException('optional'),
        loader: (_, _) async => bytes,
      ),
    );
    final outer = _ObservedScrollController();
    final inner = _ObservedScrollController();
    var transformVisits = 0;
    var active = true;
    late StateSetter update;
    final content = SingleChildScrollView(
      controller: outer,
      child: Column(
        children: [
          _TransformCounter(
            onTransform: () => transformVisits++,
            child: SizedBox(
              height: 100,
              child: SingleChildScrollView(
                controller: inner,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < 10; i++) _image(i),
                    const SizedBox(width: 1600),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 2000),
        ],
      ),
    );
    await tester.pumpWidget(
      _app(
        cache,
        StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return WorkspaceActivity(
              active: active,
              child: TickerMode(enabled: active, child: content),
            );
          },
        ),
      ),
    );
    await _until(
      tester,
      () =>
          tester
              .widgetList<RawImage>(find.byType(RawImage))
              .where((image) => image.image != null)
              .length ==
          10,
    );
    await tester.pumpAndSettle();
    expect(outer.observed.imageListeners, 1);
    expect(inner.observed.imageListeners, 1);
    transformVisits = 0;
    binding.visibilityBatches = 0;
    outer.jumpTo(5);
    inner.jumpTo(5);
    await tester.pump();
    expect(binding.visibilityBatches, 1);
    expect(transformVisits, 1);
    update(() => active = false);
    await tester.pumpAndSettle();
    expect(outer.observed.imageListeners, 0);
    expect(inner.observed.imageListeners, 0);
    binding.visibilityBatches = 0;
    outer.jumpTo(10);
    inner.jumpTo(10);
    await tester.pump();
    expect(binding.visibilityBatches, 0);
    update(() => active = true);
    await tester.pumpAndSettle();
    expect(outer.observed.imageListeners, 1);
    expect(inner.observed.imageListeners, 1);
    await tester.pumpWidget(const SizedBox());
    expect(outer.observed.imageListeners, 0);
    expect(inner.observed.imageListeners, 0);
    outer.dispose();
    inner.dispose();
    await cache.close();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reparenting a cached image replaces queued geometry and old '
      'scroll listeners', (tester) async {
    final bytes = await tester.runAsync(_png);
    if (bytes == null) throw StateError('Missing PNG');
    var loads = 0;
    final cache = AppImageCache(
      ImageByteCache(
        directory: () async => throw const FileSystemException('optional'),
        loader: (_, _) async {
          loads++;
          return bytes;
        },
      ),
    );
    final left = _ObservedScrollController();
    final right = _ObservedScrollController();
    final key = GlobalKey();
    final image = AppNetworkImage(
      key: key,
      url: 'https://i0.hdslb.com/reparent.jpg',
      width: 40,
      height: 40,
    );
    var onRight = false;
    late StateSetter update;
    await tester.pumpWidget(
      _app(
        cache,
        StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    controller: left,
                    child: Column(
                      children: [
                        if (!onRight) image,
                        const SizedBox(height: 2000),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: right,
                    child: Column(
                      children: [
                        const SizedBox(height: 1000),
                        if (onRight) image,
                        const SizedBox(height: 1000),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    await _until(
      tester,
      () => tester
          .widgetList<RawImage>(find.byType(RawImage))
          .any((image) => image.image != null),
    );
    left.jumpTo(800);
    update(() => onRight = true);
    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsNothing);
    expect(left.observed.imageListeners, 0);
    expect(right.observed.imageListeners, 1);
    expect(loads, 1);
    right.jumpTo(1000);
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(loads, 1);
    await tester.pumpAndSettle();
    binding.visibilityBatches = 0;
    left.jumpTo(0);
    await tester.pump();
    expect(binding.visibilityBatches, 0);
    await tester.pumpWidget(const SizedBox());
    expect(right.observed.imageListeners, 0);
    left.dispose();
    right.dispose();
    await cache.close();
    expect(tester.takeException(), isNull);
  });
  for (final lazy in [false, true]) {
    for (final fast in [false, true]) {
      testWidgets(
        'decoded images return in the first frame with lazy=$lazy fast=$fast',
        (tester) async {
          tester.view.physicalSize = const Size(800, 600);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final bytes = await tester.runAsync(_png);
          if (bytes == null) throw StateError('Missing PNG');
          var calls = 0;
          final cache = AppImageCache(
            ImageByteCache(
              directory: () async =>
                  throw const FileSystemException('optional'),
              loader: (_, _) async {
                calls++;
                return bytes;
              },
            ),
          );
          final scroll = ScrollController();
          bool ready() => tester
              .widgetList<RawImage>(find.byType(RawImage))
              .any((image) => image.image != null);
          await tester.pumpWidget(
            _app(
              cache,
              lazy
                  ? ListView.builder(
                      controller: scroll,
                      itemExtent: 150,
                      itemCount: 30,
                      addAutomaticKeepAlives: false,
                      itemBuilder: (_, index) =>
                          index == 0 ? _image(1) : const SizedBox(height: 150),
                    )
                  : SingleChildScrollView(
                      controller: scroll,
                      child: Column(
                        children: [_image(1), const SizedBox(height: 4400)],
                      ),
                    ),
            ),
          );
          await _until(tester, ready);
          final original = tester.widget<RawImage>(find.byType(RawImage)).image;
          if (original == null) throw StateError('Missing frame');
          final clone = original.clone();
          final decodes = binding.decodes;
          final frameworkCacheSize = binding.imageCache.currentSize;
          scroll.jumpTo(2500);
          await tester.pumpAndSettle();
          expect(
            find.byType(AppNetworkImage),
            lazy ? findsNothing : findsOneWidget,
          );
          expect(find.byType(RawImage), findsNothing);
          expect(cache.decoded.liveImageCount, 0);
          expect(cache.decoded.currentSize, 1);
          scroll.jumpTo(0);
          if (fast) {
            final position = scroll.position as ScrollPositionWithSingleContext;
            position.beginActivity(_FastScrollActivity(position));
          }
          await tester.pump();
          expect(ready(), isTrue);
          final returned = tester.widget<RawImage>(find.byType(RawImage)).image;
          expect(returned?.isCloneOf(clone), isTrue);
          for (var frame = 0; frame < 3; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(ready(), isTrue);
          }
          expect(calls, 1);
          expect(binding.decodes, decodes);
          expect(binding.imageCache.currentSize, frameworkCacheSize);
          clone.dispose();
          await tester.pumpWidget(const SizedBox());
          scroll.dispose();
          await cache.close();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'cached streams deliver frames, pause when hidden and release offscreen',
    (tester) async {
      final bytes = await tester.runAsync(_png);
      if (bytes == null) throw StateError('Missing PNG');
      final pixels = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        codec.dispose();
        return frame.image;
      });
      if (pixels == null) throw StateError('Missing frame');
      var calls = 0;
      final cache = AppImageCache(
        ImageByteCache(
          directory: () async => throw const FileSystemException('optional'),
          loader: (_, _) async {
            calls++;
            return bytes;
          },
        ),
      );
      final completer = _ManualImageCompleter();
      cache.decoded.putIfAbsent(
        AppImageProvider(cache: cache, url: 'https://i0.hdslb.com/cached.gif'),
        () => completer,
      );
      completer.emit(pixels.clone());
      final scroll = ScrollController();
      int? lastFrame;
      bool? synchronous;
      Widget page(bool active, {bool outside = false}) => _app(
        cache,
        WorkspaceActivity(
          active: active,
          child: SingleChildScrollView(
            controller: scroll,
            child: Column(
              children: [
                if (outside) const SizedBox(height: 2000),
                AppNetworkImage(
                  url: 'https://i0.hdslb.com/cached.gif',
                  width: 40,
                  height: 40,
                  semanticLabel: 'cached animation',
                  errorBuilder: (_, _, _) => const Text('cached failure'),
                  frameBuilder: (_, child, frame, sync) {
                    lastFrame = frame;
                    synchronous = sync;
                    return child;
                  },
                ),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      );
      await tester.pumpWidget(page(false));
      expect(find.byType(RawImage), findsNothing);
      expect(completer.hasListeners, isFalse);
      await tester.pumpWidget(page(true));
      expect(lastFrame, 0);
      expect(synchronous, isTrue);
      expect(find.bySemanticsLabel('cached animation'), findsOneWidget);
      completer.emit(pixels.clone());
      await tester.pump();
      expect(lastFrame, 1);
      await tester.pumpWidget(page(false));
      expect(completer.hasListeners, isFalse);
      completer.emit(pixels.clone());
      await tester.pump();
      expect(lastFrame, 1);
      await tester.pumpWidget(page(true));
      expect(lastFrame, 2);
      completer.fail();
      await tester.pump();
      expect(find.text('cached failure'), findsOneWidget);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.byType(RawImage), findsNothing);
      expect(completer.hasListeners, isFalse);
      expect(cache.decoded.liveImageCount, 0);
      expect(calls, 0);
      // Late failures after listener removal follow Image's errorBuilder policy.
      completer.fail();
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page(true, outside: true));
      await tester.pumpAndSettle();
      expect(completer.hasListeners, isFalse);
      expect(cache.decoded.liveImageCount, 0);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
      await cache.close();
      pixels.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('uncached images still defer requests during fast scrolling', (
    tester,
  ) async {
    final bytes = await tester.runAsync(_png);
    if (bytes == null) throw StateError('Missing PNG');
    var calls = 0;
    final cache = AppImageCache(
      ImageByteCache(
        directory: () async => throw const FileSystemException('optional'),
        loader: (_, _) async {
          calls++;
          return bytes;
        },
      ),
    );
    final scroll = ScrollController();
    await tester.pumpWidget(
      _app(
        cache,
        ListView(
          controller: scroll,
          children: [_image(1), const SizedBox(height: 2000)],
        ),
      ),
    );
    final position = scroll.position as ScrollPositionWithSingleContext;
    position.beginActivity(_FastScrollActivity(position));
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(calls, 0);
    position.goIdle();
    await _until(
      tester,
      () => tester
          .widgetList<RawImage>(find.byType(RawImage))
          .any((image) => image.image != null),
    );
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
    await cache.close();
  });

  for (final enabled in [false, true]) {
    testWidgets(
      'retained hidden frames clear on URL or account changes with cache=$enabled',
      (tester) async {
        final bytes = await tester.runAsync(_png);
        if (bytes == null) throw StateError('Missing PNG');
        var calls = 0;
        final cache = AppImageCache(
          ImageByteCache(
            enabled: enabled,
            directory: () async => throw const FileSystemException('optional'),
            loader: (_, _) async {
              calls++;
              return bytes;
            },
          ),
        );
        Widget page(bool active, int image) => _app(
          cache,
          WorkspaceActivity(active: active, child: _image(image)),
        );
        Future<void> loaded() => _until(
          tester,
          () => tester
              .widgetList<RawImage>(find.byType(RawImage))
              .any((image) => image.image != null),
        );

        await tester.pumpWidget(page(true, 1));
        await loaded();
        if (enabled) {
          // Exercise the cached-stream renderer after a genuine remount.
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(page(true, 1));
          expect(
            tester.widget<RawImage>(find.byType(RawImage)).image,
            isNotNull,
          );
        }
        final frame = tester.widget<RawImage>(find.byType(RawImage)).image;
        await tester.pumpWidget(page(false, 1));
        await tester.pumpAndSettle();
        expect(
          tester.widget<RawImage>(find.byType(RawImage)).image,
          same(frame),
        );
        expect(calls, 1);
        final ticker = find
            .ancestor(
              of: find.byType(RawImage),
              matching: find.byType(TickerMode),
            )
            .first;
        expect(tester.widget<TickerMode>(ticker).enabled, isFalse);

        await tester.pumpWidget(page(false, 2));
        await tester.pumpAndSettle();
        expect(find.byType(RawImage), findsNothing);
        expect(calls, 1);
        await tester.pumpWidget(page(true, 2));
        await loaded();
        expect(calls, 2);
        await tester.pumpWidget(page(false, 2));
        await tester.pumpAndSettle();
        expect(find.byType(RawImage), findsOneWidget);
        await tester.runAsync(() => cache.changeScope('next-account'));
        await tester.pumpAndSettle();
        expect(find.byType(RawImage), findsNothing);
        expect(calls, 2);
        await tester.pumpWidget(page(true, 2));
        await loaded();
        expect(calls, 3);
        await tester.pumpWidget(const SizedBox());
        await cache.close();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('active page images release frames after vertical scrolling', (
    tester,
  ) async {
    final bytes = await tester.runAsync(_png);
    if (bytes == null) throw StateError('Missing PNG');
    var calls = 0;
    final cache = AppImageCache(
      ImageByteCache(
        enabled: false,
        directory: () async => throw const FileSystemException('optional'),
        loader: (_, _) async {
          calls++;
          return bytes;
        },
      ),
    );
    final scroll = ScrollController();
    await tester.pumpWidget(
      _app(
        cache,
        AppImagePageViewport(
          child: SingleChildScrollView(
            controller: scroll,
            child: Column(children: [_image(1), const SizedBox(height: 2000)]),
          ),
        ),
      ),
    );
    await _until(
      tester,
      () => tester
          .widgetList<RawImage>(find.byType(RawImage))
          .any((image) => image.image != null),
    );
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsNothing);
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    await _until(
      tester,
      () => tester
          .widgetList<RawImage>(find.byType(RawImage))
          .any((image) => image.image != null),
    );
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
    await cache.close();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'outer and inner scrolling both admit images in nested viewports',
    (tester) async {
      final bytes = await tester.runAsync(_png);
      if (bytes == null) throw StateError('Missing PNG');
      final loaded = <String>[];
      final cache = AppImageCache(
        ImageByteCache(
          directory: () async => throw const FileSystemException('optional'),
          loader: (uri, _) async {
            loaded.add(uri.path);
            return bytes;
          },
        ),
      );
      final outer = ScrollController();
      final inner = ScrollController();
      await tester.pumpWidget(
        _app(
          cache,
          SingleChildScrollView(
            controller: outer,
            child: Column(
              children: [
                const SizedBox(height: 900),
                SizedBox(
                  height: 60,
                  child: AppImagePageViewport(
                    child: SingleChildScrollView(
                      controller: inner,
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _image(1),
                          const SizedBox(width: 1200),
                          _image(2),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(loaded, isEmpty);
      outer.jumpTo(outer.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await _until(
        tester,
        () =>
            loaded.contains('/visibility-1.jpg') &&
            cache.decoded.pendingImageCount == 0,
      );
      expect(loaded, isNot(contains('/visibility-2.jpg')));
      inner.jumpTo(inner.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await _until(
        tester,
        () =>
            loaded.contains('/visibility-2.jpg') &&
            cache.decoded.pendingImageCount == 0,
      );
      expect(find.byType(RawImage), findsOneWidget);
      outer.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.byType(RawImage), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      outer.dispose();
      inner.dispose();
      await cache.close();
    },
  );
  testWidgets(
    'deferred images retain intrinsic layout and can acquire their natural size',
    (tester) async {
      final bytes = await tester.runAsync(_png);
      if (bytes == null) throw StateError('Missing PNG');
      var calls = 0;
      final cache = AppImageCache(
        ImageByteCache(
          directory: () async => throw const FileSystemException('optional'),
          loader: (_, _) async {
            calls++;
            return bytes;
          },
        ),
      );
      await tester.pumpWidget(
        _app(
          cache,
          SingleChildScrollView(
            child: Column(
              children: [
                IntrinsicHeight(
                  child: Row(children: [_image(1), const Text('avatar')]),
                ),
                AppNetworkImage(
                  url: 'https://i0.hdslb.com/natural.jpg',
                  errorBuilder: (_, _, _) => const Text('failed'),
                ),
              ],
            ),
          ),
        ),
      );
      await _until(
        tester,
        () =>
            calls == 2 &&
            tester
                    .widgetList<RawImage>(find.byType(RawImage))
                    .where((image) => image.image != null)
                    .length ==
                2,
      );
      expect(tester.getSize(find.byType(AppNetworkImage).last).height, 24);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await cache.close();
    },
  );
  testWidgets(
    'only viewport covers load and scrolling back reuses decoded images',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bytes = await tester.runAsync(_png);
      if (bytes == null) throw StateError('Missing PNG');
      final loaded = <String>[];
      final cache = AppImageCache(
        ImageByteCache(
          directory: () async => throw const FileSystemException('optional'),
          loader: (uri, _) async {
            expect(uri.path, endsWith('_1280h_0e.webp'));
            // Visibility is keyed by cover identity, independently of its size.
            loaded.add(uri.path.split('@').first);
            return bytes;
          },
        ),
      );
      final scroll = ScrollController();
      final videos = [
        for (var i = 0; i < 80; i++)
          VideoSummary(
            id: VideoId('BV${i.toString().padLeft(10, '0')}'),
            title: 'video-$i',
            author: '',
            duration: const Duration(minutes: 1),
            coverUrl: 'https://i0.hdslb.com/grid-$i.jpg',
          ),
      ];
      await tester.pumpWidget(
        _app(
          cache,
          CustomScrollView(
            controller: scroll,
            slivers: [
              SliverToBoxAdapter(
                child: VideoGrid(items: videos, onOpen: (_) {}),
              ),
            ],
          ),
        ),
      );
      await _until(
        tester,
        () => cache.decoded.pendingImageCount == 0 && loaded.isNotEmpty,
      );
      expect(loaded, contains('/grid-0.jpg'));
      expect(loaded, isNot(contains('/grid-79.jpg')));
      expect(loaded.length, lessThan(20));
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await _until(
        tester,
        () =>
            cache.decoded.pendingImageCount == 0 &&
            loaded.contains('/grid-79.jpg'),
      );
      expect(loaded.length, lessThan(40));
      final count = loaded.length;
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await _until(
        tester,
        () => tester
            .widgetList<RawImage>(find.byType(RawImage))
            .every((image) => image.image != null),
      );
      expect(loaded.length, count);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
      await cache.close();
    },
  );

  testWidgets(
    'queue-full visible images recover when capacity is released without remounting',
    (tester) async {
      final bytes = await tester.runAsync(_png);
      if (bytes == null) throw StateError('Missing PNG');
      final gate = Completer<Uint8List>();
      var calls = 0;
      final cache = AppImageCache(
        ImageByteCache(
          directory: () async => throw const FileSystemException('optional'),
          maxPending: 4,
          maxConcurrent: 2,
          loader: (_, _) {
            calls++;
            return gate.future;
          },
        ),
      );
      await tester.pumpWidget(
        _app(cache, Row(children: [for (var i = 0; i < 6; i++) _image(i)])),
      );
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(cache.bytes.hasCapacity, isFalse);
      expect(find.text('failed'), findsNothing);
      gate.complete(bytes);
      await _until(
        tester,
        () => calls == 6 && cache.decoded.pendingImageCount == 0,
      );
      expect(tester.widgetList<RawImage>(find.byType(RawImage)), hasLength(6));
      expect(
        tester
            .widgetList<RawImage>(find.byType(RawImage))
            .every((image) => image.image != null),
        isTrue,
      );
      expect(find.text('failed'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await cache.close();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hidden workspace waits without requesting or retrying and resumes on activation',
    (tester) async {
      final bytes = await tester.runAsync(_png);
      if (bytes == null) throw StateError('Missing PNG');
      final gate = Completer<Uint8List>();
      var calls = 0;
      final cache = AppImageCache(
        ImageByteCache(
          enabled: false,
          directory: () async => throw const FileSystemException('optional'),
          maxPending: 1,
          loader: (_, _) {
            calls++;
            return gate.future;
          },
        ),
      );
      final blocking = cache.bytes.load(
        Uri.parse('https://i0.hdslb.com/blocker.jpg'),
      );
      await tester.pumpWidget(
        _app(cache, WorkspaceActivity(active: true, child: _image(1))),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.pumpWidget(
        _app(cache, WorkspaceActivity(active: false, child: _image(1))),
      );
      gate.complete(bytes);
      await tester.runAsync(() async => blocking);
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.pumpWidget(
        _app(cache, WorkspaceActivity(active: true, child: _image(1))),
      );
      await _until(
        tester,
        () =>
            calls == 2 &&
            tester
                .widgetList<RawImage>(find.byType(RawImage))
                .any((image) => image.image != null),
      );
      await tester.pumpWidget(const SizedBox());
      await cache.close();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'resize admits an offscreen image and genuine transport errors are not replayed',
    (tester) async {
      tester.view.physicalSize = const Size(400, 300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var calls = 0;
      final cache = AppImageCache(
        ImageByteCache(
          directory: () async => throw const FileSystemException('optional'),
          loader: (_, _) async {
            calls++;
            throw const HttpException('Image response rejected');
          },
        ),
      );
      await tester.pumpWidget(
        _app(
          cache,
          SingleChildScrollView(
            child: Column(children: [const SizedBox(height: 700), _image(1)]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 0);
      tester.view.physicalSize = const Size(400, 900);
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('failed'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox());
      await cache.close();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending video cover shows its placeholder until the first frame',
    (tester) async {
      final bytes = await tester.runAsync(_png);
      if (bytes == null) throw StateError('Missing PNG');
      final gate = Completer<Uint8List>();
      final cache = AppImageCache(
        ImageByteCache(
          directory: () async => throw const FileSystemException('optional'),
          loader: (_, _) => gate.future,
        ),
      );
      await tester.pumpWidget(
        _app(
          cache,
          SizedBox(
            width: 300,
            child: VideoCard(
              video: const VideoSummary(
                id: VideoId('BV0000000001'),
                title: 'video',
                coverUrl: 'https://i0.hdslb.com/cover.jpg',
                author: '',
                duration: Duration(minutes: 1),
              ),
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      gate.complete(bytes);
      await _until(
        tester,
        () => tester
            .widgetList<RawImage>(find.byType(RawImage))
            .any((image) => image.image != null),
      );
      expect(find.byIcon(Icons.image_outlined), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await cache.close();
      expect(tester.takeException(), isNull);
    },
  );

  for (final enabled in [false, true]) {
    testWidgets(
      'hiding one shared consumer does not cancel its visible peer with cache=$enabled',
      (tester) async {
        final bytes = await tester.runAsync(_png);
        if (bytes == null) throw StateError('Missing PNG');
        final response = Completer<Uint8List>();
        var calls = 0;
        var aborts = 0;
        final cache = AppImageCache(
          ImageByteCache(
            enabled: enabled,
            directory: () async => throw const FileSystemException('optional'),
            loader: (_, request) {
              calls++;
              request.onCancel(() => aborts++);
              return response.future;
            },
          ),
        );
        Widget page(bool firstActive) => _app(
          cache,
          Row(
            children: [
              WorkspaceActivity(active: firstActive, child: _image(1)),
              _image(1),
            ],
          ),
        );
        await tester.pumpWidget(page(true));
        await tester.pumpAndSettle();
        expect(calls, 1);
        await tester.pumpWidget(page(false));
        await tester.pumpAndSettle();
        expect(aborts, 0);
        response.complete(bytes);
        await _until(
          tester,
          () => tester
              .widgetList<RawImage>(find.byType(RawImage))
              .any((image) => image.image != null),
        );
        expect(calls, 1);
        expect(aborts, 0);
        expect(find.text('failed'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await cache.close();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a new viewport cancels old active and queued demand before any stale decode',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bytes = await tester.runAsync(_png);
      if (bytes == null) throw StateError('Missing PNG');
      final gates = <String, Completer<Uint8List>>{};
      final aborted = <String>[];
      final cache = AppImageCache(
        ImageByteCache(
          enabled: false,
          directory: () async => throw const FileSystemException('optional'),
          maxConcurrent: 1,
          loader: (uri, request) {
            final response = Completer<Uint8List>();
            gates[uri.path] = response;
            request.onCancel(() => aborted.add(uri.path));
            return response.future;
          },
        ),
      );
      final scroll = ScrollController();
      await tester.pumpWidget(
        _app(
          cache,
          SingleChildScrollView(
            controller: scroll,
            child: Column(
              children: [
                for (var index = 0; index < 12; index++)
                  SizedBox(height: 300, child: _image(index)),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(gates.keys, ['/visibility-0.jpg']);
      final before = binding.decodes;
      scroll.jumpTo(2400);
      await tester.pumpAndSettle();
      expect(aborted, ['/visibility-0.jpg']);
      expect(gates.keys, ['/visibility-0.jpg', '/visibility-8.jpg']);
      gates['/visibility-0.jpg']!.complete(bytes);
      await tester.pumpAndSettle();
      expect(binding.decodes, before);
      gates['/visibility-8.jpg']!.complete(bytes);
      await _until(
        tester,
        () => tester
            .widgetList<RawImage>(find.byType(RawImage))
            .any((image) => image.image != null),
      );
      expect(binding.decodes, before + 1);
      expect(gates.keys, isNot(contains('/visibility-1.jpg')));
      expect(gates.keys, isNot(contains('/visibility-2.jpg')));
      expect(find.text('failed'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await cache.close();
      scroll.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a released scroll-deferred source cannot restart after leaving the viewport',
    (tester) async {
      var calls = 0;
      final cache = AppImageCache(
        ImageByteCache(
          enabled: false,
          directory: () async => throw const FileSystemException('optional'),
          loader: (_, _) async {
            calls++;
            throw const HttpException('A released image must not load');
          },
        ),
      );
      final scroll = ScrollController();
      await tester.pumpWidget(
        _app(
          cache,
          SingleChildScrollView(
            controller: scroll,
            child: Column(children: [_image(1), const SizedBox(height: 3000)]),
          ),
        ),
      );
      final position = scroll.position as ScrollPositionWithSingleContext;
      position.beginActivity(_FastScrollActivity(position));
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(calls, 0);
      final deferred = tester.widget<Image>(find.byType(Image)).image;
      scroll.jumpTo(2000);
      position.beginActivity(_FastScrollActivity(position));
      await tester.pump();
      // Replay the old provider callback between viewport release and the
      // following frame that removes its Image widget.
      deferred.resolve(ImageConfiguration.empty);
      position.goIdle();
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.byType(RawImage), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await cache.close();
      scroll.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}

final class _ObservedScrollController extends ScrollController {
  late _ObservedScrollPosition observed;
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => observed = _ObservedScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

final class _ObservedScrollPosition extends ScrollPositionWithSingleContext {
  _ObservedScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
  });
  int imageListeners = 0;
  @override
  void addListener(VoidCallback listener) {
    if (StackTrace.current.toString().contains('_ImageScrollObserver')) {
      imageListeners++;
    }
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (StackTrace.current.toString().contains('_ImageScrollObserver')) {
      imageListeners--;
    }
    super.removeListener(listener);
  }
}

final class _TransformCounter extends SingleChildRenderObjectWidget {
  const _TransformCounter({required this.onTransform, required super.child});
  final VoidCallback onTransform;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTransformCounter(onTransform);
}

final class _RenderTransformCounter extends RenderProxyBox {
  _RenderTransformCounter(this.onTransform);
  final VoidCallback onTransform;
  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (StackTrace.current.toString().contains('app_network_image.dart')) {
      onTransform();
    }
    super.applyPaintTransform(child, transform);
  }
}
