import 'dart:io';
import 'dart:ui' as ui;

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/core/presentation/app_image_provider.dart';
import 'package:bilisail/core/storage/image_byte_cache.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/data/api_playback_repository.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/playback/presentation/playback_panel.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/video/data/api_video_repository.dart';
import 'package:bilisail/shared/ui/app_network_image.dart';
import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'Windows chapter hover uses real BV1VEHn6TEKq sprites and one engine',
    (tester) async {
      initializePlayerBackend();
      final requests = ApiRequests();
      final api = BiliApiClient(sessionProvider: requests);
      final window = WindowService();
      await window.initialize();
      final detail = await ApiVideoRepository(api, requests).loadDetail(
        const VideoId('BV1VEHn6TEKq'),
        cancellation: RequestCancellation(),
      );
      final engine = MediaKitEngine();
      final repository = ApiPlaybackRepository(api, requests);
      final session = PlaybackSession(
        engine: engine,
        repository: repository,
        metadataRepository: repository,
        progress: _NoopProgress(),
        accountScope: () => 'guest',
      );
      // Count actual CDN loads independently of metadata; repeated hover must reuse.
      final directory = await Directory.systemTemp.createTemp(
        'bilisail-timeline-',
      );
      var imageLoads = 0;
      final cache = AppImageCache(
        ImageByteCache(
          directory: () async => directory,
          loader: (uri, request) {
            imageLoads++;
            return loadPublicImage(uri, request);
          },
        ),
      );
      final boundaryKey = GlobalKey();
      final width = ValueNotifier(900.0);
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [playbackSessionProvider.overrideWithValue(session)],
            child: AppImageCacheScope(
              cache: cache,
              child: RepaintBoundary(
                key: boundaryKey,
                child: MaterialApp(
                  home: Scaffold(
                    body: Center(
                      child: ValueListenableBuilder<double>(
                        valueListenable: width,
                        builder: (_, width, _) => SizedBox(
                          width: width,
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: PlaybackPanel(
                              detail: detail,
                              part: detail.parts.first,
                              settings: AppSettings(
                                danmakuEnabled: false,
                                defaultVolume: 0,
                              ),
                              onToggleComments: () {},
                              window: window,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await _until(
          tester,
          () =>
              session.chapters.length == 5 &&
              engine.inspectDiagnostics().hasDecodedVideo &&
              engine.inspectDiagnostics().hasDecodedAudio,
          const Duration(seconds: 85),
        );
        expect(session.error, isNull);
        await session.pause();
        final generation = engine.currentSnapshot.generation;
        final paused = engine.currentSnapshot.position;
        expect(
          session.storyboard,
          isNull,
          reason: 'Images load on first hover',
        );
        final mouse = await tester.createGesture(
          kind: ui.PointerDeviceKind.mouse,
        );
        await mouse.addPointer();
        final slider = find.byKey(const ValueKey('playback-timeline-slider'));
        var rect = tester.getRect(slider);
        await mouse.moveTo(
          Offset(
            rect.left +
                8 +
                (rect.width - 16) *
                    18000 /
                    engine.currentSnapshot.duration.inMilliseconds,
            rect.center.dy,
          ),
        );
        await _until(
          tester,
          () => session.storyboard != null && cache.decoded.currentSize > 0,
          const Duration(seconds: 25),
        );
        expect(session.storyboard?.times, hasLength(9));
        expect(
          find.byKey(const ValueKey('playback-seek-preview')),
          findsOneWidget,
        );
        expect(
          (engine.currentSnapshot.position - paused).inMilliseconds.abs(),
          lessThan(300),
        );
        expect(engine.currentSnapshot.generation, generation);
        await tester.pump(const Duration(milliseconds: 500));
        final boundary = boundaryKey.currentContext?.findRenderObject();
        expect(boundary, isA<RenderRepaintBoundary>());
        if (boundary is RenderRepaintBoundary) {
          final screenshot = await boundary.toImage(pixelRatio: 1.5);
          final bytes = await screenshot.toByteData(
            format: ui.ImageByteFormat.png,
          );
          screenshot.dispose();
          final outputDirectory = Platform.environment['BILI_TIMELINE_OUTPUT'];
          if (bytes != null && outputDirectory != null) {
            final output = File('$outputDirectory/playback-timeline.png');
            await output.parent.create(recursive: true);
            await output.writeAsBytes(bytes.buffer.asUint8List());
          }
        }
        for (final fraction in [0.05, 0.5, 0.95]) {
          await mouse.moveTo(
            Offset(
              rect.left + 8 + (rect.width - 16) * fraction,
              rect.center.dy,
            ),
          );
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(imageLoads, 1);
        width.value = 320;
        await tester.pump(const Duration(milliseconds: 300));
        rect = tester.getRect(slider);
        await mouse.moveTo(rect.center);
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(engine.currentSnapshot.generation, generation);
        width.value = 900;
        await mouse.moveTo(Offset.zero);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byTooltip('全屏（F）'));
        await tester.pump(const Duration(milliseconds: 400));
        await mouse.moveTo(tester.getCenter(slider));
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          find.byKey(const ValueKey('playback-seek-preview')),
          findsOneWidget,
        );
        expect(engine.currentSnapshot.generation, generation);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump(const Duration(milliseconds: 400));
        expect(engine.currentSnapshot.generation, generation);
        await mouse.removePointer();
        debugPrint(
          'TIMELINE_ONLINE chapters=${session.chapters.length} frames=${session.storyboard?.times.length} imageLoads=$imageLoads video=${engine.inspectDiagnostics().hasDecodedVideo} audio=${engine.inspectDiagnostics().hasDecodedAudio}',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await session.close();
        await cache.close();
        width.dispose();
        api.close();
        // This exact directory was created above by this test.
        await directory.delete(recursive: true);
      }
    },
    skip: !const bool.fromEnvironment('BILI_ONLINE_SMOKE'),
  );
}

Future<void> _until(
  WidgetTester tester,
  bool Function() condition,
  Duration timeout,
) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    condition(),
    isTrue,
    reason: 'Real media or timeline failed to become ready',
  );
}

final class _NoopProgress implements PlaybackProgressStore {
  @override
  Future<Duration> read(String scope, VideoId video, String cid) async =>
      Duration.zero;
  @override
  Future<void> write(
    String scope,
    VideoSummary video,
    VideoPart part,
    Duration position,
    Duration duration, {
    String? episodeId,
  }) async {}
}
