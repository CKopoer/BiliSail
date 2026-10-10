import 'dart:convert';
import 'dart:ui';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/core/presentation/app_image_provider.dart';
import 'package:bilisail/core/storage/image_byte_cache.dart';
import 'package:bilisail/shared/ui/app_network_image.dart';
import 'package:bilisail/features/playback/domain/playback_timeline.dart';
import 'package:bilisail/features/playback/data/api_playback_repository.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/presentation/playback_timeline_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _chapters = [
  VideoChapter(start: Duration.zero, end: Duration(seconds: 20), title: '开场'),
  VideoChapter(
    start: Duration(seconds: 20),
    end: Duration(seconds: 60),
    title: '主要内容',
  ),
];

void main() {
  testWidgets(
    'zero-size sprite metadata resolves every crop and reuses the sheet',
    (tester) async {
      final encoded = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        for (var i = 0; i < 4; i++) {
          canvas.drawRect(
            Rect.fromLTWH((i % 2) * 20, (i ~/ 2) * 20, 20, 20),
            Paint()
              ..color = [
                Colors.red,
                Colors.green,
                Colors.blue,
                Colors.yellow,
              ][i],
          );
        }
        final picture = recorder.endRecording();
        final image = await picture.toImage(40, 40);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        if (bytes == null) throw StateError('Missing synthetic PNG');
        return bytes.buffer.asUint8List();
      });
      if (encoded == null) throw StateError('Missing synthetic PNG');
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('bilisail-storyboard-'),
      );
      if (directory == null) throw StateError('Missing cache directory');
      var loads = 0;
      // Disk operations and image-header inspection run in the real async zone.
      final cache = await tester.runAsync(
        () async => AppImageCache(
          ImageByteCache(
            directory: () async => directory,
            loader: (_, _) async {
              loads++;
              return encoded;
            },
          ),
        ),
      );
      if (cache == null) throw StateError('Missing image cache');
      final requests = ApiRequests();
      final api = BiliApiClient(
        transport: const _SpriteTransport(),
        sessionProvider: requests,
      );
      addTearDown(api.close);
      addTearDown(() => directory.deleteSync(recursive: true));
      VideoStoryboard? loaded;
      Object? failure;
      final load =
          ApiPlaybackRepository(
                api,
                requests,
                imageDimensions: cache.dimensions,
              )
              .storyboard(
                const VideoId('BV1abc123456'),
                '2',
                cancellation: RequestCancellation(),
              )
              .then(
                (value) => loaded = value,
                onError: (Object error) {
                  failure = error;
                  return null;
                },
              );
      for (
        var attempt = 0;
        attempt < 100 && loaded == null && failure == null;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(failure, isNull);
      final storyboard = loaded;
      if (storyboard == null) throw StateError('Missing inferred storyboard');
      await load;
      expect(storyboard.tileWidth, 20);
      expect(storyboard.tileHeight, 20);
      final boundaryKey = GlobalKey();
      for (var index = 0; index < 4; index++) {
        final frame = storyboard.frameAt(Duration(seconds: index * 5));
        if (frame == null) throw StateError('Missing frame');
        await tester.pumpWidget(
          AppImageCacheScope(
            cache: cache,
            child: MaterialApp(
              home: Center(
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: StoryboardThumbnail(
                    storyboard: storyboard,
                    frame: frame,
                    width: 40,
                    height: 40,
                  ),
                ),
              ),
            ),
          ),
        );
        for (var attempt = 0; attempt < 20; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
          if (tester.widget<RawImage>(find.byType(RawImage)).image != null) {
            break;
          }
        }
        final boundary = boundaryKey.currentContext?.findRenderObject();
        if (boundary is! RenderRepaintBoundary) {
          throw StateError('Missing boundary');
        }
        final pixels = await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData();
          image.dispose();
          return bytes;
        });
        if (pixels == null) throw StateError('Missing pixels');
        final rgba = Uint8List.view(pixels.buffer);
        final offset = (20 * 40 + 20) * 4;
        final color = Color.fromARGB(
          rgba[offset + 3],
          rgba[offset],
          rgba[offset + 1],
          rgba[offset + 2],
        );
        expect(
          color.toARGB32(),
          [
            Colors.red,
            Colors.green,
            Colors.blue,
            Colors.yellow,
          ][index].toARGB32(),
        );
      }
      expect(loads, 1);
      await tester.pumpWidget(const SizedBox());
      var closed = false;
      final cleanup = cache.close().then((_) => closed = true);
      for (var attempt = 0; attempt < 100 && !closed; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(closed, isTrue);
      await cleanup;
    },
  );
  testWidgets('hover shows chapter and time within player without seeking', (
    tester,
  ) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.build());
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    final track = tester.getRect(
      find.byKey(const ValueKey('playback-timeline-slider')),
    );
    await mouse.moveTo(track.center);
    await tester.pump();
    expect(find.byKey(const ValueKey('playback-seek-preview')), findsOneWidget);
    expect(find.text('00:30'), findsOneWidget);
    expect(harness.seeks, isEmpty);
    expect(harness.previews, greaterThan(0));
    for (final x in [track.left + 1, track.right - 1]) {
      await mouse.moveTo(Offset(x, track.center.dy));
      await tester.pump();
      final card = tester.getRect(
        find.byKey(const ValueKey('playback-seek-preview')),
      );
      final player = tester.getRect(find.byKey(harness.player));
      expect(card.left, greaterThanOrEqualTo(player.left));
      expect(card.right, lessThanOrEqualTo(player.right));
      expect(card.top, greaterThanOrEqualTo(player.top));
      expect(card.bottom, lessThan(track.top));
    }
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(find.byKey(const ValueKey('playback-seek-preview')), findsNothing);
    await mouse.removePointer();
  });

  testWidgets(
    'drag seeks once on release and source replacement cancels drag',
    (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.build());
      final track = tester.getRect(
        find.byKey(const ValueKey('playback-timeline-slider')),
      );
      final gesture = await tester.startGesture(
        Offset(track.left + 8, track.center.dy),
      );
      await gesture.moveTo(track.center);
      await tester.pump();
      expect(harness.seeks, isEmpty);
      await gesture.up();
      await tester.pump();
      expect(harness.seeks, hasLength(1));
      expect(harness.seeks.single.inSeconds, closeTo(30, 1));
      final oldDrag = await tester.startGesture(track.center);
      await oldDrag.moveTo(Offset(track.right - 30, track.center.dy));
      harness.generation++;
      await tester.pumpWidget(harness.build());
      await oldDrag.up();
      await tester.pump();
      expect(harness.seeks, hasLength(1));
      expect(find.byKey(const ValueKey('playback-seek-preview')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('chapter menu exposes short titles and seeks to their start', (
    tester,
  ) async {
    final harness = _Harness(width: 320, textScale: 2);
    await tester.pumpWidget(harness.build());
    await tester.tap(find.byKey(const ValueKey('playback-chapters-menu')));
    await tester.pumpAndSettle();
    expect(find.text('主要内容'), findsOneWidget);
    await tester.tap(find.text('主要内容'));
    await tester.pumpAndSettle();
    expect(harness.seeks, [const Duration(seconds: 20)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'preview survives resize and disappears when disabled or removed',
    (tester) async {
      final harness = _Harness(width: 320, textScale: 2);
      await tester.pumpWidget(harness.build());
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      await mouse.moveTo(
        tester.getCenter(
          find.byKey(const ValueKey('playback-timeline-slider')),
        ),
      );
      await tester.pump();
      harness.width = 250;
      await tester.pumpWidget(harness.build());
      await tester.pump();
      expect(tester.takeException(), isNull);
      harness.duration = Duration.zero;
      await tester.pumpWidget(harness.build());
      await tester.pump();
      expect(find.byKey(const ValueKey('playback-seek-preview')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    },
  );
}

final class _SpriteTransport implements ApiTransport {
  const _SpriteTransport();
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async => ApiHttpResponse(
    200,
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'code': 0,
          'data': {
            'img_x_len': 2,
            'img_y_len': 2,
            'img_x_size': 0,
            'img_y_size': 0,
            'image': ['https://i0.hdslb.com/synthetic-sprite.jpg'],
            'index': [0, 0, 5, 10, 15],
          },
        }),
      ),
    ),
    const {},
  );
}

class _Harness {
  _Harness({this.width = 600, this.textScale = 1});
  final player = GlobalKey();
  final seeks = <Duration>[];
  int previews = 0, generation = 1;
  double width, textScale;
  Duration duration = const Duration(seconds: 60);

  Widget build() => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            key: player,
            width: width,
            height: 260,
            child: ColoredBox(
              color: Colors.black,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 40,
                    child: PlaybackTimelineBar(
                      key: ValueKey(generation),
                      position: Duration.zero,
                      duration: duration,
                      buffered: const Duration(seconds: 45),
                      chapters: _chapters,
                      sourceGeneration: generation,
                      playerBoundsKey: player,
                      onSeek: seeks.add,
                      onPreviewRequest: () => previews++,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
