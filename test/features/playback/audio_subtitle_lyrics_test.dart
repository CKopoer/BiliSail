import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/playback/presentation/audio_playback_view.dart';
import 'package:bilisail/features/playback/presentation/audio_subtitle_lyrics.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/video_card_fake_engine.dart';

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
    session =
        PlaybackSession(
          engine: engine,
          repository: repository,
          progress: _Progress(),
          accountScope: () => 'guest',
        )..configureSettings(
          AppSettings(
            resumePlayback: false,
            autoPlay: false,
            subtitlesEnabled: false,
            danmakuEnabled: false,
          ),
        );
  });
  tearDown(() => session.close());

  Future<void> listen() async {
    await session.open(_detail, _part);
    await session.setAudioOnly(true);
    await session.pause();
  }

  Future<void> mount(WidgetTester tester, {bool enabled = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BiliTheme.light(),
        home: Scaffold(
          body: TickerMode(
            enabled: enabled,
            child: ListenableBuilder(
              listenable: session,
              builder: (context, _) => AudioPlaybackView(
                session: session,
                snapshot: session.snapshots.value,
                fullScreen: false,
                onFullScreen: () {},
                navigation: const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  FixedExtentScrollController controller(WidgetTester tester) =>
      tester
              .widget<ListWheelScrollView>(find.byType(ListWheelScrollView))
              .controller!
          as FixedExtentScrollController;

  test(
    'listening defaults to lyrics without changing video subtitle default',
    () async {
      await session.open(_detail, _part);
      expect(session.selectedSubtitle, -1);
      await session.setAudioOnly(true);
      await Future<void>.delayed(Duration.zero);
      expect(session.selectedSubtitle, 0);
      expect(session.subtitleCues, hasLength(100));
      await session.setAudioOnly(false);
      await Future<void>.delayed(Duration.zero);
      expect(session.selectedSubtitle, -1);
      await session.setAudioOnly(true);
      await Future<void>.delayed(Duration.zero);
      await session.selectSubtitle(-1);
      await session.retry();
      await Future<void>.delayed(Duration.zero);
      expect(session.selectedSubtitle, -1);
      expect(session.subtitleCues, isEmpty);
    },
  );

  testWidgets('current sentence follows, preserves gaps and seeks both ways', (
    tester,
  ) async {
    await listen();
    await mount(tester);
    expect(controller(tester).selectedItem, 0);
    engine.advance(const Duration(seconds: 61));
    await tester.pumpAndSettle();
    expect(controller(tester).selectedItem, 6);
    final selected = tester.widget<Text>(find.text('第 6 句字幕'));
    expect(selected.style!.fontWeight, FontWeight.w600);
    engine.advance(const Duration(seconds: 69));
    await tester.pumpAndSettle();
    expect(controller(tester).selectedItem, 6);
    expect(
      tester.widget<Text>(find.text('第 6 句字幕')).style!.fontWeight,
      FontWeight.w400,
    );
    engine.advance(const Duration(seconds: 21));
    await tester.pumpAndSettle();
    expect(controller(tester).selectedItem, 2);
    expect(engine.seeks, 0, reason: 'automatic following must never seek');
  });

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets('$kind drag only browses until a sentence is tapped', (
      tester,
    ) async {
      await listen();
      engine.advance(const Duration(seconds: 51));
      await mount(tester);
      final lyrics = find.byKey(const ValueKey('audio-subtitle-lyrics'));
      final gesture = await tester.startGesture(
        tester.getCenter(lyrics),
        kind: kind,
      );
      await gesture.moveBy(const Offset(0, -90));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.moveBy(const Offset(0, -70));
      await tester.pump(const Duration(milliseconds: 300));
      expect(engine.seeks, 0);
      engine.advance(const Duration(seconds: 91));
      await tester.pump();
      expect(controller(tester).selectedItem, isNot(9));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(engine.seeks, 0);
      expect(engine.currentSnapshot.position, const Duration(seconds: 91));
      final browsed = controller(tester).selectedItem;
      engine.advance(const Duration(seconds: 101));
      await tester.pumpAndSettle();
      expect(controller(tester).selectedItem, browsed);
      await tester.tap(find.byKey(ValueKey('audio-subtitle-$browsed')));
      await tester.pumpAndSettle();
      expect(engine.seeks, 1);
      expect(
        engine.currentSnapshot.position,
        Duration(seconds: controller(tester).selectedItem * 10),
      );
      expect(engine.currentSnapshot.desiredPlaying, isFalse);
    });
  }

  testWidgets('mouse wheel only browses and clicking resumes following', (
    tester,
  ) async {
    await listen();
    engine.advance(const Duration(seconds: 51));
    await mount(tester);
    final center = tester.getCenter(find.byType(ListWheelScrollView));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: center,
        scrollDelta: const Offset(0, 140),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(engine.seeks, 0);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: center,
        scrollDelta: const Offset(0, 70),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(engine.seeks, 0);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(engine.seeks, 0);
    expect(engine.currentSnapshot.position, const Duration(seconds: 51));
    final next = controller(tester).selectedItem + 1;
    await tester.tap(find.byKey(ValueKey('audio-subtitle-$next')));
    await tester.pumpAndSettle();
    expect(engine.currentSnapshot.position, Duration(seconds: next * 10));
    expect(engine.seeks, 1);
    engine.advance(Duration(seconds: (next + 1) * 10));
    await tester.pumpAndSettle();
    expect(controller(tester).selectedItem, next + 1);
  });

  testWidgets('pending seek and track replacement cannot restore old lyrics', (
    tester,
  ) async {
    await listen();
    engine.advance(const Duration(seconds: 51));
    await mount(tester);
    final pending = Completer<void>();
    engine.nextSeek = pending;
    await tester.tap(find.byKey(const ValueKey('audio-subtitle-6')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.text('第 6 句字幕')).style!.fontWeight,
      FontWeight.w600,
    );
    await session.selectSubtitle(1);
    await tester.pumpAndSettle();
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('第 6 句字幕'), findsNothing);
    expect(find.text('另一轨 6'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    engine.advance(const Duration(seconds: 81));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('source change during drag discards the old gesture', (
    tester,
  ) async {
    await listen();
    await mount(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListWheelScrollView)),
    );
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    await session.retry();
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(engine.seeks, 0);
    expect(controller(tester).selectedItem, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled drag returns to playback without seeking', (
    tester,
  ) async {
    await listen();
    engine.advance(const Duration(seconds: 51));
    await mount(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListWheelScrollView)),
    );
    await gesture.moveBy(const Offset(0, -140));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(engine.seeks, 0);
    expect(controller(tester).selectedItem, 5);
  });

  testWidgets('old seek completion keeps a newer sentence preview', (
    tester,
  ) async {
    await listen();
    engine.advance(const Duration(seconds: 51));
    await mount(tester);
    final first = Completer<void>();
    final second = Completer<void>();
    engine.nextSeek = first;
    await tester.tap(find.byKey(const ValueKey('audio-subtitle-6')));
    await tester.pump();
    engine.nextSeek = second;
    await tester.tap(find.byKey(const ValueKey('audio-subtitle-4')));
    await tester.pump();
    first.complete();
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.text('第 4 句字幕')).style!.fontWeight,
      FontWeight.w600,
    );
    expect(
      tester.widget<Text>(find.text('第 6 句字幕')).style!.fontWeight,
      FontWeight.w400,
    );
    second.complete();
    await tester.pumpAndSettle();
    expect(controller(tester).selectedItem, 4);
  });

  testWidgets('resize and text scaling preserve the current sentence', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await listen();
    engine.advance(const Duration(seconds: 251));
    await mount(tester);
    expect(controller(tester).selectedItem, 25);
    tester.view.physicalSize = const Size(390, 220);
    await tester.pumpAndSettle();
    expect(controller(tester).selectedItem, 25);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(controller(tester).selectedItem, 25);
    expect(engine.seeks, 0);
  });

  testWidgets('overlaps retain source priority and invalid cues are omitted', (
    tester,
  ) async {
    await listen();
    session.subtitleCues = const [
      SubtitleCue(Duration(seconds: 10), Duration(seconds: 18), '优先句'),
      SubtitleCue(Duration.zero, Duration(seconds: 15), '早开始的句子'),
      SubtitleCue(Duration(seconds: 10), Duration(seconds: 10), '无效时间'),
      SubtitleCue(Duration(seconds: 10), Duration(seconds: 20), '  '),
    ];
    engine.advance(const Duration(seconds: 11));
    await mount(tester);
    expect(controller(tester).selectedItem, 1);
    expect(
      tester.widget<Text>(find.text('优先句')).style!.fontWeight,
      FontWeight.w600,
    );
    expect(find.text('无效时间'), findsNothing);
    engine.advance(Duration.zero);
    await tester.pumpAndSettle();
    expect(controller(tester).selectedItem, 0);
  });

  testWidgets('hidden and background lyrics stop lookups and cancel a drag', (
    tester,
  ) async {
    await listen();
    await mount(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListWheelScrollView)),
    );
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    await mount(tester, enabled: false);
    final lookups = session.subtitleLookupCount;
    for (var i = 1; i < 30; i++) {
      engine.advance(Duration(seconds: i));
      await tester.pump();
    }
    expect(session.subtitleLookupCount, lookups);
    await gesture.up();
    await mount(tester);
    expect(engine.seeks, 0);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(ListWheelScrollView)),
        scrollDelta: const Offset(0, 120),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump(const Duration(milliseconds: 300));
    final backgroundLookups = session.subtitleLookupCount;
    engine.advance(const Duration(seconds: 81));
    await tester.pump();
    expect(session.subtitleLookupCount, backgroundLookups);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(controller(tester).selectedItem, 8);
    expect(engine.seeks, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long transcript stays lazy and same-cue ticks do not rebuild it',
    (tester) async {
      repository.cueCount = 20000;
      await listen();
      await mount(tester);
      expect(find.byType(InkWell).evaluate().length, lessThan(30));
      final text = tester.widget<Text>(find.text('第 0 句字幕'));
      for (var i = 1; i < 100; i++) {
        engine.advance(Duration(milliseconds: i * 50));
        await tester.pump();
      }
      expect(tester.widget<Text>(find.text('第 0 句字幕')), same(text));
      expect(tester.binding.hasScheduledFrame, isFalse);
      engine.advance(const Duration(seconds: 190001));
      await tester.pumpAndSettle();
      expect(controller(tester).selectedItem, 19000);
      expect(find.byType(InkWell).evaluate().length, lessThan(30));
    },
  );

  testWidgets(
    'load failure, retry, disabled and missing subtitles remain usable',
    (tester) async {
      repository.failCues = true;
      await listen();
      await mount(tester);
      expect(find.text('字幕加载失败，请重新选择重试'), findsOneWidget);
      repository.failCues = false;
      await tester.tap(find.byTooltip('听视频选项'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<VoidCallback>, '中文'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AudioSubtitleLyrics), findsOneWidget);
      await session.selectSubtitle(-1);
      await tester.pumpAndSettle();
      expect(find.text('字幕已关闭，可在听视频选项中开启'), findsOneWidget);
      repository.tracks = [];
      await session.retry();
      await tester.pumpAndSettle();
      expect(find.text('暂无字幕'), findsOneWidget);
    },
  );

  for (final size in [
    const Size(320, 180),
    const Size(390, 220),
    const Size(390, 400),
    const Size(390, 760),
    const Size(900, 506),
    const Size(1400, 800),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('lyrics layout $size scale=$scale', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        repository.longText = true;
        await listen();
        engine.advance(const Duration(seconds: 51));
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: size.width >= 900 ? BiliTheme.dark() : BiliTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: RepaintBoundary(
              key: boundary,
              child: AudioPlaybackView(
                session: session,
                snapshot: session.snapshots.value,
                fullScreen: size.height > 600,
                onFullScreen: () {},
                navigation: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.arrow_back),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.home_outlined),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ListWheelScrollView), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (scale == 1) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
              'build/validation/audio-lyrics-${size.width.round()}x${size.height.round()}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
}

const _part = VideoPart(
  cid: 'one',
  page: 1,
  title: '第一集',
  duration: Duration(minutes: 20),
);
const _detail = VideoDetail(
  summary: VideoSummary(
    id: VideoId('BV1abc123456'),
    title: '在声音里，继续探索世界',
    author: '哔帆',
    coverUrl: '',
    duration: Duration(minutes: 20),
  ),
  description: '',
  parts: [_part],
);

class _Repository extends Fake implements PlaybackRepository {
  int cueCount = 100;
  bool failCues = false;
  bool longText = false;
  List<SubtitleTrack> tracks = [
    SubtitleTrack('中文', Uri.parse('https://example.test/zh')),
    SubtitleTrack('另一轨', Uri.parse('https://example.test/en')),
  ];
  @override
  Future<PlaybackMedia> resolve(
    VideoId target,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => cardPreviewMedia();
  @override
  Future<List<TimedComment>> comments(
    String cid,
    int segment, {
    required RequestCancellation cancellation,
  }) async => [];
  @override
  Future<List<SubtitleTrack>> subtitles(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  }) async => tracks;
  @override
  Future<List<SubtitleCue>> subtitleCues(
    SubtitleTrack track, {
    required RequestCancellation cancellation,
  }) async {
    if (failCues) throw StateError('fixture failure');
    return List.generate(
      cueCount,
      (i) => SubtitleCue(
        Duration(seconds: i * 10),
        Duration(seconds: i * 10 + 8),
        track.label == '中文'
            ? longText
                  ? '第 $i 句字幕，跟随声音探索世界，这是一句用于检查窄屏和大字体换行的较长字幕。'
                  : '第 $i 句字幕'
            : '另一轨 $i',
      ),
    );
  }
}

class _Engine extends CardFakeEngine {
  Completer<void>? nextSeek;
  @override
  Future<void> open(ResolvedMediaSource source, OpenOptions options) async {
    await super.open(source, options);
    publish(snapshot.copyWith(duration: const Duration(minutes: 20)));
  }

  @override
  Future<void> seek(Duration target) async {
    final pending = nextSeek;
    nextSeek = null;
    await pending?.future;
    await super.seek(target);
  }

  @override
  Future<void> play() async => publish(
    snapshot.copyWith(phase: PlaybackPhase.playing, desiredPlaying: true),
  );
  @override
  Future<void> pause() async => publish(
    snapshot.copyWith(phase: PlaybackPhase.paused, desiredPlaying: false),
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
