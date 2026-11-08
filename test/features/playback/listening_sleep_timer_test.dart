import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/application/playback_manager.dart';
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

  Future<void> flush(WidgetTester tester, Future<void> operation) async {
    var done = false;
    unawaited(operation.then((_) => done = true));
    for (var i = 0; !done && i < 20; i++) {
      await tester.pump(Duration.zero);
    }
    expect(done, isTrue, reason: 'Playback cleanup did not complete');
    await operation;
  }

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

  PlaybackManager manager(WidgetTester tester) {
    final value = PlaybackManager(
      sleepTimerNow: tester.binding.clock.now,
      createSession: (sleepTimer) {
        final session = PlaybackSession(
          engine: _Engine(),
          repository: _Repository(),
          contentRepository: _Content(),
          progress: _Progress(),
          accountScope: () => 'guest',
          sleepTimer: sleepTimer,
        );
        session.configureSettings(
          AppSettings(autoPlay: true, resumePlayback: false),
        );
        return session;
      },
    );
    addTearDown(() => flush(tester, value.close()));
    return value;
  }

  for (final concurrent in [false, true]) {
    testWidgets(
      'new playback pages share the deadline: concurrent=$concurrent',
      (tester) async {
        final playback = manager(tester);
        final first = playback.acquire('first');
        await playback.updateWorkspace(
          allowConcurrent: concurrent,
          activeTabId: 'first',
        );
        await first.open(_detail, _parts.first);
        first.startSleepTimer(const Duration(seconds: 10));
        await tester.pump(const Duration(seconds: 3));
        final second = playback.acquire('second');
        await playback.updateWorkspace(
          allowConcurrent: concurrent,
          activeTabId: 'second',
        );
        await second.open(_detail, _parts.last);
        expect(second.sleepTimer.remaining, const Duration(seconds: 7));
        expect(second.sleepTimer, same(first.sleepTimer));
        await second.pause();
        await tester.pump(const Duration(seconds: 2));
        expect(second.sleepTimer.remaining, const Duration(seconds: 5));
        await second.play();
        await tester.pump(const Duration(seconds: 5));
        for (final session in [first, second]) {
          expect(session.sleepTimer.elapsed, isTrue);
          expect(session.canAutoAdvance, isFalse);
          expect(session.engine.currentSnapshot.desiredPlaying, isFalse);
        }
        await playback.updateWorkspace(
          allowConcurrent: concurrent,
          activeTabId: 'first',
        );
        expect(first.engine.currentSnapshot.desiredPlaying, isFalse);
      },
    );
  }

  testWidgets(
    'closing the timer page preserves it until the last page closes',
    (tester) async {
      final playback = manager(tester);
      final first = playback.acquire('first');
      final second = playback.acquire('second');
      await first.open(_detail, _parts.first);
      await second.open(_detail, _parts.last);
      first.startSleepTimer(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 3));
      await tester.runAsync(() async {
        playback.release('first', first);
        await playback.drainReleases();
      });
      expect(second.sleepTimer.remaining, const Duration(seconds: 7));
      await tester.pump(const Duration(seconds: 7));
      expect(second.sleepTimer.elapsed, isTrue);
      expect(second.engine.currentSnapshot.desiredPlaying, isFalse);
      second.startSleepTimer(const Duration(seconds: 5));
      final closingGate = Completer<void>();
      (second.engine as CardFakeEngine).releasing = closingGate;
      await tester.runAsync(() async => playback.release('second', second));
      // A new page can mount while the previous native engine is still closing.
      final third = playback.acquire('third');
      await third.open(_detail, _parts.first);
      expect(third.sleepTimer.remaining, isNull);
      expect(third.sleepTimer.elapsed, isFalse);
      third.startSleepTimer(const Duration(seconds: 10));
      await tester.runAsync(() async {
        closingGate.complete();
        await playback.drainReleases();
      });
      await tester.pump(const Duration(seconds: 6));
      expect(third.sleepTimer.remaining, const Duration(seconds: 4));
      expect(third.engine.currentSnapshot.desiredPlaying, isTrue);
      await tester.pump(const Duration(seconds: 4));
      expect(third.engine.currentSnapshot.desiredPlaying, isFalse);
    },
  );

  testWidgets('expiry while a new page resolves prevents its late autoplay', (
    tester,
  ) async {
    final playback = manager(tester);
    final first = playback.acquire('first');
    await first.open(_detail, _parts.first);
    first.startSleepTimer(const Duration(seconds: 5));
    final second = playback.acquire('second');
    final repository = second.repository as _Repository;
    repository.pending = Completer<PlaybackMedia>();
    final loading = second.open(_detail, _parts.last, desiredPlaying: true);
    await tester.pump(const Duration(seconds: 5));
    repository.pending!.complete(cardPreviewMedia());
    await loading;
    expect(first.engine.currentSnapshot.desiredPlaying, isFalse);
    expect(second.engine.currentSnapshot.desiredPlaying, isFalse);
    expect(second.canAutoAdvance, isFalse);
    final third = playback.acquire('third');
    await third.open(_detail, _parts.first);
    expect(third.engine.currentSnapshot.desiredPlaying, isFalse);
  });

  for (final target in [
    const PgcPlaybackTarget('2', cid: '102'),
    const OfflinePlaybackTarget('2'),
    const LivePlaybackTarget('42'),
  ]) {
    testWidgets('new content pages preserve the shared timer: $target', (
      tester,
    ) async {
      final playback = manager(tester);
      final first = playback.acquire('first');
      await first.open(_detail, _parts.first);
      first.startSleepTimer(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 2));
      final second = playback.acquire('second');
      await second.open(null, null, target: target);
      expect(second.sleepTimer.remaining, const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      expect(first.engine.currentSnapshot.desiredPlaying, isFalse);
      expect(second.engine.currentSnapshot.desiredPlaying, isFalse);
    });
  }

  testWidgets('stop of one page preserves the timer; account stop clears it', (
    tester,
  ) async {
    final playback = manager(tester);
    final first = playback.acquire('first');
    final second = playback.acquire('second');
    await first.open(_detail, _parts.first);
    await second.open(_detail, _parts.last);
    first.startSleepTimer(const Duration(seconds: 10));
    await first.stop();
    await tester.pump(const Duration(seconds: 3));
    expect(second.sleepTimer.remaining, const Duration(seconds: 7));
    await playback.stop();
    expect(second.sleepTimer.remaining, isNull);
    await second.open(_detail, _parts.last);
    await tester.pump(const Duration(seconds: 8));
    expect(second.engine.currentSnapshot.desiredPlaying, isTrue);
  });

  testWidgets('timer replacement and cancellation are shared across pages', (
    tester,
  ) async {
    final playback = manager(tester);
    final first = playback.acquire('first');
    final second = playback.acquire('second');
    await first.open(_detail, _parts.first);
    await second.open(_detail, _parts.last);
    first.startSleepTimer(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 2));
    second.startSleepTimer(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 4));
    expect(first.sleepTimer.remaining, const Duration(seconds: 6));
    expect(first.engine.currentSnapshot.desiredPlaying, isTrue);
    first.sleepTimer.cancel();
    expect(second.sleepTimer.remaining, isNull);
    await tester.pump(const Duration(seconds: 7));
    expect(second.engine.currentSnapshot.desiredPlaying, isTrue);
  });

  for (final audioOnly in [false, true]) {
    testWidgets('expiry pauses until explicit play: audioOnly=$audioOnly', (
      tester,
    ) async {
      await open(tester);
      await session.setAudioOnly(audioOnly);
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
  }

  testWidgets('video and listening mode keep one original deadline', (
    tester,
  ) async {
    await open(tester);
    session.startSleepTimer(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 2));
    await session.setAudioOnly(true);
    expect(session.sleepTimer.remaining, const Duration(seconds: 8));
    await tester.pump(const Duration(seconds: 2));
    await session.setAudioOnly(false);
    expect(session.sleepTimer.remaining, const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 6));
    expect(session.audioOnly, isFalse);
    expect(engine.currentSnapshot.desiredPlaying, isFalse);
  });

  testWidgets('timer accepts 1440 minutes and rejects out-of-range values', (
    tester,
  ) async {
    await open(tester);
    session.startSleepTimer(const Duration(minutes: 1440));
    expect(session.sleepTimer.remaining, const Duration(minutes: 1440));
    for (final invalid in [Duration.zero, const Duration(minutes: 1441)]) {
      expect(() => session.startSleepTimer(invalid), throwsArgumentError);
      expect(session.sleepTimer.remaining, const Duration(minutes: 1440));
    }
    session.sleepTimer.cancel();
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

  for (final action in ['cancel', 'stop', 'close']) {
    testWidgets('$action cancels without affecting a later listening session', (
      tester,
    ) async {
      await open(tester);
      await session.setAudioOnly(true);
      session.startSleepTimer(const Duration(seconds: 5));
      switch (action) {
        case 'cancel':
          session.sleepTimer.cancel();
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

  for (final audioOnly in [false, true]) {
    testWidgets(
      'expiry during a mode switch prevents late playback: $audioOnly',
      (tester) async {
        await open(tester);
        await session.setAudioOnly(!audioOnly);
        session.startSleepTimer(const Duration(seconds: 5));
        repository.pending = Completer<PlaybackMedia>();
        final changing = session.setAudioOnly(audioOnly);
        await tester.pump();
        await tester.pump(const Duration(seconds: 5));
        repository.pending!.complete(cardPreviewMedia());
        await changing;
        expect(session.error, isNull);
        expect(session.audioOnly, audioOnly);
        expect(session.sleepTimer.elapsed, isTrue);
        expect(engine.currentSnapshot.desiredPlaying, isFalse);
      },
    );
  }

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
    expect(session.canAutoAdvance, isFalse);
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
        expect(find.text('请输入 1–1440 分钟'), findsOneWidget);
        await tester.enterText(find.byType(TextField), '1441');
        await tester.tap(find.text('开始计时'));
        await tester.pumpAndSettle();
        expect(find.text('请输入 1–1440 分钟'), findsOneWidget);
        await tester.enterText(find.byType(TextField), '1440');
        await tester.tap(find.text('开始计时'));
        await tester.pumpAndSettle();
        expect(session.sleepTimer.remaining, isNotNull);
        expect(session.sleepTimer.remaining!.inMinutes, 1439);
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

  for (final compact in [false, true]) {
    testWidgets('video timer uses ${compact ? 'more menu' : 'top bar'}', (
      tester,
    ) async {
      await open(tester);
      tester.view.physicalSize = compact
          ? const Size(320, 800)
          : const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [playbackSessionProvider.overrideWithValue(session)],
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  height: compact ? 220 : 506,
                  child: PlaybackPanel(
                    detail: _detail,
                    part: _parts.first,
                    settings: AppSettings(
                      danmakuEnabled: false,
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
        ),
      );
      await tester.pumpAndSettle();
      expect(session.error, isNull);
      if (compact) {
        expect(
          find.byKey(const ValueKey('listening-sleep-timer')),
          findsNothing,
        );
        await tester.tap(find.byTooltip('更多播放选项'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('player-sleep-timer-menu')));
      } else {
        final timer = find.byKey(const ValueKey('listening-sleep-timer'));
        expect(tester.widget<IconButton>(timer).color, Colors.white);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('player-control-title-layer')),
            matching: timer,
          ),
          findsOneWidget,
        );
        await tester.tap(timer);
      }
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      // Timer setup must keep its launching controls mounted past auto-hide.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始计时'));
      await tester.pumpAndSettle();
      expect(session.audioOnly, isFalse);
      expect(session.sleepTimer.remaining, isNotNull);
      if (compact) {
        expect(
          find.byKey(const ValueKey('player-more-dialog')),
          findsOneWidget,
        );
        expect(find.textContaining('后暂停'), findsOneWidget);
      } else {
        expect(find.byTooltip(RegExp('定时关闭：')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
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
