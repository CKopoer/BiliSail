import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bilisail/core/presentation/app_image_provider.dart';
import 'package:bilisail/core/storage/image_byte_cache.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/profile/presentation/profile_video_card.dart';
import 'package:bilisail/shared/ui/app_cover_image.dart';
import 'package:bilisail/shared/ui/app_network_image.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _source = 'https://i0.hdslb.com/bfs/archive/cover.jpg';

void main() {
  for (final profile in [false, true]) {
    testWidgets('video cover downloads a thumbnail with profile=$profile', (
      tester,
    ) async {
      final bytes = await tester.runAsync(_png);
      if (bytes == null) throw StateError('Missing PNG');
      final downloaded = <Uri>[];
      final cache = _cache(bytes, downloaded);
      const video = VideoSummary(
        id: VideoId('BV1234567890'),
        title: '测试封面',
        coverUrl: _source,
        author: '测试UP',
        duration: Duration(minutes: 3),
      );
      await tester.pumpWidget(
        _app(
          cache,
          width: profile ? 560 : 300,
          child: profile
              ? ProfileVideoCard(video: video, onTap: () {})
              : VideoCard(video: video, onTap: () {}),
        ),
      );
      await _loaded(tester);
      expect(
        downloaded.single.toString(),
        '$_source@${profile ? 240 : 320}w_1280h_0e.webp',
      );
      expect(video.coverUrl, _source);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await cache.close();
    });
  }

  testWidgets('retina covers reuse a size bucket and fetch larger on resize', (
    tester,
  ) async {
    final bytes = await tester.runAsync(_png);
    if (bytes == null) throw StateError('Missing PNG');
    final downloaded = <Uri>[];
    final cache = _cache(bytes, downloaded);
    Future<void> show(double width) async {
      await tester.pumpWidget(
        _app(
          cache,
          width: width,
          pixelRatio: 2,
          child: const AppCoverImage(url: _source, height: 120),
        ),
      );
      await _loaded(tester);
    }

    await show(300);
    expect(downloaded.single.toString(), '$_source@640w_1280h_0e.webp');
    await show(310);
    expect(downloaded, hasLength(1));
    await show(321);
    expect(downloaded.last.toString(), '$_source@960w_1280h_0e.webp');
    expect(downloaded, hasLength(2));
    await show(300);
    expect(downloaded, hasLength(2));
    await tester.pumpWidget(const SizedBox());
    await cache.close();
  });

  testWidgets('explicit cover dimensions bound the thumbnail and decode size', (
    tester,
  ) async {
    final bytes = await tester.runAsync(_png);
    if (bytes == null) throw StateError('Missing PNG');
    final downloaded = <Uri>[];
    final cache = _cache(bytes, downloaded);
    await tester.pumpWidget(
      _app(
        cache,
        width: 600,
        pixelRatio: 3,
        child: const Align(
          alignment: Alignment.topLeft,
          child: AppCoverImage(url: _source, width: 96, height: 54),
        ),
      ),
    );
    await _loaded(tester);
    expect(tester.getSize(find.byType(AppCoverImage)), const Size(96, 54));
    expect(downloaded.single.toString(), '$_source@320w_1280h_0e.webp');
    await tester.pumpWidget(
      _app(
        cache,
        width: 600,
        pixelRatio: 3,
        child: const AppCoverImage(url: _source, height: 120),
      ),
    );
    await _loaded(tester);
    expect(downloaded.last.toString(), '$_source@1280w_1280h_0e.webp');
    expect(
      tester.widget<AppNetworkImage>(find.byType(AppNetworkImage)).cacheWidth,
      1280,
    );
    await tester.pumpWidget(const SizedBox());
    await cache.close();
  });

  testWidgets('existing CDN transformations reach the loader unchanged', (
    tester,
  ) async {
    final bytes = await tester.runAsync(_png);
    if (bytes == null) throw StateError('Missing PNG');
    final downloaded = <Uri>[];
    final cache = _cache(bytes, downloaded);
    const transformed = '$_source@400w.jpg';
    await tester.pumpWidget(
      _app(
        cache,
        width: 300,
        child: const AppCoverImage(url: transformed, height: 120),
      ),
    );
    await _loaded(tester);
    expect(downloaded.single.toString(), transformed);
    await tester.pumpWidget(const SizedBox());
    await cache.close();
  });
}

AppImageCache _cache(Uint8List bytes, List<Uri> downloaded) => AppImageCache(
  ImageByteCache(
    directory: () async => throw const FileSystemException('optional'),
    maxImageBytes: bytes.length + 1,
    loader: (uri, _) async {
      downloaded.add(uri);
      // A full original would exceed the transfer cap before image decoding.
      return uri.toString() == _source ? Uint8List(bytes.length + 2) : bytes;
    },
  ),
);

Widget _app(
  AppImageCache cache, {
  required double width,
  required Widget child,
  double pixelRatio = 1,
}) => AppImageCacheScope(
  cache: cache,
  child: MaterialApp(
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(devicePixelRatio: pixelRatio),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  ),
);

Future<void> _loaded(WidgetTester tester) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    final images = tester.widgetList<RawImage>(find.byType(RawImage));
    if (images.isNotEmpty && images.every((image) => image.image != null)) {
      return;
    }
  }
  fail('Cover did not load');
}

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
