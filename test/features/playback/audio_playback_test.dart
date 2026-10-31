import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/content_playback.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/playback/presentation/audio_playback_view.dart';
import 'package:bilisail/features/playback/presentation/playback_panel.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_video_output.dart';
import '../../support/input_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('HarmonyOS Sans')..addFont(
          rootBundle.load(
            'assets/fonts/harmonyos_sans/HarmonyOS_Sans_SC_Regular.ttf',
          ),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  late _Engine engine;
  late _Repository repository;
  late PlaybackSession session;

  setUp(() {
    engine = _Engine();
    repository = _Repository();
    session = PlaybackSession(
      engine: engine,
      repository: repository,
      contentRepository: _Content(repository),
      progress: _Progress(),
      accountScope: () => 'guest',
    );
    session.configureSettings(
      AppSettings(resumePlayback: false, autoPlay: true),
    );
  });
  tearDown(() => session.close());

  for (final manual in [false, true]) {
    for (final paused in [false, true]) {
      testWidgets(
        'Android retains source in background manual=$manual paused=$paused',
        (tester) async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [playbackSessionProvider.overrideWithValue(session)],
              child: MaterialApp(
                home: Scaffold(
                  body: PlaybackPanel(
                    detail: _detail,
                    part: _part,
                    settings: AppSettings(
                      danmakuEnabled: false,
                      resumePlayback: false,
                    ),
                    window: _AndroidWindow(),
                    onToggleComments: () {},
                  ),
                ),
              ),
            ),
          );
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          if (manual) await session.setAudioOnly(true);
          await session.seek(const Duration(minutes: 3));
          await session.setRate(1.5);
          await session.setVolume(32);
          if (paused) await session.pause();
          final generation = session.sourceGeneration;
          final nativeGeneration = engine.currentSnapshot.generation;
          final source = engine.sources.last;
          final opens = engine.sources.length;
          try {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.hidden,
            );
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.paused,
            );
            await tester.pump();
            expect(session.audioOnly, manual);
            expect(engine.sources, hasLength(opens));
            expect(engine.sources.last, same(source));
            expect(engine.currentSnapshot.desiredPlaying, !paused);
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.hidden,
            );
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
            await tester.pump();
            expect(session.sourceGeneration, generation);
            expect(engine.currentSnapshot.generation, nativeGeneration);
            expect(engine.sources, hasLength(opens));
            expect(session.audioOnly, manual);
            expect(engine.currentSnapshot.position, const Duration(minutes: 3));
            expect(engine.currentSnapshot.rate, 1.5);
            expect(engine.currentSnapshot.volume, 32);
            expect(engine.currentSnapshot.desiredPlaying, !paused);
          } finally {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
            await tester.pumpWidget(const SizedBox.shrink());
          }
        },
      );
    }
  }

  testWidgets(
    'Android background retains progressive media and playing intent',
    (tester) async {
      repository.media = _media(
        kind: PlaybackMediaKind.progressive,
        audio: false,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [playbackSessionProvider.overrideWithValue(session)],
          child: MaterialApp(
            home: Scaffold(
              body: PlaybackPanel(
                detail: _detail,
                part: _part,
                settings: AppSettings(
                  danmakuEnabled: false,
                  resumePlayback: false,
                ),
                window: _AndroidWindow(),
                onToggleComments: () {},
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final source = engine.sources.last;
      final generation = engine.currentSnapshot.generation;
      try {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(engine.sources, hasLength(1));
        expect(engine.sources.last, same(source));
        expect(engine.currentSnapshot.generation, generation);
        expect(engine.currentSnapshot.desiredPlaying, isTrue);
      } finally {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('background during source resolution keeps the video request', (
    tester,
  ) async {
    final pending = Completer<PlaybackMedia>();
    repository.pending = pending;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playbackSessionProvider.overrideWithValue(session)],
        child: MaterialApp(
          home: Scaffold(
            body: PlaybackPanel(
              detail: _detail,
              part: _part,
              settings: AppSettings(
                danmakuEnabled: false,
                resumePlayback: false,
              ),
              window: _AndroidWindow(),
              onToggleComments: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    try {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      pending.complete(repository.media);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(engine.sources, hasLength(1));
      expect(engine.sources.single, isA<DashPairSource>());
      expect(session.audioOnly, isFalse);
      expect(engine.currentSnapshot.desiredPlaying, isTrue);
    } finally {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  for (final target in [
    null,
    const PgcPlaybackTarget('42', cid: 'one'),
    const OfflinePlaybackTarget('local'),
  ]) {
    for (final paused in [false, true]) {
      test(
        'audio stream preserves playback intent and preferences target=$target paused=$paused',
        () async {
          await session.open(_detail, _part, target: target);
          await session.seek(const Duration(seconds: 35));
          await session.setRate(1.5);
          await session.setVolume(31);
          if (paused) await session.pause();
          await session.setAudioOnly(true);
          expect(session.audioOnly, isTrue);
          final audio = engine.sources.last as ProgressiveSource;
          expect(audio.media.uri, repository.media.audio?.urls.first);
          expect(audio.media.requestPolicy.headers, repository.media.headers);
          expect(engine.currentSnapshot.position, const Duration(seconds: 35));
          expect(engine.currentSnapshot.rate, 1.5);
          expect(engine.currentSnapshot.volume, 31);
          expect(engine.currentSnapshot.desiredPlaying, !paused);
          final comments = repository.commentRequests;
          engine.publish(
            engine.currentSnapshot.copyWith(
              position: const Duration(minutes: 7),
            ),
          );
          expect(repository.commentRequests, comments);
          await session.setAudioOnly(false);
          expect(engine.sources.last, isA<DashPairSource>());
          expect(engine.currentSnapshot.position, const Duration(minutes: 7));
          expect(engine.currentSnapshot.desiredPlaying, !paused);
        },
      );
    }
  }

  test(
    'audio CDN fallback never opens video and retry stays in listening mode',
    () async {
      await session.open(_detail, _part);
      engine.failNextAudio = true;
      await session.setAudioOnly(true);
      final sources = engine.sources.skip(1).cast<ProgressiveSource>();
      expect(
        sources.map((source) => source.media.uri),
        repository.media.audio?.urls,
      );
      await session.retry();
      expect(session.audioOnly, isTrue);
      expect(engine.sources.last, isA<ProgressiveSource>());
    },
  );

  test(
    'navigation restores listening per owner and next part inherits it',
    () async {
      final first = Object(), second = Object();
      session.attach(first);
      session.attach(second);
      await session.activate(first, _detail, _part);
      await session.setAudioOnly(true);
      await session.activate(
        first,
        _detail,
        const VideoPart(
          cid: 'two',
          page: 2,
          title: '第二集',
          duration: Duration(minutes: 10),
        ),
      );
      expect(session.audioOnly, isTrue);
      await session.activate(
        second,
        const VideoDetail(
          summary: VideoSummary(
            id: VideoId('BV1other12345'),
            title: '其他视频',
            coverUrl: '',
            author: 'UP',
            duration: Duration(minutes: 10),
          ),
          description: '',
          parts: [_part],
        ),
        _part,
      );
      expect(session.audioOnly, isFalse);
      await session.activate(
        first,
        _detail,
        const VideoPart(
          cid: 'two',
          page: 2,
          title: '第二集',
          duration: Duration(minutes: 10),
        ),
      );
      expect(session.audioOnly, isTrue);
      await session.stop();
      expect(session.audioOnly, isFalse);
    },
  );

  test(
    'return during pending audio resolution rejects late audio source',
    () async {
      await session.open(_detail, _part);
      final pending = Completer<PlaybackMedia>();
      repository.pending = pending;
      final listening = session.setAudioOnly(true);
      await Future<void>.delayed(Duration.zero);
      await session.setAudioOnly(false);
      pending.complete(repository.media);
      await listening;
      expect(session.audioOnly, isFalse);
      expect(engine.sources.whereType<ProgressiveSource>(), isEmpty);
      expect(engine.sources.last, isA<DashPairSource>());
    },
  );

  test(
    'unsupported media never falls back to fetching video while listening',
    () async {
      repository.media = _media(
        kind: PlaybackMediaKind.progressive,
        audio: false,
      );
      await session.open(_detail, _part);
      expect(session.canListen, isFalse);
      await session.setAudioOnly(true);
      expect(session.audioOnly, isFalse);
      expect(engine.sources, hasLength(1));
      repository.media = _media();
      await session.retry();
      await session.setAudioOnly(true);
      repository.media = _media(
        kind: PlaybackMediaKind.progressive,
        audio: false,
      );
      final count = engine.sources.length;
      await session.retry();
      expect(session.audioOnly, isTrue);
      expect(session.error, contains('没有独立音轨'));
      expect(engine.sources, hasLength(count));
      await session.setAudioOnly(false);
      expect(session.error, isNull);
    },
  );

  for (final size in [
    const Size(320, 180),
    const Size(390, 220),
    const Size(900, 506),
    const Size(390, 760),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('listening controls remain usable at $size scale=$scale', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await session.open(_detail, _part);
        await session.setAudioOnly(true);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: size.width == 900 ? BiliTheme.dark() : BiliTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: RepaintBoundary(
              key: boundary,
              child: ListenableBuilder(
                listenable: Listenable.merge([session, session.snapshots]),
                builder: (context, _) => AudioPlaybackView(
                  session: session,
                  snapshot: session.snapshots.value,
                  fullScreen: false,
                  onFullScreen: () {},
                  navigation: IconButton(
                    tooltip: '返回',
                    onPressed: () {},
                    icon: const Icon(Icons.arrow_back),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('audio-toggle-playing')));
        await tester.pump();
        expect(engine.currentSnapshot.desiredPlaying, isFalse);
        await tester.tap(find.byTooltip('前进 10 秒'));
        await tester.pump();
        expect(engine.currentSnapshot.position, const Duration(seconds: 10));
        if (scale == 1 && (size.width == 390 || size.width == 900)) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final output = File(
              'build/validation/audio-listening-${size.width.round()}x${size.height.round()}.png',
            );
            await output.parent.create(recursive: true);
            await output.writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(find.byKey(const ValueKey('audio-return-video')));
        await tester.pumpAndSettle();
        expect(session.audioOnly, isFalse);
      });
    }
  }

  testWidgets(
    'listening timeline holds its preview until native seek confirms',
    (tester) async {
      await session.open(_detail, _part);
      await session.setAudioOnly(true);
      await tester.pumpWidget(
        MaterialApp(
          home: ListenableBuilder(
            listenable: Listenable.merge([session, session.snapshots]),
            builder: (_, _) => AudioPlaybackView(
              session: session,
              snapshot: session.snapshots.value,
              fullScreen: false,
              onFullScreen: () {},
              navigation: const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      engine.nextSeek = Completer<void>();
      await tester.drag(
        find.byKey(const ValueKey('audio-timeline')),
        const Offset(100, 0),
      );
      await tester.pump();
      final preview = tester
          .widget<Slider>(find.byKey(const ValueKey('audio-timeline')))
          .value;
      expect(preview, greaterThan(0));
      expect(engine.currentSnapshot.position, Duration.zero);
      engine.nextSeek?.complete();
      await tester.pumpAndSettle();
      expect(engine.currentSnapshot.position.inMilliseconds, preview.round());
      await tester.tap(find.byTooltip('播放速度'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.ancestor(
          of: find.text('2.0x'),
          matching: find.byType(CheckedPopupMenuItem<double>),
        ),
      );
      await tester.pumpAndSettle();
      expect(engine.currentSnapshot.rate, 2);
      await tester.tap(find.byTooltip('听视频选项'));
      await tester.pumpAndSettle();
      final volume = find.byType(Slider).last;
      await tester.drag(volume, const Offset(-40, 0));
      await tester.pump();
      expect(engine.currentSnapshot.volume, lessThan(100));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'shared player menu enters listening without a video surface or danmaku',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [playbackSessionProvider.overrideWithValue(session)],
          child: InputTestApp(
            home: Scaffold(
              body: SizedBox(
                width: 390,
                height: 220,
                child: PlaybackPanel(
                  detail: _detail,
                  part: _part,
                  settings: AppSettings(
                    autoPlay: true,
                    resumePlayback: false,
                    playerControlsMode: PlayerControlsMode.dynamic,
                  ),
                  onToggleComments: () {},
                  window: _Window(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(RegExp('^全屏')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('听视频'));
      await tester.pumpAndSettle();
      expect(find.byType(AudioPlaybackView), findsOneWidget);
      expect(find.byType(VideoSurface), findsNothing);
      expect(engine.sources.last, isA<ProgressiveSource>());
      final opens = engine.sources.length;
      await tester.tap(find.byTooltip('退出全屏'));
      await tester.pumpAndSettle();
      expect(session.audioOnly, isTrue);
      expect(engine.sources.length, opens);
      await tester.tap(find.byTooltip('全屏'));
      await tester.pumpAndSettle();
      expect(find.byType(AudioPlaybackView), findsOneWidget);
      expect(engine.sources.length, opens);
      await tester.tap(find.byTooltip('退出全屏'));
      await tester.pumpAndSettle();
      expect(session.audioOnly, isTrue);
      expect(engine.sources.length, opens);
      await tester.tap(find.byKey(const ValueKey('audio-return-video')));
      await tester.pumpAndSettle();
      expect(find.byType(VideoSurface), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

const _part = VideoPart(
  cid: 'one',
  page: 1,
  title: '第一集',
  duration: Duration(minutes: 10),
);
const _detail = VideoDetail(
  summary: VideoSummary(
    id: VideoId('BV1abc123456'),
    title: '在声音里，继续探索世界',
    author: '哔帆',
    coverUrl: '',
    duration: Duration(minutes: 10),
  ),
  description: '',
  parts: [_part],
);

PlaybackMedia _media({
  PlaybackMediaKind kind = PlaybackMediaKind.dash,
  bool audio = true,
}) => PlaybackMedia(
  video: PlaybackTrack(
    urls: [
      Uri.parse('https://example.test/video'),
      Uri.parse('https://backup.test/video'),
    ],
    codec: 'avc1',
    bandwidth: 1000,
  ),
  audio: audio
      ? PlaybackTrack(
          urls: [
            Uri.parse('https://example.test/audio'),
            Uri.parse('https://backup.test/audio'),
          ],
          codec: 'mp4a',
          bandwidth: 128,
        )
      : null,
  quality: 80,
  qualities: const [64, 80],
  duration: const Duration(minutes: 10),
  headers: const {'Referer': 'https://www.bilibili.com/'},
  kind: kind,
);

class _Repository extends Fake implements PlaybackRepository {
  PlaybackMedia media = _media();
  Completer<PlaybackMedia>? pending;
  int commentRequests = 0;
  @override
  Future<PlaybackMedia> resolve(
    VideoId target,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async {
    final gate = pending;
    pending = null;
    return gate == null ? media : gate.future;
  }

  @override
  Future<List<TimedComment>> comments(
    String cid,
    int segment, {
    required RequestCancellation cancellation,
  }) async {
    commentRequests++;
    return [];
  }

  @override
  Future<List<SubtitleTrack>> subtitles(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  }) async => [];
  @override
  Future<List<SubtitleCue>> subtitleCues(
    SubtitleTrack track, {
    required RequestCancellation cancellation,
  }) async => [];
}

class _Content extends Fake implements ContentPlaybackRepository {
  _Content(this.repository);
  final _Repository repository;
  @override
  Future<PlaybackMedia> resolve(
    ContentPlaybackTarget target, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) => repository.resolve(
    _detail.summary.id,
    _part.cid,
    quality: quality,
    preferredCodec: preferredCodec,
    cancellation: cancellation,
  );
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

class _Engine extends Fake implements PlayerEngine, VideoOutputSource {
  final events = StreamController<PlaybackSnapshot>.broadcast(sync: true);
  final errors = StreamController<PlayerFailure>.broadcast(sync: true);
  final sources = <ResolvedMediaSource>[];
  bool failNextAudio = false;
  Completer<void>? nextSeek;
  PlaybackSnapshot value = const PlaybackSnapshot(
    phase: PlaybackPhase.idle,
    generation: 0,
  );
  @override
  PlaybackSnapshot get currentSnapshot => value;
  @override
  Stream<PlaybackSnapshot> get snapshots => events.stream;
  @override
  Stream<PlayerFailure> get failures => errors.stream;
  @override
  late final VideoOutput videoOutput = FakeVideoOutput(
    () => const ColoredBox(color: Colors.black),
  );
  void publish(PlaybackSnapshot next) {
    value = next;
    events.add(next);
  }

  @override
  Future<void> open(ResolvedMediaSource source, OpenOptions options) async {
    sources.add(source);
    if (source is ProgressiveSource && failNextAudio) {
      failNextAudio = false;
      throw PlayerFailure(
        PlayerFailureKind.nativePlayback,
        'fixture failure',
        value.generation,
      );
    }
    publish(
      PlaybackSnapshot(
        phase: PlaybackPhase.paused,
        generation: value.generation + 1,
        position: options.startPosition,
        duration: const Duration(minutes: 10),
        rate: options.rate,
        volume: options.volume,
        desiredPlaying: options.play,
      ),
    );
  }

  @override
  Future<void> play() async => publish(
    value.copyWith(phase: PlaybackPhase.playing, desiredPlaying: true),
  );
  @override
  Future<void> pause() async => publish(
    value.copyWith(phase: PlaybackPhase.paused, desiredPlaying: false),
  );
  @override
  Future<void> stop() async => publish(
    PlaybackSnapshot(
      phase: PlaybackPhase.idle,
      generation: value.generation + 1,
    ),
  );
  @override
  Future<void> seek(Duration target) async {
    await nextSeek?.future;
    publish(value.copyWith(position: target));
  }

  @override
  Future<void> setRate(double rate) async =>
      publish(value.copyWith(rate: rate));
  @override
  Future<void> setVolume(double volume) async =>
      publish(value.copyWith(volume: volume));
  @override
  Future<void> dispose() async {
    await events.close();
    await errors.close();
  }
}

class _Window extends WindowService {
  @override
  bool get hasDesktopWindow => true;
  @override
  Future<void> setFullScreen(
    bool value, {
    FullScreenOrientation? orientation,
  }) async {}
}

class _AndroidWindow extends _Window {
  @override
  bool get supportsBackgroundAudio => true;
  @override
  bool get hasDesktopWindow => false;
  @override
  Stream<FullScreenOrientation> get deviceOrientations => const Stream.empty();
}
