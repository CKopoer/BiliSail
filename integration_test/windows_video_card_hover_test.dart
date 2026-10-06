import 'dart:io';
import 'dart:ui' as ui;

import 'package:bili_api/bili_api.dart';
import 'package:bili_player/bili_player.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/core/presentation/app_image_provider.dart';
import 'package:bilisail/core/storage/image_byte_cache.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/domain/media_cdn.dart';
import 'package:bilisail/features/playback/data/api_playback_repository.dart';
import 'package:bilisail/features/video/application/video_card_controller.dart';
import 'package:bilisail/features/video/data/api_video_actions_repository.dart';
import 'package:bilisail/features/video/data/api_video_repository.dart';
import 'package:bilisail/shared/ui/app_network_image.dart';
import 'package:bilisail/features/video/application/video_card_preview_playback.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:bilisail/shared/ui/video_card_interaction_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'Windows guest hover decodes muted DASH, advances without motion and releases on exit',
    (tester) async {
      initializePlayerBackend();
      final deniedPrimary = const bool.fromEnvironment(
        'BILI_PREVIEW_DENIED_PRIMARY',
      );
      final server = deniedPrimary
          ? await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
          : null;
      var deniedRequests = 0;
      server?.listen((request) async {
        deniedRequests++;
        request.response.statusCode = 403;
        await request.response.close();
      });
      final preference =
          MediaCdnPreference.values
              .where(
                (p) =>
                    p.name ==
                    const String.fromEnvironment(
                      'BILI_PREVIEW_CDN',
                      defaultValue: 'automatic',
                    ),
              )
              .firstOrNull ??
          MediaCdnPreference.automatic;
      final engines = <_TrackedEngine>[];
      var maxActive = 0;
      final previews = VideoCardPreviewPlayback(
        createEngine: () {
          var diagnosticCount = 0;
          final engine = _TrackedEngine(
            MediaKitEngine(
              onDiagnostic: (event) {
                if (diagnosticCount++ < 30) {
                  debugPrint('VIDEO_CARD_DIAGNOSTIC ${event.toJson()}');
                }
              },
            ),
            deniedVideo: engines.isEmpty && server != null
                ? Uri.parse('http://127.0.0.1:${server.port}/denied')
                : null,
          );
          engines.add(engine);
          final active = engines.where((e) => !e.disposed).length;
          if (active > maxActive) maxActive = active;
          return engine;
        },
      );
      final requests = ApiRequests();
      final api = BiliApiClient(sessionProvider: requests);
      final videos = ApiVideoRepository(api, requests);
      final controller = VideoCardController(
        videos: videos,
        playback: ApiPlaybackRepository(
          api,
          requests,
          cdnPreference: () async => preference,
        ),
        previews: previews,
        actions: ApiVideoActionsRepository(
          VideoActionsClient(api),
          requests,
          accountScope: () => 'guest',
        ),
        signedIn: false,
      );
      var loads = 0, opens = 0;
      String? notice;
      final cache = AppImageCache(
        ImageByteCache(
          directory: () async => Directory('build/video-card-hover-cache'),
          loader: (uri, request) {
            loads++;
            return loadPublicImage(uri, request);
          },
        ),
      );
      final key = GlobalKey();
      try {
        final detail = await videos.loadDetail(
          const VideoId(
            String.fromEnvironment(
              'BILI_PREVIEW_BVID',
              defaultValue: 'BV1GJ411x7h7',
            ),
          ),
          cancellation: RequestCancellation(),
        );
        await tester.pumpWidget(
          AppImageCacheScope(
            cache: cache,
            child: MaterialApp(
              theme: BiliTheme.light(),
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                body: VideoCardInteractionScope(
                  interactions: controller,
                  onNotice: (_, message) => notice = message,
                  child: Center(
                    child: RepaintBoundary(
                      key: key,
                      child: ColoredBox(
                        color: Colors.white,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: SizedBox(
                                width: 320,
                                child: VideoCard(
                                  video: detail.summary,
                                  onTap: () => opens++,
                                ),
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
        await _until(
          tester,
          () => find
              .byType(RawImage)
              .evaluate()
              .any((e) => (e.widget as RawImage).image != null),
        );
        final mouse = await tester.createGesture(
          kind: ui.PointerDeviceKind.mouse,
        );
        await mouse.addPointer(location: Offset.zero);
        final cover = tester.getRect(
          find.byKey(const ValueKey('video-card-cover-scale')),
        );
        await mouse.moveTo(
          Offset(cover.left + cover.width * .2, cover.center.dy),
        );
        await _until(
          tester,
          () =>
              engines.isNotEmpty &&
              engines.last.native.inspectDiagnostics().hasDecodedVideo &&
              engines.last.native.inspectDiagnostics().hasDecodedAudio &&
              engines.last.currentSnapshot.position.inMilliseconds >= 1000,
        );
        final initialEngines = engines.length;
        expect(initialEngines, lessThanOrEqualTo(2));
        if (deniedPrimary) {
          expect(initialEngines, 2);
          expect(deniedRequests, greaterThan(0));
          expect(engines.first.disposed, true);
        }
        final first = engines.last;
        final start = first.currentSnapshot.position;
        await _until(
          tester,
          () =>
              first.currentSnapshot.position - start >
              const Duration(seconds: 1),
        );
        expect(first.currentSnapshot.volume, 0);
        expect(first.currentSnapshot.desiredPlaying, true);
        final diagnostics = first.native.inspectDiagnostics();
        expect(
          find.byKey(const ValueKey('video-card-preview')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('video-card-watch-later')));
        await tester.pump();
        expect(notice, '请先登录后再添加稍后再看');
        expect(opens, 0);
        final boundary = key.currentContext?.findRenderObject();
        if (boundary is! RenderRepaintBoundary) {
          throw StateError('Missing boundary');
        }
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (bytes == null) throw StateError('Missing preview');
        final dir = Directory('build/validation');
        await dir.create(recursive: true);
        await File('${dir.path}/video-card-hover-windows.png')
            .writeAsBytes(bytes.buffer.asUint8List());
        await mouse.moveTo(Offset.zero);
        await _until(tester, () => first.disposed);
        expect(first.stops, 1);
        expect(first.currentSnapshot.desiredPlaying, false);
        expect(find.byKey(const ValueKey('video-card-preview')), findsNothing);
        final stopped = first.currentSnapshot.position;
        await tester.pump(const Duration(milliseconds: 500));
        expect(first.currentSnapshot.position, stopped);
        // Title is part of the hover target; reopening uses a fresh native engine.
        await mouse.moveTo(tester.getCenter(find.text(detail.summary.title)));
        await tester.pump(const Duration(milliseconds: 500));
        await _until(
          tester,
          () =>
              engines.length > initialEngines &&
              engines.last.native.inspectDiagnostics().hasDecodedVideo &&
              engines.last.currentSnapshot.position.inMilliseconds >= 500,
        );
        expect(maxActive, 1);
        expect(engines.length - initialEngines, lessThanOrEqualTo(2));
        await mouse.moveTo(Offset.zero);
        await _until(tester, () => engines.last.disposed);
        await mouse.removePointer();
        expect(tester.takeException(), isNull);
        debugPrint(
          'VIDEO_CARD_DASH video=${diagnostics.videoWidth}x${diagnostics.videoHeight} '
          'audio=${diagnostics.audioChannels} volume=0 advanced=${(first.lastPlayingPosition - start).inMilliseconds}ms '
          'engines=${engines.length} maxActive=$maxActive cdn=${preference.name} '
          'deniedPrimary=$deniedPrimary deniedRequests=$deniedRequests '
          'imageLoads=$loads disposed=${engines.every((e) => e.disposed)}',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await previews.close();
        await cache.close();
        api.close();
        await server?.close(force: true);
      }
    },
    skip:
        !Platform.isWindows || !const bool.fromEnvironment('BILI_ONLINE_SMOKE'),
  );
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 25));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    ready(),
    true,
    reason:
        'Native preview did not reach the required playback or disposal state',
  );
}

class _TrackedEngine implements PlayerEngine, VideoSurfaceSource {
  _TrackedEngine(this.native, {this.deniedVideo});
  final MediaKitEngine native;
  final Uri? deniedVideo;
  bool disposed = false;
  int stops = 0;
  Duration lastPlayingPosition = Duration.zero;
  @override
  PlaybackSnapshot get currentSnapshot => native.currentSnapshot;
  @override
  Stream<PlaybackSnapshot> get snapshots => native.snapshots;
  @override
  Stream<PlayerFailure> get failures => native.failures;
  @override
  PlayerCapabilities get capabilities => native.capabilities;
  @override
  Future<void> open(ResolvedMediaSource source, OpenOptions options) {
    if (source is DashPairSource) {
      debugPrint(
        'VIDEO_CARD_CDN videoHost=${source.video.uri.host} audioHost=${source.audio?.uri.host}',
      );
      if (deniedVideo case final uri?) {
        source = DashPairSource(
          video: MediaTrack(
            uri: uri,
            requestPolicy: source.video.requestPolicy,
          ),
          audio: source.audio,
        );
      }
    }
    return native.open(source, options);
  }

  @override
  Future<void> play() => native.play();
  @override
  Future<void> pause() => native.pause();
  @override
  Future<void> seek(Duration position) => native.seek(position);
  @override
  Future<void> setRate(double rate) => native.setRate(rate);
  @override
  Future<void> setVolume(double volume) => native.setVolume(volume);
  @override
  Future<void> stop() {
    stops++;
    lastPlayingPosition = currentSnapshot.position;
    return native.stop();
  }

  @override
  Future<void> dispose() async {
    await native.dispose();
    disposed = true;
  }

  @override
  Widget buildVideoSurface() => native.buildVideoSurface();
}
