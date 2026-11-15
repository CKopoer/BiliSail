import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bilisail/core/presentation/app_image_provider.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/core/storage/image_byte_cache.dart';
import 'package:bilisail/shared/ui/app_cover_image.dart';
import 'package:bilisail/shared/ui/app_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _url = 'https://i0.hdslb.com/retry-cover.jpg';
const _delays = [
  Duration(milliseconds: 500),
  Duration(seconds: 1),
  Duration(seconds: 2),
];

void main() {
  for (final enabled in [false, true]) {
    testWidgets('cover recovers on its third retry with cache=$enabled', (
      tester,
    ) async {
      final bytes = await tester.runAsync(_png);
      if (bytes == null) throw StateError('Missing PNG');
      var calls = 0;
      final cache = _cache((_, _) async {
        switch (++calls) {
          case 1:
            throw const SocketException('offline');
          case 2:
            throw TimeoutException('stalled');
          case 3:
            throw const HttpException('Image response rejected');
        }
        return bytes;
      }, enabled: enabled);
      await _show(tester, cache);
      expect(calls, 1);
      for (final (index, delay) in _delays.indexed) {
        await tester.pump(delay - const Duration(milliseconds: 1));
        expect(calls, index + 1);
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pumpAndSettle();
        expect(calls, index + 2);
      }
      await _until(tester, () => _hasFrame(tester));
      expect(find.text('failed'), findsNothing);
      await tester.pump(const Duration(seconds: 20));
      expect(calls, 4);
      await _close(tester, cache);
    });
  }

  testWidgets('three retries remain exhausted across rebuilds and scrolling', (
    tester,
  ) async {
    var calls = 0;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final cache = _cache((_, _) async {
      ++calls;
      throw const HttpException('Image response rejected');
    });
    await _show(tester, cache, scroll: scroll);
    for (final delay in _delays) {
      await _show(tester, cache, scroll: scroll);
      await tester.pump(delay);
      await tester.pumpAndSettle();
    }
    expect(calls, 4);
    expect(find.text('failed'), findsOneWidget);
    scroll.jumpTo(1000);
    await tester.pumpAndSettle();
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 4);
    expect(find.text('failed'), findsOneWidget);
    await _close(tester, cache);
  });

  for (final hidePage in [false, true]) {
    testWidgets(
      'pending retry pauses for ${hidePage ? 'hidden page' : 'offscreen cover'}',
      (tester) async {
        var calls = 0;
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final cache = _cache((_, _) async {
          ++calls;
          throw const HttpException('Image response rejected');
        });
        await _show(tester, cache, scroll: scroll);
        expect(calls, 1);
        if (hidePage) {
          await _show(tester, cache, scroll: scroll, active: false);
        } else {
          scroll.jumpTo(1000);
          await tester.pumpAndSettle();
        }
        await tester.pump(const Duration(seconds: 10));
        expect(calls, 1);
        if (hidePage) {
          await _show(tester, cache, scroll: scroll);
        } else {
          scroll.jumpTo(0);
          await tester.pumpAndSettle();
        }
        expect(calls, 1);
        for (final delay in _delays) {
          await tester.pump(delay);
          await tester.pumpAndSettle();
        }
        expect(calls, 4);
        await _close(tester, cache);
      },
    );
  }

  testWidgets('new URL cancels old retries and starts a fresh budget', (
    tester,
  ) async {
    final calls = <String, int>{};
    final cache = _cache((uri, _) async {
      calls.update(uri.path, (value) => value + 1, ifAbsent: () => 1);
      throw const HttpException('Image response rejected');
    });
    await _show(tester, cache);
    await tester.pump(const Duration(milliseconds: 250));
    await _show(tester, cache, url: 'https://i0.hdslb.com/new-cover.jpg');
    for (final delay in _delays) {
      await tester.pump(delay);
      await tester.pumpAndSettle();
    }
    expect(calls.values, [1, 4]);
    await cache.changeScope('another-account');
    await tester.pumpAndSettle();
    for (final delay in _delays) {
      await tester.pump(delay);
      await tester.pumpAndSettle();
    }
    expect(calls.values, [1, 8]);
    await _close(tester, cache);
  });

  testWidgets('queue admission does not consume the cover retry budget', (
    tester,
  ) async {
    var calls = 0;
    final gate = Completer<Uint8List>();
    final cache = AppImageCache(
      ImageByteCache(
        enabled: false,
        maxPending: 1,
        directory: () async => throw const FileSystemException('optional'),
        loader: (uri, _) {
          if (uri.path == '/blocker.jpg') return gate.future;
          ++calls;
          throw const HttpException('Image response rejected');
        },
      ),
    );
    final blocking = cache.bytes.load(
      Uri.parse('https://i0.hdslb.com/blocker.jpg'),
    );
    await _show(tester, cache);
    await tester.pump(const Duration(seconds: 5));
    expect(calls, 0);
    expect(find.text('failed'), findsNothing);
    gate.complete(Uint8List.fromList([1]));
    await blocking;
    await tester.pumpAndSettle();
    expect(calls, 1);
    for (final delay in _delays) {
      await tester.pump(delay);
      await tester.pumpAndSettle();
    }
    expect(calls, 4);
    await _close(tester, cache);
  });

  testWidgets('late failure from the old URL cannot retry the new image', (
    tester,
  ) async {
    final bytes = await tester.runAsync(_png);
    if (bytes == null) throw StateError('Missing PNG');
    final gate = Completer<Uint8List>();
    final downloaded = <Uri>[];
    final cache = _cache((uri, _) {
      downloaded.add(uri);
      return uri.path.startsWith('/retry-cover.jpg')
          ? gate.future
          : Future.value(bytes);
    });
    await _show(tester, cache);
    await _show(tester, cache, url: 'https://i0.hdslb.com/new-cover.jpg');
    await _until(tester, () => _hasFrame(tester));
    gate.completeError(const HttpException('late old failure'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    expect(downloaded, hasLength(2));
    expect(_hasFrame(tester), isTrue);
    expect(find.text('failed'), findsNothing);
    await _close(tester, cache);
  });

  testWidgets(
    'unmount cancels pending retry and avatars keep single attempts',
    (tester) async {
      var calls = 0;
      final cache = _cache((_, _) async {
        ++calls;
        throw const HttpException('Image response rejected');
      });
      await _show(tester, cache);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
      expect(calls, 1);
      await _show(tester, cache, cover: false);
      await tester.pump(const Duration(seconds: 10));
      expect(calls, 2);
      await _close(tester, cache);
    },
  );

  testWidgets('invalid cover URL does not retry or start a transfer', (
    tester,
  ) async {
    var calls = 0;
    final cache = _cache((_, _) async {
      ++calls;
      throw StateError('Invalid URL must not load');
    });
    await _show(tester, cache, url: 'invalid');
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 0);
    expect(find.text('failed'), findsOneWidget);
    await _close(tester, cache);
  });
}

