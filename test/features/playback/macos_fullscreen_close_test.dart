import 'dart:async';
import 'dart:ui' show ViewFocusDirection, ViewFocusEvent, ViewFocusState;

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/app/workspace_playback_window.dart';
import 'package:bilisail/core/platform/detached_playback_window.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_manager.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/playback/presentation/playback_panel.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/detached_window_fake.dart';
import '../../support/fake_video_output.dart';
import '../../support/input_test_app.dart';
import '../../support/video_card_fake_engine.dart';
import '../../support/window_service_fake.dart';

void main() {
  testWidgets(
    'Cmd+W in detached fullscreen drains only its engine before native close and reopening',
    (tester) async {
      for (final name in ['bilisail/desktop_window', 'bilisail/text_input']) {
        final channel = MethodChannel(name);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (_) async => null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
      }
      final engines = <_Engine>[];
      final manager = PlaybackManager(
        createSession: (sleepTimer) {
          final engine = _Engine();
          engines.add(engine);
          addTearDown(() {
            final releasing = engine.releasing;
            if (releasing != null && !releasing.isCompleted) {
              releasing.complete();
            }
          });
          return PlaybackSession(
            sleepTimer: sleepTimer,
            engine: engine,
            repository: _Repository(),
            progress: _Progress(),
            accountScope: () => 'guest',
          );
        },
      );
      addTearDown(manager.close);
      final retained = manager.acquire('retained');
      final windows = <_Window>[];
      var open = true;
      var generation = 0;
      late StateSetter update;
      void close() {
        if (open) update(() => open = false);
      }

      await tester.pumpWidget(
        ProviderScope(
          child: InputTestApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                final id = 'playback-$generation';
                return DesktopPlaybackWindow(
                  waitForPlaybackRelease: manager.drainReleases,
                  onCloseRequested: close,
                  onError: (error) => fail('$error'),
                  windowFactory: ({required title, required onCloseRequested}) {
                    final window = _Window(
                      tester,
                      100 + windows.length,
                      onCloseRequested,
                    );
                    windows.add(window);
                    addTearDown(() {
                      if (!window.normal.isCompleted) window.normal.complete();
                    });
                    return window;
                  },
                  playback: !open
                      ? null
                      : ProviderScope(
                          key: ValueKey(id),
                          overrides: [
                            playbackSessionProvider.overrideWith((ref) {
                              final session = manager.acquire(id);
                              ref.onDispose(() => manager.release(id, session));
                              return session;
                            }),
                          ],
                          child: WorkspacePlaybackWindow(
                            theme: ThemeData(platform: TargetPlatform.macOS),
                            shortcuts: const ShortcutSettings.defaults(
                              useAppleDefaults: true,
                            ),
                            onBack: close,
                            onClose: close,
                            onActivateBrowser: () {},
                            child: Builder(
                              builder: (context) => PlaybackPanel(
                                detail: _detail,
                                part: _part,
                                settings: AppSettings(
                                  danmakuEnabled: false,
                                  resumePlayback: false,
                                ),
                                onToggleComments: () {},
                                window: WindowServiceScope.maybeOf(context)!,
                              ),
                            ),
                          ),
                        ),
                  child: const Scaffold(body: Text('browser survives')),
                );
              },
            ),
          ),
        ),
      );
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();
      final browser = tester.element(find.text('browser survives'));
      final browserNavigator = Navigator.of(browser);

      for (var round = 0; round < 2; round++) {
        if (round != 0) {
          update(() {
            open = true;
            generation++;
          });
          for (var frame = 0; frame < 5; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          await tester.pumpAndSettle();
        }
        final window = windows.last;
        final engine = engines.last;
        tester.binding.handleViewFocusChanged(
          ViewFocusEvent(
            viewId: window.viewId,
            state: ViewFocusState.focused,
            direction: ViewFocusDirection.undefined,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('player-surface-tap-target')),
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('全屏（F）'));
        await tester.pumpAndSettle();
        final fullscreen = tester.element(find.byType(Dialog));
        expect(View.of(fullscreen).viewId, window.viewId);
        expect(Navigator.of(fullscreen), isNot(same(browserNavigator)));
        expect(browserNavigator.canPop(), isFalse);
        expect(engine.opens, 1);
        expect(engine.surfaces, 1);
        expect(engine.maxSurfaces, 1);

        engine.releasing = Completer<void>();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
        window.requestClose();
        window.requestClose();
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(find.byType(PlaybackPanel), findsNothing);
        expect(engine.surfaces, 0);
        expect(window.disposed, isFalse);
        expect(window.preparations, 0);
        expect(tester.element(find.text('browser survives')), same(browser));
        expect(manager.sessions, [retained]);
        engine.releasing!.complete();
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        // Broadcast stream cancellation also drains its real event queue.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
        expect(engine.disposals, 1);
        expect(window.preparations, 1);
        expect(window.disposed, isFalse);
        window.normal.complete();
        await tester.pumpAndSettle();
        expect(window.disposed, isTrue);
        expect(engines.first.disposals, 0);
        expect(manager.sessions, [retained]);
        expect(engine.maxSurfaces, 1);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        expect(tester.takeException(), isNull);
      }
      expect(windows, hasLength(2));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(manager.close);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}

class _Window extends FakeDetachedWindow {
  _Window(WidgetTester tester, int id, VoidCallback onClose)
    : super(
        mainView: tester.view,
        viewId: id,
        size: const Size(1120, 760),
        title: 'playback',
        onCloseRequested: onClose,
      );
  final normal = Completer<void>();
  int preparations = 0;
  @override
  Future<void> prepareToClose() {
    preparations++;
    return normal.future;
  }

  late final _windowService = FakePlaybackWindowService(
    viewId: viewId,
    setFullScreen: (_) async {},
    activate: () async {},
  );

  @override
  WindowService get windowService => _windowService;
}

class _Engine extends CardFakeEngine {
  int surfaces = 0, maxSurfaces = 0;
  @override
  PlayerCapabilities get capabilities =>
      const PlayerCapabilities(externalAudio: true, externalAudioHeaders: true);
  @override
  Future<void> play() async => publish(
    snapshot.copyWith(phase: PlaybackPhase.playing, desiredPlaying: true),
  );
  @override
  Future<void> pause() async => publish(
    snapshot.copyWith(phase: PlaybackPhase.paused, desiredPlaying: false),
  );
  late final VideoOutput _output = FakeVideoOutput(() => _Surface(this));
  @override
  VideoOutput get videoOutput => _output;
}

class _Surface extends StatefulWidget {
  const _Surface(this.engine);
  final _Engine engine;
  @override
  State<_Surface> createState() => _SurfaceState();
}

class _SurfaceState extends State<_Surface> {
  @override
  void initState() {
    super.initState();
    final engine = widget.engine;
    engine.surfaces++;
    if (engine.surfaces > engine.maxSurfaces) {
      engine.maxSurfaces = engine.surfaces;
    }
  }

  @override
  void dispose() {
    widget.engine.surfaces--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black);
}

class _Repository extends Fake implements PlaybackRepository {
  @override
  Future<List<SubtitleTrack>> subtitles(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  }) async => [];

  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => cardPreviewMedia();
}

class _Progress extends Fake implements PlaybackProgressStore {
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

const _part = VideoPart(
  cid: '123',
  page: 1,
  title: 'part',
  duration: Duration(seconds: 20),
);
const _detail = VideoDetail(
  summary: VideoSummary(
    id: VideoId('BV1abc123456'),
    title: 'video',
    coverUrl: '',
    author: 'author',
    duration: Duration(seconds: 20),
  ),
  description: '',
  parts: [_part],
);
