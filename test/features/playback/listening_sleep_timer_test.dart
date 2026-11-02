import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/content_playback.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/playback/presentation/audio_playback_view.dart';
import 'package:bilisail/features/playback/presentation/playback_panel.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/shared/ui/playback_page_commands.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../support/video_card_fake_engine.dart';

void main() {
  late _Engine engine;
  late _Repository repository;
  late PlaybackSession session;

  Future<void> open(WidgetTester tester, {DateTime Function()? now}) async {
    engine = _Engine();
    repository = _Repository();
    session = PlaybackSession(
      engine: engine,
      repository: repository,
      contentRepository: _Content(),
      progress: _Progress(),
      accountScope: () => 'guest',
      sleepTimerNow: now ?? tester.binding.clock.now,
    );
    session.configureSettings(
      AppSettings(autoPlay: true, resumePlayback: false),
    );
    addTearDown(session.close);
    await session.open(_detail, _parts.first);
  }

  testWidgets('timer is listening-only and expiry pauses until explicit play', (
    tester,
  ) async {
    await open(tester);
    session.startSleepTimer(const Duration(seconds: 5));
    expect(session.sleepTimer.remaining, isNull);
    await session.setAudioOnly(true);
    session.startSleepTimer(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    expect(engine.currentSnapshot.desiredPlaying, isFalse);
    expect(session.sleepTimer.elapsed, isTrue);
    expect(session.canAutoAdvance, isFalse);
    await session.retry();
    expect(engine.currentSnapshot.desiredPlaying, isFalse);
    await session.play();
    expect(engine.currentSnapshot.desiredPlaying, isTrue);
    expect(session.canAutoAdvance, isTrue);
  });

  for (final target in [
    null,
    const PgcPlaybackTarget('2', cid: '102'),
    const OfflinePlaybackTarget('2'),
  ]) {
    testWidgets('source changes keep the original deadline: $target', (
      tester,
    ) async {
      await open(tester);
      await session.setAudioOnly(true);
      session.startSleepTimer(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 4));
      await session.open(_detail, _parts.last, target: target);
      expect(session.audioOnly, isTrue);
      expect(session.sleepTimer.remaining, const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 6));
      expect(engine.currentSnapshot.desiredPlaying, isFalse);
    });
  }

  testWidgets('pause, buffering and a hidden page keep counting', (
    tester,
  ) async {
    await open(tester);
    final owner = Object();
    session.attach(owner);
    await session.activate(owner, _detail, _parts.first);
    await session.setAudioOnly(true);
    session.startSleepTimer(const Duration(seconds: 10));
    await session.pause();
    await session.deactivate(owner);
    await tester.pump(const Duration(seconds: 4));
    expect(session.sleepTimer.remaining, const Duration(seconds: 6));
    await session.play();
    engine.publish(engine.snapshot.copyWith(isBuffering: true));
    await tester.pump(const Duration(seconds: 6));
    expect(engine.currentSnapshot.desiredPlaying, isFalse);
    await session.activate(owner, _detail, _parts.first);
    expect(engine.currentSnapshot.desiredPlaying, isFalse);
  });

  for (final action in ['cancel', 'video', 'stop', 'close']) {
    testWidgets('$action cancels without affecting a later listening session', (
      tester,
    ) async {
      await open(tester);
      await session.setAudioOnly(true);
      session.startSleepTimer(const Duration(seconds: 5));
      switch (action) {
        case 'cancel':
          session.sleepTimer.cancel();
        case 'video':
          await session.setAudioOnly(false);
          await session.setAudioOnly(true);
        case 'stop':
          await session.stop();
          await session.open(_detail, _parts.first);
          await session.setAudioOnly(true);
        case 'close':
          await tester.runAsync(session.close);
      }
      expect(session.sleepTimer.remaining, isNull);
      await tester.pump(const Duration(seconds: 6));
      if (action != 'close') {
        expect(engine.currentSnapshot.desiredPlaying, isTrue);
        expect(session.sleepTimer.elapsed, isFalse);
      }
    });
  }

  testWidgets('expiry while the next source resolves prevents late autoplay', (
    tester,
  ) async {
    await open(tester);
    await session.setAudioOnly(true);
    session.startSleepTimer(const Duration(seconds: 5));
    repository.pending = Completer<PlaybackMedia>();
    final loading = session.open(_detail, _parts.last, desiredPlaying: true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    repository.pending!.complete(cardPreviewMedia());
    await loading;
    expect(session.error, isNull);
    expect(engine.currentSnapshot.desiredPlaying, isFalse);
  });

  testWidgets('replacing a timer revokes the old alarm', (tester) async {
    await open(tester);
    await session.setAudioOnly(true);
    session.startSleepTimer(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 2));
    session.startSleepTimer(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 4));
    expect(engine.currentSnapshot.desiredPlaying, isTrue);
    expect(session.sleepTimer.remaining, const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 6));
    expect(engine.currentSnapshot.desiredPlaying, isFalse);
  });

  testWidgets(
    'expiry revokes a next-route intent before the new owner mounts',
    (tester) async {
      await open(tester);
      await session.setAudioOnly(true);
      session.startSleepTimer(const Duration(seconds: 5));
      engine.publish(engine.snapshot.copyWith(phase: PlaybackPhase.ended));
      expect(
        session.prepareNextVideo(
          _detail.summary.id,
          _parts.first.cid,
          nextId: _detail.summary.id,
          nextCid: _parts.last.cid,
          completed: true,
        ),
        isTrue,
      );
      await tester.pump(const Duration(seconds: 5));
      final owner = Object();
      session.attach(owner);
      await session.activate(owner, _detail, _parts.last);
      expect(session.audioOnly, isTrue);
      expect(session.sleepTimer.elapsed, isTrue);
      expect(engine.currentSnapshot.desiredPlaying, isFalse);
    },
  );

  testWidgets('continuous playback and fullscreen keep the listening timer', (
    tester,
  ) async {
    await open(tester);
    var part = _parts.first;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playbackSessionProvider.overrideWithValue(session)],
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (_, update) => PlaybackPageCommands(
              previousPart: () {},
              nextPart: () {},
              toggleInfo: () {},
              hasNext: part == _parts.first,
              onCompleted: () {
                if (session.prepareNextVideo(
                  _detail.summary.id,
                  part.cid,
                  nextId: _detail.summary.id,
                  nextCid: _parts.last.cid,
                  completed: true,
                )) {
                  update(() => part = _parts.last);
                }
              },
              child: PlaybackPanel(
                window: _Window(),
                detail: _detail,
                part: part,
                settings: AppSettings(
                  continuousPlayback: true,
                  resumePlayback: false,
                  danmakuEnabled: false,
                ),
                onToggleComments: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('listening-sleep-timer')), findsNothing);
    await session.setAudioOnly(true);
    await tester.pumpAndSettle();
    session.startSleepTimer(const Duration(minutes: 1));
    await tester.pump(const Duration(seconds: 5));
    engine.publish(engine.snapshot.copyWith(phase: PlaybackPhase.ended));
    await tester.pumpAndSettle();
    expect(session.part, _parts.last);
    expect(session.audioOnly, isTrue);
    expect(engine.currentSnapshot.desiredPlaying, isTrue);
    final left = session.sleepTimer.remaining!;
    expect(left, lessThan(const Duration(seconds: 56)));
    await tester.tap(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    expect(session.sleepTimer.remaining, lessThanOrEqualTo(left));
    await tester.tap(find.byTooltip('退出全屏'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 1));
    expect(engine.currentSnapshot.desiredPlaying, isFalse);
    await session.setAudioOnly(false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('listening-sleep-timer')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('expiry gates a queued EOF completion and related autoplay', (
    tester,
  ) async {
    var now = DateTime(2026, 11, 2);
    await open(tester, now: () => now);
    var completions = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playbackSessionProvider.overrideWithValue(session)],
        child: MaterialApp(
          home: PlaybackPageCommands(
            previousPart: () {},
            nextPart: () {},
            toggleInfo: () {},
            hasNext: true,
            onCompleted: () => completions++,
            child: PlaybackPanel(
              window: _Window(),
              detail: _detail,
              part: _parts.first,
              settings: AppSettings(
                autoPlay: true,
                continuousPlayback: true,
                continuousRelatedPlayback: true,
                resumePlayback: false,
                danmakuEnabled: false,
              ),
              onToggleComments: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await session.setAudioOnly(true);
    session.startSleepTimer(const Duration(seconds: 5));
    engine.publish(engine.snapshot.copyWith(phase: PlaybackPhase.ended));
    // Completion is queued, but cancellation must win before it runs.
    now = now.add(const Duration(seconds: 6));
    await tester.pump();
    session.sleepTimer.checkDeadline();
    await tester.pump();
    expect(completions, 0);
    expect(session.continuousRelatedPlaybackEnabled, isFalse);
    expect(
      session.prepareNextVideo(
        _detail.summary.id,
        _parts.first.cid,
        nextId: _detail.summary.id,
        nextCid: _parts.last.cid,
        completed: true,
      ),
      isFalse,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in [const Size(320, 220), const Size(900, 506)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('timer options and countdown at $size / $scale', (
        tester,
      ) async {
        await open(tester);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await session.setAudioOnly(true);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: AudioPlaybackView(
              session: session,
              snapshot: session.snapshots.value,
              fullScreen: false,
              navigation: const SizedBox.shrink(),
              onFullScreen: () {},
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('listening-sleep-timer')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('自定义'));
        await tester.tap(find.text('自定义'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '0');
        await tester.ensureVisible(find.text('开始计时'));
        await tester.tap(find.text('开始计时'));
        await tester.pumpAndSettle();
        expect(find.text('请输入 1–180 分钟'), findsOneWidget);
        await tester.enterText(find.byType(TextField), '1');
        await tester.tap(find.text('开始计时'));
        await tester.pumpAndSettle();
        expect(session.sleepTimer.remaining, isNotNull);
        expect(find.byType(AlertDialog), findsNothing);
        await tester.pump(const Duration(seconds: 1));
        expect(find.byTooltip(RegExp('定时关闭：')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('listening-sleep-timer')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消定时'));
        await tester.pumpAndSettle();
        expect(session.sleepTimer.remaining, isNull);
        expect(engine.currentSnapshot.desiredPlaying, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}

const _parts = [
  VideoPart(cid: '101', page: 1, title: 'P1', duration: Duration(seconds: 20)),
  VideoPart(cid: '102', page: 2, title: 'P2', duration: Duration(seconds: 20)),
];
const _detail = VideoDetail(
  summary: VideoSummary(
    id: VideoId('BV1234567890'),
    title: '听视频',
    author: 'UP',
    coverUrl: '',
    duration: Duration(seconds: 20),
  ),
  description: '',
  parts: _parts,
);

class _Engine extends CardFakeEngine {
  @override
  Future<void> play() async => publish(
    snapshot.copyWith(phase: PlaybackPhase.playing, desiredPlaying: true),
  );
  @override
  Future<void> pause() async => publish(
    snapshot.copyWith(phase: PlaybackPhase.paused, desiredPlaying: false),
  );
}

class _Repository extends Fake implements PlaybackRepository {
  Completer<PlaybackMedia>? pending;
  @override
  Future<PlaybackMedia> resolve(
    VideoId target,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => pending == null ? cardPreviewMedia() : pending!.future;

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
  }) async => [];
}

class _Content extends Fake implements ContentPlaybackRepository {
  @override
  Future<PlaybackMedia> resolve(
    ContentPlaybackTarget target, {
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

class _Window extends WindowService {
  @override
  bool get hasDesktopWindow => true;
  @override
  Future<void> setFullScreen(
    bool value, {
    FullScreenOrientation? orientation,
  }) async {}
}
