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
import 'package:flutter/material.dart';
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

void main() {
  testWidgets(
    'retained hidden frames stop listening and clear on URL or account changes',
    (tester) async {
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
      Widget page(bool active, int image) =>
          _app(cache, WorkspaceActivity(active: active, child: _image(image)));
      Future<void> loaded() => _until(
        tester,
        () => tester
            .widgetList<RawImage>(find.byType(RawImage))
            .any((image) => image.image != null),
      );

      await tester.pumpWidget(page(true, 1));
      await loaded();
      final frame = tester.widget<RawImage>(find.byType(RawImage)).image;
      await tester.pumpWidget(page(false, 1));
      await tester.pumpAndSettle();
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, same(frame));
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

  testWidgets('active offscreen images release their retained frame', (
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
        SingleChildScrollView(
          controller: scroll,
          child: Column(children: [_image(1), const SizedBox(height: 2000)]),
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
}
