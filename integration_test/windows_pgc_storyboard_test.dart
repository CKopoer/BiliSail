import 'dart:io';
import 'dart:ui' as ui;

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/core/presentation/app_image_provider.dart';
import 'package:bilisail/core/storage/image_byte_cache.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/data/api_playback_repository.dart';
import 'package:bilisail/features/playback/presentation/playback_timeline_bar.dart';
import 'package:bilisail/shared/ui/app_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'PGC ep323085 hover renders both real sheets with inferred dimensions',
    (tester) async {
      final requests = ApiRequests();
      final api = BiliApiClient(sessionProvider: requests);
      final directory = await Directory.systemTemp.createTemp(
        'bilisail-pgc-shot-',
      );
      var imageLoads = 0;
      final images = AppImageCache(
        ImageByteCache(
          directory: () async => directory,
          loader: (uri, request) {
            imageLoads++;
            return loadPublicImage(uri, request);
          },
        ),
      );
      final repository = ApiPlaybackRepository(
        api,
        requests,
        imageDimensions: images.dimensions,
      );
      try {
        final season = await PgcClient(api).getSeason(episodeId: '323085');
        final episode = season.episodes.firstWhere(
          (e) => e.episodeId == '323085',
        );
        final bvid = episode.bvid;
        final cid = episode.cid;
        if (bvid == null || cid == null) {
          throw StateError('Missing episode IDs');
        }
        final shot = await repository.storyboard(
          VideoId(bvid),
          cid,
          cancellation: RequestCancellation(),
        );
        if (shot == null) throw StateError('Missing real storyboard');
        expect(shot.tileWidth, 256);
        expect(shot.tileHeight, 144);
        expect(shot.times, hasLength(186));
        expect(shot.images, hasLength(2));
        expect(
          imageLoads,
          1,
          reason: 'Only the first sheet is read to infer dimensions',
        );
        final playerKey = GlobalKey();
        final boundaryKey = GlobalKey();
        final seeks = <Duration>[];
        await tester.pumpWidget(
          AppImageCacheScope(
            cache: images,
            child: RepaintBoundary(
              key: boundaryKey,
              child: MaterialApp(
                home: Scaffold(
                  body: Center(
                    child: SizedBox(
                      key: playerKey,
                      width: 900,
                      height: 480,
                      child: ColoredBox(
                        color: Colors.black,
                        child: Stack(
                          children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 40,
                              child: PlaybackTimelineBar(
                                position: Duration.zero,
                                duration: const Duration(seconds: 1500),
                                buffered: Duration.zero,
                                chapters: const [],
                                sourceGeneration: 1,
                                playerBoundsKey: playerKey,
                                storyboard: shot,
                                onSeek: seeks.add,
                                onPreviewRequest: () {},
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final mouse = await tester.createGesture(
          kind: ui.PointerDeviceKind.mouse,
        );
        await mouse.addPointer();
        final slider = tester.getRect(
          find.byKey(const ValueKey('playback-timeline-slider')),
        );
        for (final fraction in [0.1, 0.8, 0.1, 0.8]) {
          await mouse.moveTo(
            Offset(
              slider.left + 8 + (slider.width - 16) * fraction,
              slider.center.dy,
            ),
          );
          await tester.pump(const Duration(milliseconds: 100));
          final deadline = DateTime.now().add(const Duration(seconds: 25));
          bool ready() {
            final raw = find.byType(RawImage);
            return raw.evaluate().isNotEmpty &&
                tester.widget<RawImage>(raw).image != null;
          }

          while (!ready() && DateTime.now().isBefore(deadline)) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(ready(), isTrue);
          final thumbnail = tester.widget<StoryboardThumbnail>(
            find.byType(StoryboardThumbnail),
          );
          expect(
            thumbnail.frame.image,
            fraction < 0.5 ? shot.images.first : shot.images.last,
          );
          final image = tester.widget<RawImage>(find.byType(RawImage)).image;
          expect(image?.width, 1280);
          expect(image?.height, 720);
        }
        expect(
          imageLoads,
          2,
          reason: 'Dimension inspection and repeated hover reuse the byte/decoded caches',
        );
        expect(seeks, isEmpty);
        expect(tester.takeException(), isNull);
        final outputDirectory = Platform.environment['BILI_TIMELINE_OUTPUT'];
        final boundary = boundaryKey.currentContext?.findRenderObject();
        if (outputDirectory != null && boundary is RenderRepaintBoundary) {
          final screenshot = await boundary.toImage();
          try {
            final bytes = await screenshot.toByteData(
              format: ui.ImageByteFormat.png,
            );
            if (bytes != null) {
              final output = File(
                '$outputDirectory/pgc-storyboard-ep323085.png',
              );
              await output.parent.create(recursive: true);
              await output.writeAsBytes(bytes.buffer.asUint8List());
            }
          } finally {
            screenshot.dispose();
          }
        }
        await mouse.removePointer();
        debugPrint(
          'PGC_STORYBOARD_ONLINE ep=323085 frames=${shot.times.length} tile=${shot.tileWidth}x${shot.tileHeight} pages=${shot.images.length} imageLoads=$imageLoads rendered=true',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await images.close();
        api.close();
        await directory.delete(recursive: true);
      }
    },
    skip: !const bool.fromEnvironment('BILI_ONLINE_SMOKE'),
  );
}
