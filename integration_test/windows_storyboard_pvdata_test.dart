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
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('BV1HX8v6UEZ3 pvdata renders all four sheets without seeking', (
    tester,
  ) async {
    final requests = ApiRequests();
    final api = BiliApiClient(sessionProvider: requests);
    final directory = await Directory.systemTemp.createTemp('bilisail-pvdata-');
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
    try {
      final detail = await api.getVideoDetail('BV1HX8v6UEZ3');
      final part = detail.pages.first;
      final shot =
          await ApiPlaybackRepository(
            api,
            requests,
            imageDimensions: images.dimensions,
          ).storyboard(
            const VideoId('BV1HX8v6UEZ3'),
            part.cid,
            cancellation: RequestCancellation(),
          );
      if (shot == null) throw StateError('Missing pvdata storyboard');
      expect(shot.times, hasLength(359));
      expect(shot.images, hasLength(4));
      expect(shot.tileWidth, 480);
      expect(shot.tileHeight, 270);
      final playerKey = GlobalKey();
      final seeks = <Duration>[];
      var previewRequests = 0;
      await tester.pumpWidget(
        AppImageCacheScope(
          cache: images,
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
                            duration: part.duration,
                            buffered: Duration.zero,
                            chapters: const [],
                            sourceGeneration: 1,
                            playerBoundsKey: playerKey,
                            storyboard: shot,
                            onSeek: (position) async => seeks.add(position),
                            onPreviewRequest: () => previewRequests++,
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
      );
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer();
      final slider = tester.getRect(
        find.byKey(const ValueKey('playback-timeline-slider')),
      );
      for (final index in [0, 100, 200, 300, 0, 300]) {
        final time = shot.times[index] + const Duration(milliseconds: 500);
        final fraction = time.inMilliseconds / part.duration.inMilliseconds;
        await mouse.moveTo(
          Offset(
            slider.left +
                timelineTrackInset +
                (slider.width - 2 * timelineTrackInset) * fraction,
            slider.center.dy,
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        bool ready() =>
            find.byType(RawImage).evaluate().isNotEmpty &&
            tester.widget<RawImage>(find.byType(RawImage)).image != null;
        final deadline = DateTime.now().add(const Duration(seconds: 25));
        while (!ready() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(ready(), isTrue);
        final thumbnail = tester.widget<StoryboardThumbnail>(
          find.byType(StoryboardThumbnail),
        );
        expect(thumbnail.frame.image, shot.images[index ~/ 100]);
        expect(thumbnail.frame.column, 0);
        expect(thumbnail.frame.row, 0);
      }
      expect(imageLoads, 4);
      expect(previewRequests, 1);
      expect(seeks, isEmpty);
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
      debugPrint(
        'PVDATA_STORYBOARD_ONLINE bvid=BV1HX8v6UEZ3 frames=${shot.times.length} pages=${shot.images.length} imageLoads=$imageLoads rendered=true',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await images.close();
      api.close();
      await directory.delete(recursive: true);
    }
  }, skip: !const bool.fromEnvironment('BILI_ONLINE_SMOKE'));
}
