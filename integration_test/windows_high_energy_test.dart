import '../test/support/material_tooltip_finder.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bili_api/bili_api.dart';
import 'package:bili_player/bili_player.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/data/api_playback_repository.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/playback/presentation/playback_panel.dart';
import 'package:bilisail/features/playback/presentation/high_energy_curve.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/video/data/api_video_repository.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Opt-in real media/Profile probe. Normal CI never contacts Bilibili.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'Windows native high energy, chapters and alternating Profile A/B',
    (tester) async {
      initializePlayerBackend();
      final requests = ApiRequests();
      final api = BiliApiClient(sessionProvider: requests);
      final window = WindowService();
      await window.initialize();
      final videos = ApiVideoRepository(api, requests);
      final plain = await videos.loadDetail(
        const VideoId('BV1xx411c7mD'),
        cancellation: RequestCancellation(),
      );
      final chaptered = await videos.loadDetail(
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
      final settings = ValueNotifier(
        AppSettings(
          highEnergyProgressEnabled: true,
          playerControlsMode: PlayerControlsMode.dynamic,
          danmakuEnabled: false,
          resumePlayback: false,
          defaultVolume: 0,
        ),
      );
      final width = ValueNotifier(960.0);
      final boundaryKey = GlobalKey();
      VideoDetail current = plain;
      var collect = false;
      final timings = <ui.FrameTiming>[];
      void record(List<ui.FrameTiming> batch) {
        if (collect) timings.addAll(batch);
      }

      WidgetsBinding.instance.addTimingsCallback(record);
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer();
      Future<void> mount() => tester.pumpWidget(
        ProviderScope(
          overrides: [playbackSessionProvider.overrideWithValue(session)],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: ValueListenableBuilder<double>(
                  valueListenable: width,
                  builder: (_, value, _) => SizedBox(
                    width: value,
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: RepaintBoundary(
                        key: boundaryKey,
                        child: ValueListenableBuilder<AppSettings>(
                          valueListenable: settings,
                          builder: (_, value, _) => PlaybackPanel(
                            detail: current,
                            part: current.parts.first,
                            settings: value,
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
      final outputDirectory = Platform.environment['BILI_HIGH_ENERGY_OUTPUT'];
      final refreshRate =
          ui.PlatformDispatcher.instance.views.first.display.refreshRate;
      Future<void> screenshot(String name) async {
        final boundary = boundaryKey.currentContext?.findRenderObject();
        if (boundary is RenderRepaintBoundary && outputDirectory != null) {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          if (bytes != null) {
            await Directory(outputDirectory).create(recursive: true);
            await File('$outputDirectory/$name.png')
                .writeAsBytes(bytes.buffer.asUint8List());
          }
        }
      }

      try {
        await mount();
        await _until(
          tester,
          () =>
              session.highEnergy.value != null &&
              engine.inspectDiagnostics().hasDecodedVideo &&
              engine.inspectDiagnostics().hasDecodedAudio,
          const Duration(seconds: 90),
        );
        expect(session.chapters, isEmpty);
        // Keep controls visible by hovering an ordinary control, avoiding preview reads.
        await mouse.moveTo(tester.getCenter(findMaterialTooltip('暂停（空格）')));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(HighEnergyCurve), findsOneWidget);
        await screenshot('window');
        final generation = engine.currentSnapshot.generation;
        await tester.tap(findMaterialTooltip('全屏（F）'));
        await tester.pump(const Duration(milliseconds: 400));
        await mouse.moveTo(tester.getCenter(findMaterialTooltip('暂停（空格）')));
        expect(engine.currentSnapshot.generation, generation);
        expect(find.byType(HighEnergyCurve), findsOneWidget);
        await tester.tap(findMaterialTooltip('退出全屏（Esc）'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(Dialog), findsNothing);
        width.value = 320;
        await tester.pump(const Duration(milliseconds: 400));
        await mouse.moveTo(tester.getCenter(findMaterialTooltip('暂停（空格）')));
        await screenshot('compact');
        expect(find.byType(HighEnergyCurve), findsOneWidget);
        width.value = 960;
        await tester.pump(const Duration(milliseconds: 400));
        await mouse.moveTo(tester.getCenter(findMaterialTooltip('暂停（空格）')));
        // Warm geometry/shaders and native decoder before alternating six segments.
        await tester.pump(const Duration(seconds: 3));
        final samples = <Map<String, Object>>[];
        for (var round = 0; round < 3; round++) {
          for (final enabled in [false, true]) {
            settings.value = settings.value.copyWith(
              highEnergyProgressEnabled: enabled,
            );
            await tester.pump(const Duration(seconds: 1));
            if (enabled) {
              await _until(
                tester,
                () => session.highEnergy.value != null,
                const Duration(seconds: 8),
              );
            }
            if (outputDirectory != null) {
              await File('$outputDirectory/phase.json').writeAsString(
                jsonEncode({
                  'round': round,
                  'enabled': enabled,
                  'stage': 'start',
                }),
              );
              await tester.pump(const Duration(seconds: 1));
            }
            timings.clear();
            collect = true;
            final rssBefore = ProcessInfo.currentRss;
            await tester.pump(const Duration(seconds: 20));
            collect = false;
            if (outputDirectory != null) {
              await File('$outputDirectory/phase.json').writeAsString(
                jsonEncode({
                  'round': round,
                  'enabled': enabled,
                  'stage': 'end',
                }),
              );
              await tester.pump(const Duration(seconds: 1));
            }
            final uiTimes =
                timings
                    .map((f) => f.buildDuration.inMicroseconds / 1000)
                    .toList()
                  ..sort();
            final rasterTimes =
                timings
                    .map((f) => f.rasterDuration.inMicroseconds / 1000)
                    .toList()
                  ..sort();
            double percentile(List<double> values, double p) =>
                values.isEmpty ? 0 : values[((values.length - 1) * p).round()];
            samples.add({
              'round': round,
              'enabled': enabled,
              'frames': timings.length,
              'refreshRateHz': refreshRate,
              'overRefreshBudget': timings
                  .where(
                    (f) =>
                        f.buildDuration.inMicroseconds >
                            1000000 / refreshRate ||
                        f.rasterDuration.inMicroseconds > 1000000 / refreshRate,
                  )
                  .length,
              'uiP95Ms': percentile(uiTimes, .95),
              'uiP99Ms': percentile(uiTimes, .99),
              'rasterP95Ms': percentile(rasterTimes, .95),
              'rasterP99Ms': percentile(rasterTimes, .99),
              'over16_7Ms': timings
                  .where(
                    (f) =>
                        f.buildDuration.inMicroseconds > 16667 ||
                        f.rasterDuration.inMicroseconds > 16667,
                  )
                  .length,
              'rssBefore': rssBefore,
              'rssAfter': ProcessInfo.currentRss,
            });
            debugPrint('HIGH_ENERGY_PROFILE ${jsonEncode(samples.last)}');
          }
        }
        if (outputDirectory != null) {
          await File('$outputDirectory/profile.json')
              .writeAsString(jsonEncode({'pid': pid, 'samples': samples}));
        }
        current = chaptered;
        await mount();
        await _until(
          tester,
          () => session.chapters.isNotEmpty,
          const Duration(seconds: 90),
        );
        await mouse.moveTo(tester.getCenter(findMaterialTooltip('暂停（空格）')));
        await tester.pump(const Duration(milliseconds: 400));
        expect(session.highEnergy.value, isNull);
        expect(find.byType(HighEnergyCurve), findsNothing);
        expect(
          find.byKey(const ValueKey('playback-chapters-menu')),
          findsOneWidget,
        );
        await screenshot('chapters');
        expect(tester.takeException(), isNull);
      } finally {
        WidgetsBinding.instance.removeTimingsCallback(record);
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        await session.close();
        settings.dispose();
        width.dispose();
        api.close();
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
    reason: 'Native media/metadata did not become ready',
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
