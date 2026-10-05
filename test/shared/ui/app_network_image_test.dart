import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bili_lite/core/presentation/app_image_provider.dart';
import 'package:bili_lite/core/storage/image_byte_cache.dart';
import 'package:bili_lite/shared/ui/app_network_image.dart';
import 'package:bili_lite/app/image_cache_binding.dart';
import 'package:bili_lite/features/settings/application/settings_controller.dart';
import 'package:bili_lite/features/settings/domain/app_settings.dart';
import 'package:bili_lite/features/settings/domain/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<Uint8List> png() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 24, 24),
      Paint()..color = Colors.blue,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(24, 24);
    final result = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (result == null) throw StateError('PNG encoding failed');
    return result.buffer.asUint8List();
  }

  Future<void> decoded(WidgetTester tester) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (tester
          .widgetList<RawImage>(find.byType(RawImage))
          .every((image) => image.image != null)) {
        return;
      }
    }
    throw StateError('Image did not decode');
  }

  Widget frame(AppImageCache cache, Widget child) => AppImageCacheScope(
    cache: cache,
    child: MaterialApp(home: Center(child: child)),
  );
  const url = 'https://i0.hdslb.com/shared.jpg';
  Widget image({Key? key, int width = 640}) => AppNetworkImage(
    key: key,
    url: url,
    cacheWidth: width,
    width: 40,
    height: 40,
  );

  testWidgets(
    'loading settings keeps disk off and saved opt-out applies on startup',
    (tester) async {
      final bytes = await tester.runAsync(png);
      if (bytes == null) throw StateError('Missing bytes');
      final repository = _PendingSettings();
      var opens = 0;
      final cache = AppImageCache(
        ImageByteCache(
          directory: () async {
            ++opens;
            throw const FileSystemException('optional');
          },
          loader: (_, _) async => bytes,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
          child: ImageCacheBinding(
            cache: cache,
            child: MaterialApp(home: image()),
          ),
        ),
      );
      await decoded(tester);
      expect(cache.enabled, isFalse);
      expect(opens, 0);
      repository.result.complete(AppSettings(cacheImages: false));
      await tester.pump();
      expect(cache.enabled, isFalse);
      expect(opens, 0);
      await tester.pumpWidget(const SizedBox());
      await cache.close();
    },
  );

  testWidgets(
    'parallel widgets and tab remount share decoded image; rebuilding does not refetch',
    (tester) async {
      final bytes = await tester.runAsync(png);
      if (bytes == null) throw StateError('Missing bytes');
      var calls = 0;
      final gate = Completer<Uint8List>();
      final cache = AppImageCache(
        ImageByteCache(
          directory: () async =>
              throw const FileSystemException('optional cache unavailable'),
          loader: (_, _) {
            ++calls;
            return gate.future;
          },
        ),
      );
      await tester.pumpWidget(frame(cache, Row(children: [image(), image()])));
      await tester.pump();
      expect(calls, 1);
      gate.complete(bytes);
      await decoded(tester);
      expect(cache.decoded.currentSize, 1);
      final original = tester
          .widgetList<RawImage>(find.byType(RawImage))
          .first
          .image;
      await tester.pumpWidget(frame(cache, Row(children: [image(), image()])));
      await tester.pump();
      expect(calls, 1);
      expect(
        tester.widgetList<RawImage>(find.byType(RawImage)).first.image,
        original,
      );
      await tester.pumpWidget(frame(cache, const SizedBox()));
      await tester.pumpWidget(frame(cache, image()));
      await tester.pump();
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      expect(calls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await cache.close();
    },
  );

  testWidgets(
    'disabling is immediate, keeps visible stream, and new widgets bypass both caches',
    (tester) async {
      final bytes = await tester.runAsync(png);
      if (bytes == null) throw StateError('Missing bytes');
      var opens = 0;
      var calls = 0;
      final cache = AppImageCache(
        ImageByteCache(
          directory: () async {
            ++opens;
            throw const FileSystemException('optional');
          },
          loader: (_, _) async {
            ++calls;
            return bytes;
          },
        ),
      );
      await tester.pumpWidget(frame(cache, image()));
      await decoded(tester);
      final original = tester.widget<RawImage>(find.byType(RawImage)).image;
      cache.enabled = false;
      final previousOpens = opens;
      await tester.pumpWidget(frame(cache, image()));
      await tester.pump();
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, original);
      expect(calls, 1);
      expect(cache.decoded.currentSize, 0);
      await tester.pumpWidget(frame(cache, const SizedBox()));
      await tester.pumpWidget(frame(cache, image()));
      await decoded(tester);
      expect(calls, 2);
      expect(opens, previousOpens);
      expect(cache.decoded.currentSize, 0);
      await tester.pumpWidget(const SizedBox());
      await cache.close();
    },
  );

  testWidgets(
    'size variants share transport bytes and respect decode dimensions',
    (tester) async {
      final bytes = await tester.runAsync(png);
      if (bytes == null) throw StateError('Missing bytes');
      var calls = 0;
      final gate = Completer<Uint8List>();
      final cache = AppImageCache(
        ImageByteCache(
          directory: () async => throw const FileSystemException('optional'),
          loader: (_, _) {
            ++calls;
            return gate.future;
          },
        ),
      );
      await tester.pumpWidget(
        frame(cache, Row(children: [image(width: 12), image(width: 24)])),
      );
      await tester.pump();
      expect(calls, 1);
      gate.complete(bytes);
      await decoded(tester);
      final sizes = tester
          .widgetList<RawImage>(find.byType(RawImage))
          .map((image) => image.image?.width)
          .toList();
      expect(sizes, [12, 24]);
      expect(cache.decoded.currentSize, 2);
      await tester.pumpWidget(const SizedBox());
      await cache.close();
    },
  );
}

final class _PendingSettings implements SettingsRepository {
  final result = Completer<AppSettings>();
  @override
  Future<AppSettings> load() => result.future;
  @override
  Future<void> save(AppSettings settings) async {}
}