AppImageCache _cache(ImageByteLoader loader, {bool enabled = false}) =>
    AppImageCache(
      ImageByteCache(
        enabled: enabled,
        directory: () async => throw const FileSystemException('optional'),
        loader: loader,
      ),
    );

Future<void> _show(
  WidgetTester tester,
  AppImageCache cache, {
  String url = _url,
  bool active = true,
  bool cover = true,
  ScrollController? scroll,
}) async {
  await tester.pumpWidget(
    AppImageCacheScope(
      cache: cache,
      child: MaterialApp(
        home: Scaffold(
          body: WorkspaceActivity(
            active: active,
            child: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  SizedBox(
                    width: 300,
                    height: 160,
                    child: cover
                        ? AppCoverImage(
                            url: url,
                            errorBuilder: (_, _, _) => const Text('failed'),
                          )
                        : AppNetworkImage(
                            url: url,
                            errorBuilder: (_, _, _) => const Text('failed'),
                          ),
                  ),
                  const SizedBox(height: 2000),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

bool _hasFrame(WidgetTester tester) => tester
    .widgetList<RawImage>(find.byType(RawImage))
    .any((image) => image.image != null);

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (ready()) return;
  }
  fail('Cover did not settle');
}

Future<void> _close(WidgetTester tester, AppImageCache cache) async {
  await tester.pumpWidget(const SizedBox());
  await cache.close();
  expect(tester.takeException(), isNull);
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
