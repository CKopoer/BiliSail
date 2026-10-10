import 'dart:async';

import 'package:bilisail/domain/playback_rates.dart';
import 'package:bilisail/core/input/input_stroke.dart';
import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:bilisail/features/playback/application/playback_shortcut_controller.dart';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/application/playback_manager.dart';
import 'package:bilisail/features/playback/application/playback_rate_memory.dart';
import 'package:bilisail/features/video/application/watch_later_queue_playback.dart';
import 'package:bilisail/features/video/domain/watch_later_queue.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/playback/domain/content_playback.dart';
import 'package:bilisail/features/playback/domain/sponsor_repository.dart';
import 'package:bilisail/features/playback/domain/playback_history_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bili_player/bili_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final failure in [
    PlayerFailureKind.nativePlayback,
    PlayerFailureKind.invalidSource,
  ]) {
    test('CDN startup budget and recovery classify $failure', () async {
      final engine = _FakeEngine()..nextOpenFailure = failure;
      final repository = _FakeRepository();
      final session = PlaybackSession(
        engine: engine,
        repository: repository,
        progress: _FakeProgress(),
        accountScope: () => 'guest',
      );
      addTearDown(session.close);
      final opening = session.open(
        _detail('one'),
        _part('one'),
        position: const Duration(seconds: 17),
        desiredPlaying: false,
      );
      await _flush();
      repository.pendingResolves['one']!.complete(_backupMedia());
      await opening;
      expect(engine.openOptions.first.openTimeout, const Duration(seconds: 8));
      if (failure == PlayerFailureKind.nativePlayback) {
        expect(engine.openedUris, [
          _backupMedia().video.urls.first,
          _backupMedia().video.urls.last,
        ]);
        expect(
          (engine.sources.last as DashPairSource).audio?.uri,
          _backupMedia().audio?.urls.last,
        );
        expect(
          engine.openOptions.last.openTimeout,
          lessThanOrEqualTo(const Duration(seconds: 35)),
        );
        expect(
          engine.openOptions.last.openTimeout,
          greaterThan(const Duration(seconds: 8)),
        );
        expect(engine.currentSnapshot.position, const Duration(seconds: 17));
        expect(engine.currentSnapshot.desiredPlaying, false);
        expect(session.error, isNull);
      } else {
        expect(engine.openOptions, hasLength(1));
        expect(session.error, isNotNull);
      }
    });
  }

  test(
    'account replacement after a native failure cannot start the backup',
    () async {
      var scope = 'old';
      final engine = _FakeEngine()
        ..nextOpenFailure = PlayerFailureKind.nativePlayback
        ..onOpenFailure = () => scope = 'new';
      final repository = _FakeRepository();
      final session = PlaybackSession(
        engine: engine,
        repository: repository,
        progress: _FakeProgress(),
        accountScope: () => scope,
      );
      addTearDown(session.close);
      final opening = session.open(_detail('one'), _part('one'));
      await _flush();
      repository.pendingResolves['one']!.complete(_backupMedia());
      await opening;
      expect(engine.openOptions, hasLength(1));
      expect(session.media, isNull);
    },
  );

  test(
    'single URL retains the full startup budget and never repeats it',
    () async {
      final engine = _FakeEngine()
        ..nextOpenFailure = PlayerFailureKind.nativePlayback;
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        progress: _FakeProgress(),
        accountScope: () => 'guest',
      );
      addTearDown(session.close);
      await session.open(_detail('one'), _part('one'));
      expect(engine.openOptions, hasLength(1));
      expect(
        engine.openOptions.single.openTimeout,
        const Duration(seconds: 35),
      );
    },
  );

  test('voice switching preserves playback options, subtitle intent, refresh and owner checkpoints', () async {
    final engine = _FakeEngine();
    final repository = _VoiceRepository();
    final session = PlaybackSession(
      engine: engine,
      repository: repository,
      progress: _FakeProgress(),
      accountScope: () => 'guest',
    );
    addTearDown(session.close);
    session.configureSettings(AppSettings(subtitlesEnabled: true));
    final first = Object(), second = Object();
    session.attach(first);
    session.attach(second);
    await session.activate(first, _detail('one'), _part('one'));
    await _flush();
    await session.pause();
    await session.seek(const Duration(seconds: 35));
    await session.setRate(1.5);
    await session.setVolume(30);
    await session.changeVoice(_VoiceRepository.english);
    await _flush();
    expect(session.selectedVoice.key, '2:en');
    expect(session.selectedSubtitle, 1);
    expect(engine.sources.last, isA<DashPairSource>());
    expect(engine.currentSnapshot.position, const Duration(seconds: 35));
    expect(engine.currentSnapshot.rate, 1.5);
    expect(engine.currentSnapshot.volume, 30);
    expect(engine.currentSnapshot.desiredPlaying, isFalse);
    await session.selectSubtitle(0);
    await session.changeQuality(64);
    await _flush();
    expect(session.media?.quality, 64);
    expect(session.selectedVoice.key, '2:en');
    expect(session.selectedSubtitle, 0);
    await session.retry();
    await _flush();
    expect(session.selectedVoice.key, '2:en');
    await session.activate(second, _detail('two'), _part('two'));
    expect(session.selectedVoice.isOriginal, isTrue);
    await session.activate(first, _detail('one'), _part('one'));
    await _flush();
    expect(session.selectedVoice.key, '2:en');
    expect(engine.currentSnapshot.position, const Duration(seconds: 35));
    expect(engine.currentSnapshot.desiredPlaying, isFalse);
    await session.selectSubtitle(-1);
    await session.changeVoice(_VoiceRepository.japanese);
    await _flush();
    expect(session.selectedSubtitle, -1);
    await session.changeVoice(const PlaybackVoice.original());
    await _flush();
    expect(session.selectedVoice.isOriginal, isTrue);
    expect(session.selectedSubtitle, -1);
    expect(engine.maxSimultaneousPlayers, 1);
  });

  test('late voice responses cannot replace a newer language or lose the pending position', () async {
    final engine = _FakeEngine();
    final repository = _VoiceRepository()..delayVoices = true;
    final session = PlaybackSession(
      engine: engine,
      repository: repository,
      progress: _FakeProgress(),
      accountScope: () => 'guest',
    );
    addTearDown(session.close);
    await session.open(_detail('one'), _part('one'));
    await session.pause();
    await session.seek(const Duration(seconds: 35));
    await session.setRate(1.5);
    await _flush();
    await session.selectSubtitle(0);
    final english = session.changeVoice(_VoiceRepository.english);
    await _flush();
    final japanese = session.changeVoice(_VoiceRepository.japanese);
    await _flush();
    expect(repository.voiceCancellations['en']?.isCancelled, isTrue);
    repository.completeVoice('ja');
    await japanese;
    repository.completeVoice('en');
    await english;
    await _flush();
    expect(session.selectedVoice.key, '2:ja');
    expect(session.selectedSubtitle, 2);
    expect(engine.openedUris.last.path, '/video/ja');
    expect(engine.currentSnapshot.position, const Duration(seconds: 35));
    expect(engine.currentSnapshot.rate, 1.5);
    expect(engine.currentSnapshot.desiredPlaying, isFalse);
  });

  test(
    'voice response from an old account epoch does not open media',
    () async {
      var epoch = 1;
      final engine = _FakeEngine();
      final repository = _VoiceRepository()..delayVoices = true;
      final session = PlaybackSession(
        engine: engine,
        repository: repository,
        progress: _FakeProgress(),
        accountScope: () => 'same-account',
        sessionEpoch: () => epoch,
      );
      addTearDown(session.close);
      await session.open(_detail('one'), _part('one'));
      final voice = session.changeVoice(_VoiceRepository.english);
      await _flush();
      epoch++;
      repository.completeVoice('en');
      await voice;
      expect(engine.openedUris, hasLength(1));
      expect(session.media, isNull);
    },
  );

  test('subtitle loading, failure, empty body, retry and stale responses have distinct states', () async {
    final repository = _VoiceRepository()..delayCues = true;
    final session = PlaybackSession(
      engine: _FakeEngine(),
      repository: repository,
      progress: _FakeProgress(),
      accountScope: () => 'guest',
    );
    addTearDown(session.close);
    await session.open(_detail('one'), _part('one'));
    await _flush();
    final first = session.selectSubtitle(0);
    expect(session.subtitleLoading, isTrue);
    repository.cues.last.completeError(
      const AppFailure(AppFailureKind.network, 'failed'),
    );
    await first;
    expect(session.subtitleLoading, isFalse);
    expect(session.subtitleMessage, contains('加载失败'));
    final retry = session.selectSubtitle(0);
    expect(session.subtitleMessage, isNull);
    repository.cues.last.complete([]);
    await retry;
    expect(session.subtitleMessage, contains('没有可显示'));
    final stale = session.selectSubtitle(0);
    final fresh = session.selectSubtitle(1);
    repository.cues.last.complete([
      const SubtitleCue(Duration.zero, Duration(seconds: 3), 'fresh'),
    ]);
    await fresh;
    repository.cues[2].completeError(
      const AppFailure(AppFailureKind.network, 'stale'),
    );
    await stale;
    expect(session.subtitleMessage, isNull);
    expect(session.subtitleCues.single.text, 'fresh');
    await session.selectSubtitle(-1);
    expect(session.subtitleCues, isEmpty);
    expect(session.subtitleMessage, isNull);
  });

  test('relative media targets accumulate on a delayed engine with bounded pending work', () async {
    final engine = _FakeEngine();
    final session = PlaybackSession(
      engine: engine,
      repository: _FakeRepository(autoResolve: true),
      progress: _FakeProgress(),
      accountScope: () => 'guest',
    );
    addTearDown(session.close);
    await session.open(_detail('1'), _part('1'));
    final gate = Completer<void>();
    engine.nextRate = gate;
    final first = session.setRate(PlaybackRates.faster(session.commandRate));
    final second = session.setRate(PlaybackRates.faster(session.commandRate));
    expect(session.commandRate, 1.5);
    expect(engine.currentSnapshot.rate, 1);
    gate.complete();
    await Future.wait([first, second]);
    expect(engine.currentSnapshot.rate, 1.5);
    await session.setVolume(50);
    final volumeGate = Completer<void>();
    engine.nextVolume = volumeGate;
    final changes = <Future<void>>[
      session.setVolume(session.commandVolume + 5),
    ];
    for (var i = 0; i < 8; i++) {
      changes.add(session.setVolume(session.commandVolume + 5));
    }
    expect(session.commandVolume, 95);
    final calls = engine.volumeCalls;
    volumeGate.complete();
    await Future.wait(changes);
    expect(engine.currentSnapshot.volume, 95);
    expect(engine.volumeCalls, calls + 1);
  });
  testWidgets(
    'long hold release during delayed begin restores without a short seek',
    (tester) async {
      final engine = _FakeEngine();
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        progress: _FakeProgress(),
        accountScope: () => 'guest',
      );
      await tester.runAsync(() => session.open(_detail('1'), _part('1')));
      final shortcuts = PlaybackShortcutController(
        session: session,
        settings: () => const ShortcutSettings.defaults(),
        active: () => true,
        fullscreen: () => false,
        toggleFullscreen: () {},
        toggleDanmaku: () {},
        volumeFeedback: (_) {},
      );
      final gate = Completer<void>();
      engine.nextRate = gate;
      const down = InputStroke(
        identity: 'right',
        device: InputDevice.keyboard,
        phase: InputPhase.down,
        sequence: 1,
        chord: ShortcutChord('ArrowRight'),
      );
      await shortcuts.execute(ShortcutAction.seekForward, down);
      await tester.pump(const Duration(milliseconds: 401));
      await shortcuts.execute(
        ShortcutAction.seekForward,
        const InputStroke(
          identity: 'right',
          device: InputDevice.keyboard,
          phase: InputPhase.up,
          sequence: 2,
        ),
      );
      gate.complete();
      await tester.pump();
      await tester.pump();
      expect(engine.currentSnapshot.rate, 1);
      expect(engine.seekTargets, isEmpty);
      shortcuts.dispose();
      await tester.runAsync(session.close);
    },
  );
  test('permanent rate chosen during pending temporary speed survives restoration and inheritance', () async {
    final manager = _manager();
    addTearDown(manager.close);
    final session = manager.acquire('first');
    await session.open(_detail('1'), _part('1'));
    final gate = Completer<void>();
    (session.engine as _FakeEngine).nextRate = gate;
    final begin = session.beginTemporaryRate(3);
    final permanent = session.setRate(2);
    final end = session.endTemporaryRate();
    gate.complete();
    await Future.wait([begin, permanent, end]);
    expect(session.snapshots.value.rate, 2);
    final next = manager.acquire('next');
    await next.open(_detail('2'), _part('2'));
    expect(next.snapshots.value.rate, 2);
  });
  test('failed rate drains pending choices without replaying them', () async {
    final engine = _FakeEngine();
    final session = PlaybackSession(
      engine: engine,
      repository: _FakeRepository(autoResolve: true),
      progress: _FakeProgress(),
      accountScope: () => 'guest',
    );
    addTearDown(session.close);
    await session.open(_detail('1'), _part('1'));
    final gate = Completer<void>();
    engine.nextRate = gate;
    final first = session.setRate(1.25);
    final second = session.setRate(1.5);
    gate.completeError(
      PlayerFailure(
        PlayerFailureKind.nativePlayback,
        'rate failed',
        engine.currentSnapshot.generation,
      ),
    );
    await Future.wait([first, second]);
    expect(engine.currentSnapshot.rate, 1);
    expect(session.commandRate, 1);
    expect(session.error, 'rate failed');
  });

  test('offline content keeps local PGC progress without cloud reads, reports or sponsor requests', () async {
    final history = _FakeHistory();
    final progress = _FakeProgress()..readValue = null;
    final sponsor = _FakeSponsor();
    final session = PlaybackSession(
      engine: _FakeEngine(),
      repository: _FakeRepository(),
      contentRepository: _FakeContentRepository(),
      historyRepository: history,
      sponsorRepository: sponsor,
      progress: progress,
      accountScope: () => 'user:1',
    );
    addTearDown(session.close);
    session.configureSettings(
      AppSettings(autoPlay: false, sponsorBlockMode: SponsorBlockMode.manual),
    );
    await session.open(
      _detail('1'),
      _part('101'),
      target: const OfflinePlaybackTarget('local-task', episodeId: '7'),
    );
    expect(session.error, isNull);
    await session.togglePlaying();
    await session.seek(const Duration(seconds: 5));
    await session.stop();
    expect(history.reads, isEmpty);
    expect(history.reports, isEmpty);
    expect(sponsor.pending, isEmpty);
    expect(progress.writes.last.episodeId, '7');
  });

  for (final concurrent in [false, true]) {
    test(
      'new videos inherit the latest rate with concurrent playback: $concurrent',
      () async {
        final manager = _manager();
        addTearDown(manager.close);
        final first = manager.acquire('first');
        // An already-created page must read the rate when its video is opened.
        final second = manager.acquire('second');
        final owner = Object();
        first.attach(owner);
        first.configureSettings(AppSettings(defaultPlaybackRate: 1.25));
        second.configureSettings(AppSettings(defaultPlaybackRate: 1.25));
        await manager.updateWorkspace(
          allowConcurrent: concurrent,
          activeTabId: 'first',
        );
        await first.activate(owner, _detail('1'), _part('1'));
        expect(first.snapshots.value.rate, 1.25);
        await first.setRate(2);
        await manager.updateWorkspace(
          allowConcurrent: concurrent,
          activeTabId: 'second',
        );
        await second.open(_detail('2'), _part('2'));
        expect(second.snapshots.value.rate, 2);
        await second.setRate(.75);
        expect(first.snapshots.value.rate, 2);
        await first.changeQuality(64);
        expect(first.snapshots.value.rate, 2);
        await first.activate(owner, _detail('1'), _part('next-part'));
        expect(first.snapshots.value.rate, .75);
        manager.release('first', first);
        manager.release('second', second);
        await _flush();
        final third = manager.acquire('third');
        third.configureSettings(AppSettings(defaultPlaybackRate: 1.25));
        await third.open(_detail('3'), _part('3'));
        expect(third.snapshots.value.rate, .75);
      },
    );
  }

  test('a fresh application run uses the saved default instead of the previous run rate', () async {
    final settings = AppSettings(defaultPlaybackRate: 1.25);
    final previousRun = _manager();
    addTearDown(previousRun.close);
    final previous = previousRun.acquire('video');
    previous.configureSettings(settings);
    await previous.open(_detail('1'), _part('1'));
    await previous.setRate(2);
    await previousRun.close();

    final newRun = _manager();
    addTearDown(newRun.close);
    final current = newRun.acquire('video');
    current.configureSettings(settings);
    await current.open(_detail('2'), _part('2'));
    expect(current.snapshots.value.rate, 1.25);
    expect(settings.defaultPlaybackRate, 1.25);
  });

  test(
    'temporary speed and its restoration do not replace the shared rate',
    () async {
      final manager = _manager();
      addTearDown(manager.close);
      final first = manager.acquire('first');
      await first.open(_detail('1'), _part('1'));
      await first.setRate(1.5);
      await first.beginTemporaryRate(3);
      final second = manager.acquire('second');
      await second.open(_detail('2'), _part('2'));
      expect(second.snapshots.value.rate, 1.5);
      await second.setRate(2);
      await first.endTemporaryRate();
      expect(first.snapshots.value.rate, 1.5);
      final third = manager.acquire('third');
      await third.open(_detail('3'), _part('3'));
      expect(third.snapshots.value.rate, 2);
    },
  );

  test(
    'late rate completion in another tab cannot replace a newer choice',
    () async {
      final manager = _manager();
      addTearDown(manager.close);
      final first = manager.acquire('first');
      final second = manager.acquire('second');
      await first.open(_detail('1'), _part('1'));
      await second.open(_detail('2'), _part('2'));
      final gate = Completer<void>();
      (first.engine as _FakeEngine).nextRate = gate;
      final slowChange = first.setRate(1.5);
      await second.setRate(2);
      gate.complete();
      await slowChange;
      final third = manager.acquire('third');
      await third.open(_detail('3'), _part('3'));
      expect(first.snapshots.value.rate, 1.5);
      expect(third.snapshots.value.rate, 2);
    },
  );

  test(
    'failed or stale rate commands leave the last successful shared rate',
    () async {
      final manager = _manager();
      addTearDown(manager.close);
      final first = manager.acquire('first');
      await first.open(_detail('1'), _part('1'));
      await first.setRate(1.5);
      final engine = first.engine as _FakeEngine;
      final failure = Completer<void>();
      engine.nextRate = failure;
      final failedChange = first.setRate(3);
      failure.completeError(
        PlayerFailure(
          PlayerFailureKind.nativePlayback,
          'rate failed',
          engine.currentSnapshot.generation,
        ),
      );
      await failedChange;
      final stale = Completer<void>();
      engine.nextRate = stale;
      final staleChange = first.setRate(2);
      await first.open(_detail('next'), _part('next'));
      stale.complete();
      await staleChange;
      final second = manager.acquire('second');
      await second.open(_detail('2'), _part('2'));
      expect(second.snapshots.value.rate, 1.5);
    },
  );

  test('PGC inherits the shared rate while live and changed defaults cannot replace it', () async {
    final rates = PlaybackRateMemory();
    final manager = _manager(rateMemory: rates);
    addTearDown(manager.close);
    final video = manager.acquire('video');
    await video.open(_detail('video'), _part('video'));
    await video.setRate(2);
    final content = PlaybackSession(
      engine: _FakeEngine(),
      repository: _FakeRepository(autoResolve: true),
      contentRepository: _FakeContentRepository(),
      progress: _FakeProgress(),
      accountScope: () => 'guest',
      rateMemory: rates,
    );
    addTearDown(content.close);
    await content.open(null, null, target: const PgcPlaybackTarget('1'));
    expect(content.snapshots.value.rate, 2);
    await content.open(null, null, target: const LivePlaybackTarget('42'));
    await content.setRate(.5);
    expect(content.snapshots.value.rate, 1);
    content.configureSettings(AppSettings(defaultPlaybackRate: 1.25));
    await content.open(null, null, target: const PgcPlaybackTarget('2'));
    expect(content.snapshots.value.rate, 2);
    content.configureSettings(AppSettings(defaultPlaybackRate: 1.5));
    await _flush();
    expect(content.snapshots.value.rate, 2);
  });

  test('changing defaults before a manual rate choice does not become a session override', () async {
    final manager = _manager();
    addTearDown(manager.close);
    final first = manager.acquire('first');
    await first.open(_detail('1'), _part('1'));
    first.configureSettings(AppSettings(defaultPlaybackRate: 1.5));
    await _flush();
    expect(first.snapshots.value.rate, 1.5);
    final second = manager.acquire('second');
    second.configureSettings(AppSettings(defaultPlaybackRate: 2));
    await second.open(_detail('2'), _part('2'));
    expect(second.snapshots.value.rate, 2);
  });

  test(
    'multiple tabs keep independent sources and release only the closed tab',
    () async {
      final manager = _manager();
      addTearDown(manager.close);
      final first = manager.acquire('first');
      await manager.updateWorkspace(
        allowConcurrent: true,
        activeTabId: 'first',
      );
      await first.open(_detail('1'), _part('1'));
      await first.seek(const Duration(milliseconds: 1250));
      await first.setRate(1.5);
      final generation = first.sourceGeneration;
      final second = manager.acquire('second');
      await manager.updateWorkspace(
        allowConcurrent: true,
        activeTabId: 'second',
      );
      await second.open(_detail('2'), _part('2'));
      expect(first.snapshots.value.phase, PlaybackPhase.playing);
      expect(second.snapshots.value.phase, PlaybackPhase.playing);
      expect(first.sourceGeneration, generation);
      expect(
        first.snapshots.value.position,
        const Duration(milliseconds: 1250),
      );
      expect(first.snapshots.value.rate, 1.5);
      manager.release('first', first);
      await _flush();
      expect((first.engine as _FakeEngine).disposed, isTrue);
      expect(second.snapshots.value.phase, PlaybackPhase.playing);
      await manager.stop();
      expect(second.media, isNull);
    },
  );

  test('single page suspends other sources and preserves manual pause and preferences', () async {
    final manager = _manager();
    addTearDown(manager.close);
    final first = manager.acquire('first');
    await manager.updateWorkspace(allowConcurrent: false, activeTabId: 'first');
    await first.open(_detail('1'), _part('1'));
    await first.seek(const Duration(milliseconds: 1234));
    await first.setRate(1.5);
    await first.setVolume(25);
    final generation = first.sourceGeneration;
    final second = manager.acquire('second');
    await manager.updateWorkspace(
      allowConcurrent: false,
      activeTabId: 'second',
    );
    await second.open(_detail('2'), _part('2'));
    expect(first.snapshots.value.phase, PlaybackPhase.paused);
    expect(second.snapshots.value.phase, PlaybackPhase.playing);
    await manager.updateWorkspace(allowConcurrent: false, activeTabId: 'first');
    expect(second.snapshots.value.phase, PlaybackPhase.paused);
    expect(first.snapshots.value.phase, PlaybackPhase.playing);
    expect(first.sourceGeneration, generation);
    expect(first.snapshots.value.position, const Duration(milliseconds: 1234));
    expect(first.snapshots.value.rate, 1.5);
    expect(first.snapshots.value.volume, 25);
    await first.pause();
    await manager.updateWorkspace(
      allowConcurrent: false,
      activeTabId: 'second',
    );
    await manager.updateWorkspace(allowConcurrent: false, activeTabId: 'first');
    expect(first.snapshots.value.phase, PlaybackPhase.paused);
    await manager.updateWorkspace(allowConcurrent: true, activeTabId: 'first');
    expect(first.snapshots.value.phase, PlaybackPhase.paused);
    expect(second.snapshots.value.phase, PlaybackPhase.playing);
  });

  test('single page blocks late resolution and keeps one source behind ordinary pages', () async {
    final repository = _FakeRepository();
    final manager = _manager(repository: repository);
    addTearDown(manager.close);
    final first = manager.acquire('first');
    await manager.updateWorkspace(allowConcurrent: false, activeTabId: 'first');
    final firstOpen = first.open(_detail('1'), _part('1'));
    await _flush();
    final second = manager.acquire('second');
    await manager.updateWorkspace(
      allowConcurrent: false,
      activeTabId: 'second',
    );
    final secondOpen = second.open(_detail('2'), _part('2'));
    await _flush();
    repository.pendingResolves['2']!.complete(
      _media('2', 80, const Duration(minutes: 2)),
    );
    await secondOpen;
    repository.pendingResolves['1']!.complete(
      _media('1', 80, const Duration(minutes: 2)),
    );
    await firstOpen;
    expect((first.engine as _FakeEngine).playCount, 0);
    expect(first.snapshots.value.phase, PlaybackPhase.paused);
    expect(second.snapshots.value.phase, PlaybackPhase.playing);
    await manager.updateWorkspace(
      allowConcurrent: false,
      activeTabId: 'settings',
    );
    expect(first.snapshots.value.phase, PlaybackPhase.paused);
    expect(second.snapshots.value.phase, PlaybackPhase.playing);
  });

  test('single page waits for an outgoing native pause and rejects a stale selection', () async {
    final manager = _manager();
    addTearDown(manager.close);
    final first = manager.acquire('first');
    await first.open(_detail('1'), _part('1'));
    final second = manager.acquire('second');
    await second.open(_detail('2'), _part('2'));
    await second.pause();
    final third = manager.acquire('third');
    await third.open(_detail('3'), _part('3'));
    await third.pause();
    final engine = first.engine as _FakeEngine;
    final pause = Completer<void>();
    engine.nextPause = pause;
    final selectSecond = manager.updateWorkspace(
      allowConcurrent: false,
      activeTabId: 'second',
    );
    await _flush();
    final secondPlayCount = (second.engine as _FakeEngine).playCount;
    final selectThird = manager.updateWorkspace(
      allowConcurrent: false,
      activeTabId: 'third',
    );
    // Preserve play intent while permission is blocked.
    await second.togglePlaying();
    await third.togglePlaying();
    expect((second.engine as _FakeEngine).playCount, secondPlayCount);
    expect(third.snapshots.value.phase, PlaybackPhase.paused);
    pause.complete();
    await Future.wait([selectSecond, selectThird]);
    expect(first.snapshots.value.phase, PlaybackPhase.paused);
    expect(second.snapshots.value.phase, PlaybackPhase.paused);
    expect(third.snapshots.value.phase, PlaybackPhase.playing);
  });

  test(
    'account stop cancels every pending source and close disposes every engine',
    () async {
      final repository = _FakeRepository();
      final manager = _manager(repository: repository);
      final first = manager.acquire('first');
      final second = manager.acquire('second');
      final opens = [
        first.open(_detail('1'), _part('1')),
        second.open(_detail('2'), _part('2')),
      ];
      await _flush();
      await manager.stop();
      for (final id in ['1', '2']) {
        repository.pendingResolves[id]!.complete(
          _media(id, 80, const Duration(minutes: 2)),
        );
      }
      await Future.wait(opens);
      expect(first.media, isNull);
      expect(second.media, isNull);
      expect((first.engine as _FakeEngine).playCount, 0);
      expect((second.engine as _FakeEngine).playCount, 0);
      await manager.close();
      expect((first.engine as _FakeEngine).disposed, isTrue);
      expect((second.engine as _FakeEngine).disposed, isTrue);
    },
  );

  for (final (local, remote, remember, scope, expected)
      in <(Duration?, Duration?, bool, String, Duration)>[
        (
          const Duration(seconds: 8),
          const Duration(seconds: 42),
          true,
          'user:1',
          const Duration(seconds: 8),
        ),
        (
          Duration.zero,
          const Duration(seconds: 42),
          true,
          'user:1',
          Duration.zero,
        ),
        (
          null,
          const Duration(milliseconds: 42678),
          true,
          'user:1',
          const Duration(milliseconds: 42678),
        ),
        (null, null, true, 'user:1', Duration.zero),
        (null, const Duration(seconds: 118), true, 'user:1', Duration.zero),
        (null, const Duration(seconds: 42), false, 'user:1', Duration.zero),
        (null, const Duration(seconds: 42), true, 'guest', Duration.zero),
      ]) {
    test(
      'resume precedence: local=$local remote=$remote remember=$remember scope=$scope',
      () async {
        final engine = _FakeEngine();
        final history = _FakeHistory()..readValue = remote;
        final progress = _FakeProgress()..readValue = local;
        final session = PlaybackSession(
          engine: engine,
          repository: _FakeRepository(autoResolve: true),
          progress: progress,
          historyRepository: history,
          accountScope: () => scope,
        );
        addTearDown(session.close);
        session.configureSettings(AppSettings(resumePlayback: remember));
        await session.open(_detail('11'), _part('11'));
        await _flush();
        expect(engine.openOptions.single.startPosition, local ?? Duration.zero);
        expect(engine.currentSnapshot.position, expected);
        expect(
          history.reads.length,
          local == null && remember && scope == 'user:1' ? 1 : 0,
        );
        if (scope == 'guest') expect(history.reports, isEmpty);
      },
    );
  }

  test(
    'cloud read failure starts at zero without failing media preparation',
    () async {
      final engine = _FakeEngine();
      final history = _FakeHistory()
        ..readFailure = const AppFailure(AppFailureKind.network, 'offline');
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        progress: _FakeProgress()..readValue = null,
        historyRepository: history,
        accountScope: () => 'user:1',
      );
      addTearDown(session.close);
      await session.open(_detail('11'), _part('11'));
      expect(engine.openOptions.single.startPosition, Duration.zero);
      expect(session.media, isNotNull);
      expect(session.error, isNull);
      expect(session.auxiliaryMessage, '云端进度读取失败，本次从头播放');
    },
  );

  test('old cloud progress cannot open a replacement part', () async {
    final engine = _FakeEngine();
    final history = _FakeHistory()..nextRead = Completer<Duration?>();
    final gate = history.nextRead!;
    final session = PlaybackSession(
      engine: engine,
      repository: _FakeRepository(autoResolve: true),
      progress: _FakeProgress()..readValue = null,
      historyRepository: history,
      accountScope: () => 'user:1',
    );
    addTearDown(session.close);
    final old = session.open(_detail('11'), _part('11'));
    await _flush();
    await session.open(_detail('12'), _part('12'));
    expect(history.reads.first.cancellation.isCancelled, isTrue);
    gate.complete(const Duration(seconds: 55));
    await old;
    await _flush();
    expect(engine.openOptions, hasLength(2));
    expect(engine.openOptions.last.startPosition, Duration.zero);
    expect(engine.seekTargets, isEmpty);
    expect(session.part?.cid, '12');
  });

  test(
    'same account with a new session epoch rejects late cloud progress',
    () async {
      var epoch = 1;
      final engine = _FakeEngine();
      final history = _FakeHistory()..nextRead = Completer<Duration?>();
      final gate = history.nextRead!;
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        progress: _FakeProgress()..readValue = null,
        historyRepository: history,
        accountScope: () => 'user:1',
        sessionEpoch: () => epoch,
      );
      addTearDown(session.close);
      final opening = session.open(_detail('11'), _part('11'));
      await _flush();
      epoch++;
      gate.complete(const Duration(seconds: 55));
      await opening;
      await _flush();
      expect(engine.openOptions, hasLength(1));
      expect(engine.seekTargets, isEmpty);
      expect(history.reports, isEmpty);
    },
  );

  test(
    'media starts while cloud progress is pending without saving zero',
    () async {
      final engine = _FakeEngine();
      final history = _FakeHistory()..nextRead = Completer<Duration?>();
      final gate = history.nextRead!;
      final progress = _FakeProgress()..readValue = null;
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        progress: progress,
        historyRepository: history,
        accountScope: () => 'user:1',
      );
      addTearDown(session.close);
      await session
          .open(_detail('11'), _part('11'))
          .timeout(const Duration(seconds: 1));
      expect(session.isResolving, isFalse);
      expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
      expect(engine.currentSnapshot.position, Duration.zero);
      expect(history.reports, isEmpty);
      await session.pause();
      expect(progress.writes, isEmpty);
      gate.complete(const Duration(seconds: 42));
      await _flush();
      expect(engine.seekTargets, [const Duration(seconds: 42)]);
      expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
      expect(engine.currentSnapshot.desiredPlaying, isFalse);
      expect(history.reports.first.position, const Duration(seconds: 42));
      expect(progress.writes, isNotEmpty);
    },
  );

  test(
    'early cloud response waits for the native source to be ready',
    () async {
      final engine = _FakeEngine()..nextOpen = Completer<void>();
      final nativeReady = engine.nextOpen!;
      final history = _FakeHistory()..readValue = const Duration(seconds: 42);
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        progress: _FakeProgress()..readValue = null,
        historyRepository: history,
        accountScope: () => 'user:1',
      );
      addTearDown(session.close);
      final opening = session.open(_detail('11'), _part('11'));
      await _flush();
      expect(history.reads, hasLength(1));
      expect(engine.seekTargets, isEmpty);
      nativeReady.complete();
      await opening;
      await _flush();
      expect(engine.seekTargets, [const Duration(seconds: 42)]);
      expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
    },
  );

  test(
    'closing during native preparation rejects an early cloud response',
    () async {
      final engine = _FakeEngine()..nextOpen = Completer<void>();
      final nativeReady = engine.nextOpen!;
      final history = _FakeHistory()..readValue = const Duration(seconds: 42);
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        progress: _FakeProgress()..readValue = null,
        historyRepository: history,
        accountScope: () => 'user:1',
      );
      final opening = session.open(_detail('11'), _part('11'));
      await _flush();
      await session.close();
      nativeReady.complete();
      await opening;
      await _flush();
      expect(engine.disposed, isTrue);
      expect(engine.seekTargets, isEmpty);
      expect(history.reports, isEmpty);
    },
  );

  test(
    'a cloud read failure after closing cannot notify a disposed session',
    () async {
      final engine = _FakeEngine();
      final history = _FakeHistory()..nextRead = Completer<Duration?>();
      final gate = history.nextRead!;
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        progress: _FakeProgress()..readValue = null,
        historyRepository: history,
        accountScope: () => 'user:1',
      );
      await session.open(_detail('11'), _part('11'));
      await session.close();
      gate.completeError(
        const AppFailure(AppFailureKind.network, 'late failure'),
      );
      await _flush();
      expect(session.auxiliaryMessage, isNull);
      expect(engine.seekTargets, isEmpty);
      expect(history.reports, isEmpty);
    },
  );

  for (final action in ['seek', 'stop', 'close', 'disable', 'account']) {
    test('late cloud progress is discarded after $action', () async {
      var scope = 'user:1';
      final engine = _FakeEngine();
      final history = _FakeHistory()..nextRead = Completer<Duration?>();
      final gate = history.nextRead!;
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        progress: _FakeProgress()..readValue = null,
        historyRepository: history,
        accountScope: () => scope,
      );
      addTearDown(session.close);
      await session.open(_detail('11'), _part('11'));
      switch (action) {
        case 'seek':
          await session.seek(const Duration(seconds: 10));
        case 'stop':
          await session.stop();
        case 'close':
          await session.close();
        case 'disable':
          session.configureSettings(AppSettings(resumePlayback: false));
          session.configureSettings(AppSettings(resumePlayback: true));
        case 'account':
          scope = 'user:2';
      }
      if (action != 'account') {
        expect(history.reads.single.cancellation.isCancelled, isTrue);
      }
      gate.complete(const Duration(seconds: 42));
      await _flush();
      expect(
        engine.seekTargets,
        action == 'seek' ? [const Duration(seconds: 10)] : isEmpty,
      );
      expect(session.error, isNull);
      if (action == 'stop' || action == 'close' || action == 'account') {
        expect(history.reports, isEmpty);
      }
    });
  }

  test(
    'manual seek during a local progress read prevents a cloud resume',
    () async {
      final engine = _FakeEngine();
      final progress = _FakeProgress()..nextRead = Completer<Duration?>();
      final gate = progress.nextRead!;
      final history = _FakeHistory()..readValue = const Duration(seconds: 42);
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        progress: progress,
        historyRepository: history,
        accountScope: () => 'user:1',
      );
      addTearDown(session.close);
      final opening = session.open(_detail('11'), _part('11'));
      await _flush();
      await session.seek(const Duration(seconds: 10));
      gate.complete(null);
      await opening;
      await _flush();
      expect(history.reads, isEmpty);
      expect(engine.seekTargets, [const Duration(seconds: 10)]);
    },
  );

  for (final remote in [
    Duration.zero,
    const Duration(seconds: -1),
    const Duration(seconds: 118),
    const Duration(seconds: 5),
  ]) {
    test(
      'cloud resume does not rewind or restore an invalid position: $remote',
      () async {
        final engine = _FakeEngine();
        final history = _FakeHistory()..nextRead = Completer<Duration?>();
        final gate = history.nextRead!;
        final session = PlaybackSession(
          engine: engine,
          repository: _FakeRepository(autoResolve: true),
          progress: _FakeProgress()..readValue = null,
          historyRepository: history,
          accountScope: () => 'user:1',
        );
        addTearDown(session.close);
        await session.open(_detail('11'), _part('11'));
        engine.emit(
          engine.currentSnapshot.copyWith(
            position: const Duration(seconds: 10),
          ),
        );
        gate.complete(remote);
        await _flush();
        expect(engine.seekTargets, isEmpty);
        expect(engine.currentSnapshot.position, const Duration(seconds: 10));
        expect(history.reports.last.position, const Duration(seconds: 10));
      },
    );
  }

  test(
    'a failed native open releases an early cloud response without seeking',
    () async {
      final engine = _FakeEngine()..nextOpen = Completer<void>();
      final nativeReady = engine.nextOpen!;
      final history = _FakeHistory()..readValue = const Duration(seconds: 42);
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        progress: _FakeProgress()..readValue = null,
        historyRepository: history,
        accountScope: () => 'user:1',
      );
      addTearDown(session.close);
      final opening = session.open(_detail('11'), _part('11'));
      await _flush();
      nativeReady.completeError(
        const PlayerFailure(
          PlayerFailureKind.nativePlayback,
          'native failure',
          1,
        ),
      );
      await opening;
      await _flush();
      expect(engine.seekTargets, isEmpty);
      expect(history.reports, isEmpty);
      expect(session.error, 'native failure');
    },
  );

  test(
    'reports every 15 seconds and flushes backward seek, pause and completion',
    () async {
      var now = Duration.zero;
      final engine = _FakeEngine();
      final history = _FakeHistory();
      final progress = _FakeProgress();
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        progress: progress,
        historyRepository: history,
        accountScope: () => 'user:1',
        historyNow: () => now,
      );
      addTearDown(session.close);
      session.configureSettings(AppSettings(resumePlayback: false));
      await session.open(_detail('11'), _part('11'));
      await _flush();
      for (final seconds in [5, 10, 14]) {
        now = Duration(seconds: seconds);
        engine.emit(engine.currentSnapshot.copyWith(position: now));
        await _flush();
      }
      expect(history.reports, hasLength(1));
      now = const Duration(seconds: 15);
      engine.emit(engine.currentSnapshot.copyWith(position: now));
      await _flush();
      expect(history.reports.last.position, now);
      expect(history.reports, hasLength(2));
      await session.seek(const Duration(seconds: 3));
      await _flush();
      expect(history.reports.last.position, const Duration(seconds: 3));
      engine.emit(
        engine.currentSnapshot.copyWith(position: const Duration(seconds: 4)),
      );
      await session.pause();
      await _flush();
      expect(history.reports.last.position, const Duration(seconds: 4));
      engine.emit(
        engine.currentSnapshot.copyWith(
          position: const Duration(seconds: 120),
          phase: PlaybackPhase.ended,
        ),
      );
      await _flush();
      expect(history.reports.last.completed, isTrue);
      expect(progress.writes, isNotEmpty);
    },
  );

  test(
    'switch, stop and PGC preserve the captured old progress identity',
    () async {
      final engine = _FakeEngine();
      final history = _FakeHistory();
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        contentRepository: _FakeContentRepository(),
        progress: _FakeProgress(),
        historyRepository: history,
        accountScope: () => 'user:1',
      );
      addTearDown(session.close);
      await session.open(_detail('11'), _part('11'));
      engine.emit(
        engine.currentSnapshot.copyWith(position: const Duration(seconds: 9)),
      );
      await session.open(
        _detail('12'),
        _part('12'),
        target: const PgcPlaybackTarget('7', cid: '12', seasonId: '8'),
      );
      await _flush();
      expect(
        history.reports.any(
          (r) => r.target.cid == '11' && r.position.inSeconds == 9,
        ),
        isTrue,
      );
      engine.emit(
        engine.currentSnapshot.copyWith(position: const Duration(seconds: 11)),
      );
      await session.stop();
      await _flush();
      expect(history.reports.last.target.episodeId, '7');
      expect(history.reports.last.target.seasonId, '8');
      expect(history.reports.last.position.inSeconds, 11);
    },
  );

  test('optional timeline failures preserve ready media and do not immediately repeat on hover', () async {
    final metadata = _FakeMetadataRepository();
    final session = PlaybackSession(
      engine: _FakeEngine(),
      repository: _FakeRepository(autoResolve: true),
      metadataRepository: metadata,
      progress: _FakeProgress(),
      accountScope: () => 'guest',
    );
    addTearDown(session.close);
    await session.open(_detail('one'), _part('one'));
    metadata.metadataPending['one']?.completeError(
      const AppFailure(AppFailureKind.network, 'metadata unavailable'),
    );
    await _flush();
    expect(session.media, isNotNull);
    expect(session.error, isNull);
    expect(session.chapters, isEmpty);
    final pending = session.ensureStoryboard();
    metadata.storyboardPending['one']?.completeError(
      const AppFailure(AppFailureKind.timeout, 'preview unavailable'),
    );
    await pending;
    expect(session.storyboardLoading, isFalse);
    expect(session.storyboardMessage, '缩略图暂时不可用');
    expect(session.error, isNull);
    final firstRequest = metadata.storyboardPending['one'];
    await session.ensureStoryboard();
    expect(metadata.storyboardPending['one'], same(firstRequest));
  });

  for (final kind in [AppFailureKind.network, AppFailureKind.timeout]) {
    test('storyboard $kind recovers on hover after cooldown', () async {
      var now = Duration.zero;
      final engine = _FakeEngine();
      final metadata = _FakeMetadataRepository();
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        metadataRepository: metadata,
        progress: _FakeProgress(),
        accountScope: () => 'guest',
        storyboardNow: () => now,
      );
      addTearDown(session.close);
      await session.open(_detail('one'), _part('one'));
      final first = session.ensureStoryboard();
      metadata.storyboardPending['one']?.completeError(
        AppFailure(kind, 'preview unavailable'),
      );
      await first;
      expect(session.storyboardMessage, '缩略图暂时不可用');
      expect(session.media, isNotNull);
      expect(session.error, isNull);

      now = const Duration(milliseconds: 4999);
      await session.ensureStoryboard();
      expect(metadata.storyboardCalls, ['one']);
      now = const Duration(seconds: 5);
      final retry = session.ensureStoryboard();
      expect(metadata.storyboardCalls, ['one', 'one']);
      expect(session.storyboardLoading, isTrue);
      expect(session.storyboardMessage, isNull);
      now = const Duration(minutes: 1);
      await session.ensureStoryboard();
      expect(metadata.storyboardCalls, hasLength(2));
      metadata.storyboardPending['one']?.complete(_storyboard);
      await retry;
      expect(session.storyboard, same(_storyboard));
      expect(session.storyboardLoading, isFalse);
      await session.ensureStoryboard();
      expect(metadata.storyboardCalls, hasLength(2));
      expect(engine.seekTargets, isEmpty);
    });
  }

  test(
    'storyboard retries back off and stop after three logical reads',
    () async {
      var now = Duration.zero;
      final metadata = _FakeMetadataRepository();
      final session = PlaybackSession(
        engine: _FakeEngine(),
        repository: _FakeRepository(autoResolve: true),
        metadataRepository: metadata,
        progress: _FakeProgress(),
        accountScope: () => 'guest',
        storyboardNow: () => now,
      );
      addTearDown(session.close);
      await session.open(_detail('one'), _part('one'));
      for (var attempt = 0; attempt < 3; attempt++) {
        final pending = session.ensureStoryboard();
        expect(metadata.storyboardCalls, hasLength(attempt + 1));
        metadata.storyboardPending['one']?.completeError(
          const AppFailure(AppFailureKind.timeout, 'preview unavailable'),
        );
        await pending;
        now +=
            Duration(seconds: 5 * (attempt + 1)) -
            const Duration(milliseconds: 1);
        await session.ensureStoryboard();
        expect(metadata.storyboardCalls, hasLength(attempt + 1));
        now += const Duration(milliseconds: 1);
      }
      now += const Duration(hours: 1);
      await session.ensureStoryboard();
      expect(metadata.storyboardCalls, hasLength(3));
      expect(session.storyboardLoading, isFalse);
      expect(session.error, isNull);
    },
  );

  for (final kind in [
    null,
    AppFailureKind.authentication,
    AppFailureKind.permission,
    AppFailureKind.rateLimited,
    AppFailureKind.notFound,
    AppFailureKind.protocol,
  ]) {
    test('storyboard empty result or $kind does not retry on hover', () async {
      var now = Duration.zero;
      final metadata = _FakeMetadataRepository();
      final session = PlaybackSession(
        engine: _FakeEngine(),
        repository: _FakeRepository(autoResolve: true),
        metadataRepository: metadata,
        progress: _FakeProgress(),
        accountScope: () => 'guest',
        storyboardNow: () => now,
      );
      addTearDown(session.close);
      await session.open(_detail('one'), _part('one'));
      final pending = session.ensureStoryboard();
      if (kind == null) {
        metadata.storyboardPending['one']?.complete(null);
      } else {
        metadata.storyboardPending['one']?.completeError(
          AppFailure(kind, 'preview unavailable'),
        );
      }
      await pending;
      now = const Duration(hours: 1);
      await session.ensureStoryboard();
      expect(metadata.storyboardCalls, ['one']);
      expect(session.storyboard, isNull);
      expect(session.storyboardLoading, isFalse);
      expect(session.error, isNull);
    });
  }

  test(
    'source changes reset storyboard retries and reject late retry failures',
    () async {
      var now = Duration.zero;
      final metadata = _FakeMetadataRepository();
      final session = PlaybackSession(
        engine: _FakeEngine(),
        repository: _FakeRepository(autoResolve: true),
        metadataRepository: metadata,
        progress: _FakeProgress(),
        accountScope: () => 'guest',
        storyboardNow: () => now,
      );
      addTearDown(session.close);
      await session.open(_detail('one'), _part('one'));
      final first = session.ensureStoryboard();
      metadata.storyboardPending['one']?.completeError(
        const AppFailure(AppFailureKind.timeout, 'preview unavailable'),
      );
      await first;
      now = const Duration(seconds: 5);
      final oldRetry = session.ensureStoryboard();
      await session.open(_detail('two'), _part('two'));
      expect(metadata.storyboardTokens['one']?.isCancelled, isTrue);
      final newRequest = session.ensureStoryboard();
      metadata.storyboardPending['one']?.completeError(
        const AppFailure(AppFailureKind.timeout, 'late preview failure'),
      );
      await oldRetry;
      expect(session.storyboardLoading, isTrue);
      expect(session.storyboardMessage, isNull);
      metadata.storyboardPending['two']?.completeError(
        const AppFailure(AppFailureKind.network, 'preview unavailable'),
      );
      await newRequest;
      now = const Duration(seconds: 10);
      final newRetry = session.ensureStoryboard();
      expect(metadata.storyboardCalls, ['one', 'one', 'two', 'two']);
      metadata.storyboardPending['two']?.complete(_storyboard);
      await newRetry;
      expect(session.storyboard, same(_storyboard));
      expect(session.storyboardMessage, isNull);
    },
  );

  test(
    'storyboard cooldown cannot start reads after account epoch changes',
    () async {
      var now = Duration.zero;
      var epoch = 0;
      final metadata = _FakeMetadataRepository();
      final session = PlaybackSession(
        engine: _FakeEngine(),
        repository: _FakeRepository(autoResolve: true),
        metadataRepository: metadata,
        progress: _FakeProgress(),
        accountScope: () => 'account',
        sessionEpoch: () => epoch,
        storyboardNow: () => now,
      );
      addTearDown(session.close);
      await session.open(_detail('one'), _part('one'));
      final pending = session.ensureStoryboard();
      metadata.storyboardPending['one']?.completeError(
        const AppFailure(AppFailureKind.timeout, 'preview unavailable'),
      );
      await pending;
      epoch++;
      now = const Duration(seconds: 5);
      await session.ensureStoryboard();
      expect(metadata.storyboardCalls, ['one']);
    },
  );

  test(
    'timeline loads metadata once and lazily loads storyboard without seek',
    () async {
      final metadata = _FakeMetadataRepository();
      final engine = _FakeEngine();
      final repository = _FakeRepository(autoResolve: true);
      final session = PlaybackSession(
        engine: engine,
        repository: repository,
        metadataRepository: metadata,
        progress: _FakeProgress(),
        accountScope: () => 'guest',
      );
      addTearDown(session.close);
      await session.open(_detail('one'), _part('one'));
      metadata.metadataPending['one']?.complete(_timelineMetadata);
      await _flush();
      expect(repository.pendingSubtitles, isEmpty);
      expect(session.chapters.single.title, 'Chapter one');
      expect(metadata.storyboardPending, isEmpty);
      final pending = session.ensureStoryboard();
      await session.ensureStoryboard();
      expect(metadata.storyboardPending, hasLength(1));
      expect(session.storyboardLoading, isTrue);
      metadata.storyboardPending['one']?.complete(_storyboard);
      await pending;
      expect(session.storyboard, same(_storyboard));
      expect(session.storyboardLoading, isFalse);
      expect(engine.seekTargets, isEmpty);
    },
  );

  test(
    'old chapter and storyboard responses cannot change a new source',
    () async {
      final metadata = _FakeMetadataRepository();
      final session = PlaybackSession(
        engine: _FakeEngine(),
        repository: _FakeRepository(autoResolve: true),
        metadataRepository: metadata,
        progress: _FakeProgress(),
        accountScope: () => 'guest',
      );
      addTearDown(session.close);
      await session.open(_detail('one'), _part('one'));
      final oldShot = session.ensureStoryboard();
      await session.open(_detail('two'), _part('two'));
      expect(metadata.storyboardTokens['one']?.isCancelled, isTrue);
      metadata.metadataPending['one']?.complete(_timelineMetadata);
      metadata.storyboardPending['one']?.complete(_storyboard);
      await oldShot;
      await _flush();
      expect(session.chapters, isEmpty);
      expect(session.storyboard, isNull);
      metadata.metadataPending['two']?.complete(_timelineMetadata);
      await _flush();
      expect(session.chapters, hasLength(1));
      final newShot = session.ensureStoryboard();
      await session.stop();
      expect(metadata.storyboardTokens['two']?.isCancelled, isTrue);
      metadata.storyboardPending['two']?.complete(_storyboard);
      await newShot;
      expect(session.chapters, isEmpty);
      expect(session.storyboard, isNull);
    },
  );

  test('timeline rejects responses after account scope changes', () async {
    var scope = 'guest';
    final metadata = _FakeMetadataRepository();
    final session = PlaybackSession(
      engine: _FakeEngine(),
      repository: _FakeRepository(autoResolve: true),
      metadataRepository: metadata,
      progress: _FakeProgress(),
      accountScope: () => scope,
    );
    addTearDown(session.close);
    await session.open(_detail('one'), _part('one'));
    final pending = session.ensureStoryboard();
    scope = 'account-two';
    metadata.metadataPending['one']?.complete(_timelineMetadata);
    metadata.storyboardPending['one']?.complete(_storyboard);
    await pending;
    await _flush();
    expect(session.chapters, isEmpty);
    expect(session.storyboard, isNull);
  });

  for (final target in const [
    PgcPlaybackTarget('7'),
    LivePlaybackTarget('8'),
  ]) {
    test(
      'content target ${target.key} receives the configured decoder',
      () async {
        final engine = _FakeEngine();
        final content = _FakeContentRepository();
        final session = PlaybackSession(
          engine: engine,
          repository: _FakeRepository(),
          contentRepository: content,
          progress: _FakeProgress(),
          accountScope: () => 'guest',
        );
        addTearDown(session.close);
        session.configureSettings(
          AppSettings(
            preferredVideoCodec: VideoCodecPreference.av1,
            videoDecoding: VideoDecodingPreference.software,
          ),
        );
        await session.open(null, null, target: target);
        expect(content.codecs, [VideoCodecPreference.av1]);
        expect(
          engine.openOptions.single.maxBufferAhead,
          const Duration(minutes: 5),
        );
        expect(
          engine.openOptions.single.videoDecoding,
          VideoDecodingMode.software,
        );
      },
    );
  }

  test(
    'codec and decoder settings stay consistent within a source generation',
    () async {
      final engine = _FakeEngine();
      final repository = _FakeRepository();
      final session = PlaybackSession(
        engine: engine,
        repository: repository,
        progress: _FakeProgress(),
        accountScope: () => 'guest',
      );
      addTearDown(session.close);
      session.configureSettings(
        AppSettings(
          preferredVideoCodec: VideoCodecPreference.hevc,
          videoDecoding: VideoDecodingPreference.software,
        ),
      );
      final opening = session.open(_detail('codec'), _part('codec'));
      await _flush();
      expect(repository.codecs, [VideoCodecPreference.hevc]);
      session.configureSettings(
        AppSettings(preferredVideoCodec: VideoCodecPreference.av1),
      );
      repository.completeResolve('codec');
      await opening;
      expect(engine.openOptions.last.videoDecoding, VideoDecodingMode.software);
      final generation = session.sourceGeneration;
      await session.pause();
      await session.seek(const Duration(seconds: 25));
      await session.setRate(1.5);
      await session.setVolume(35);
      final retry = session.retry();
      await _flush();
      repository.completeResolve('codec');
      await retry;
      expect(session.sourceGeneration, greaterThan(generation));
      expect(repository.codecs.last, VideoCodecPreference.av1);
      expect(
        engine.openOptions.last.videoDecoding,
        VideoDecodingMode.automatic,
      );
      expect(engine.currentSnapshot.position, const Duration(seconds: 25));
      expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
      expect(engine.currentSnapshot.rate, 1.5);
      expect(engine.currentSnapshot.volume, 35);
    },
  );

  test(
    'PGC target cid renders without a UGC detail and preserves filters',
    () async {
      final engine = _FakeEngine();
      final repository = _FakeRepository();
      final session = PlaybackSession(
        engine: engine,
        repository: repository,
        contentRepository: _FakeContentRepository(),
        progress: _FakeProgress(),
        accountScope: () => 'guest',
      );
      session.configureSettings(
        AppSettings(
          autoPlay: false,
          danmakuBlockedWords: ['blocked'],
          danmakuTopEnabled: false,
          danmakuMaxPerSecond: 1,
        ),
      );
      await session.open(
        null,
        null,
        target: const PgcPlaybackTarget('7', cid: '101'),
      );
      expect(repository.pendingComments.keys, ['101:1']);
      repository.pendingComments['101:1']!.complete([
        for (final (id, text, mode, second) in const [
          ('blocked', 'blocked text', 1, 1),
          ('top', 'top', 5, 1),
          ('scroll', 'scroll', 1, 1),
          ('density', 'density', 1, 1),
          ('bottom', 'bottom', 4, 2),
        ])
          TimedComment(
            id: id,
            position: Duration(seconds: second),
            text: text,
            mode: mode,
            color: 0xffffff,
            fontSize: 24,
          ),
      ]);
      await _flush();
      session.danmaku.setViewport(width: 800, height: 450);
      await session.seek(const Duration(seconds: 2));
      expect(session.danmaku.frame().map((item) => item.event.id).toSet(), {
        'scroll',
        'bottom',
      });
      await session.close();
    },
  );

  test(
    'fast playback keeps visible comments across media window refreshes',
    () async {
      var now = Duration.zero;
      final engine = _FakeEngine();
      final repository = _FakeRepository(autoResolve: true);
      final session = PlaybackSession(
        engine: engine,
        repository: repository,
        progress: _FakeProgress(),
        accountScope: () => 'guest',
        danmakuNow: () => now,
      );
      addTearDown(session.close);
      await session.open(_detail('one'), _part('one'));
      repository.pendingComments['one:1']!.complete([
        _comment('ongoing', 10),
        _comment('future', 31),
      ]);
      await _flush();
      session.danmaku.setViewport(width: 800, height: 450);
      await session.pause();
      await session.setRate(3);
      await session.togglePlaying();
      session.danmaku.frame();
      for (var halfSecond = 1; halfSecond <= 20; halfSecond++) {
        now = Duration(milliseconds: halfSecond * 500);
        engine.emit(
          engine.currentSnapshot.copyWith(
            position: Duration(milliseconds: halfSecond * 1500),
          ),
        );
        await _flush();
        final frame = session.danmaku.frame();
        expect(
          frame.map((p) => p.event.id),
          halfSecond < 7 ? <String>[] : ['ongoing'],
        );
      }
      expect(session.danmaku.pendingCount, 1);
      await session.pause();
      await session.seek(const Duration(seconds: 30));
      expect(session.danmaku.frame().single.event.id, 'ongoing');
      expect(repository.pendingComments.keys, ['one:1']);
    },
  );

  test('PGC seek and episode switches cancel old comment windows', () async {
    final engine = _FakeEngine();
    final repository = _FakeRepository();
    final session = PlaybackSession(
      engine: engine,
      repository: repository,
      contentRepository: _FakeContentRepository(
        duration: const Duration(minutes: 20),
      ),
      progress: _FakeProgress(),
      accountScope: () => 'guest',
    );
    await session.open(
      null,
      null,
      target: const PgcPlaybackTarget('7', cid: '101'),
    );
    final oldSegment = repository.pendingComments['101:1']!;
    final oldSegmentToken = repository.commentCancellations['101:1']!;
    await session.seek(const Duration(minutes: 12));
    expect(oldSegmentToken.isCancelled, isTrue);
    expect(repository.pendingComments.keys, containsAll(['101:3', '101:4']));
    oldSegment.complete([_comment('old-seek', 720)]);
    await _flush();
    expect(session.danmaku.pendingCount, 0);
    final oldEpisode = repository.pendingComments['101:3']!;
    final oldEpisodeToken = repository.commentCancellations['101:3']!;
    await session.open(
      null,
      null,
      target: const PgcPlaybackTarget('8', cid: '102'),
    );
    expect(oldEpisodeToken.isCancelled, isTrue);
    oldEpisode.complete([_comment('old-episode', 0)]);
    repository.pendingComments['102:1']!.complete([_comment('new-episode', 0)]);
    await _flush();
    session.danmaku.setViewport(width: 800, height: 450);
    expect(session.danmaku.frame().map((item) => item.event.id), [
      'new-episode',
    ]);
    expect(session.danmakuCid, '102');
    await session.close();
  });

  test(
    'video, PGC and live share one engine and preserve their own intent',
    () async {
      final engine = _FakeEngine();
      final content = _FakeContentRepository();
      final progress = _FakeProgress();
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        contentRepository: content,
        progress: progress,
        accountScope: () => 'guest',
      );
      final videoOwner = Object(), liveOwner = Object(), pgcOwner = Object();
      for (final owner in [videoOwner, liveOwner, pgcOwner]) {
        session.attach(owner);
      }
      await session.activate(videoOwner, _detail('video'), _part('video'));
      await session.seek(const Duration(seconds: 19));
      await session.pause();
      await session.activate(
        pgcOwner,
        _detail('pgc'),
        _part('pgc'),
        target: const PgcPlaybackTarget('7'),
      );
      expect(content.targets.last, const PgcPlaybackTarget('7'));
      await session.seek(const Duration(seconds: 12));
      await session.pause();
      expect(progress.writes.last.episodeId, '7');
      await session.activate(
        pgcOwner,
        _detail('pgc-next'),
        _part('pgc-next'),
        target: const PgcPlaybackTarget('8'),
      );
      expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
      expect(engine.openOptions.last.startPosition, Duration.zero);
      await session.seek(const Duration(seconds: 12));
      await session.changeQuality(64);
      expect(content.targets.last, const PgcPlaybackTarget('8'));
      expect(
        engine.openOptions.last.startPosition,
        const Duration(seconds: 12),
      );
      await session.activate(
        liveOwner,
        null,
        null,
        target: const LivePlaybackTarget('42'),
        title: '直播测试',
      );
      expect(engine.sources.last, isA<ManifestSource>());
      expect((engine.sources.last as ManifestSource).isLive, isTrue);
      expect(content.qualities.last, 10000);
      expect(session.title, '直播测试');
      final seeks = engine.seekTargets.length, writes = progress.writes.length;
      await session.seek(const Duration(seconds: 9));
      await session.setRate(2);
      await session.beginTemporaryRate(3);
      expect(engine.seekTargets.length, seeks);
      expect(engine.currentSnapshot.rate, 1);
      expect(progress.writes.length, writes);
      await session.pause();
      await session.changeQuality(400);
      expect(content.qualities.last, 400);
      expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
      expect(engine.openOptions.last.startPosition, Duration.zero);
      await session.activate(videoOwner, _detail('video'), _part('video'));
      expect(
        engine.openOptions.last.startPosition,
        const Duration(seconds: 19),
      );
      expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
      await session.activate(
        liveOwner,
        null,
        null,
        target: const LivePlaybackTarget('42'),
      );
      expect(content.qualities.last, 400);
      expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
      expect(engine.maxSimultaneousPlayers, 1);
      final beforeRestart = engine.sources.length;
      final seeksBeforeRestart = engine.seekTargets.length;
      engine.emit(engine.currentSnapshot.copyWith(phase: PlaybackPhase.ended));
      await session.togglePlaying();
      expect(engine.sources.length, beforeRestart + 1);
      expect(engine.seekTargets.length, seeksBeforeRestart);
      expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
      await session.close();
    },
  );

  test(
    'late PGC resolution cannot replace live and stop cancels content requests',
    () async {
      final engine = _FakeEngine();
      final content = _FakeContentRepository();
      final gate = Completer<PlaybackMedia>();
      content.pending = gate;
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        contentRepository: content,
        progress: _FakeProgress(),
        accountScope: () => 'guest',
      );
      final first = session.open(
        null,
        null,
        target: const PgcPlaybackTarget('1'),
      );
      await _flush();
      final oldRequest = content.cancellations.first;
      await session.open(null, null, target: const LivePlaybackTarget('2'));
      gate.complete(_media('old', 80, const Duration(minutes: 2)));
      await first;
      expect(oldRequest.isCancelled, isTrue);
      expect(session.contentTarget, const LivePlaybackTarget('2'));
      expect(engine.sources.length, 1);
      await session.stop();
      expect(content.cancellations.last.isCancelled, isTrue);
      expect(session.contentTarget, isNull);
      await session.close();
    },
  );

  test(
    'temporary speed never becomes a checkpoint or refresh source rate',
    () async {
      final engine = _FakeEngine();
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        progress: _FakeProgress(),
        accountScope: () => 'guest',
      );
      final first = Object();
      final second = Object();
      session.attach(first);
      session.attach(second);
      await session.activate(first, _detail('one'), _part('one'));
      await session.setRate(1.5);
      await session.beginTemporaryRate(3);
      final oldGeneration = session.snapshots.value.generation;
      await session.retry();
      expect(session.snapshots.value.rate, 1.5);
      await session.endTemporaryRate(expectedGeneration: oldGeneration);
      expect(session.snapshots.value.rate, 1.5);
      await session.beginTemporaryRate(3);
      await session.activate(second, _detail('two'), _part('two'));
      expect(session.snapshots.value.rate, 1.5);
      await session.activate(first, _detail('one'), _part('one'));
      expect(session.snapshots.value.rate, 1.5);
      await session.beginTemporaryRate(3);
      await session.deactivate(first);
      expect(session.snapshots.value.rate, 1.5);
      await session.activate(first, _detail('one'), _part('one'));
      expect(session.snapshots.value.rate, 1.5);
      await session.close();
    },
  );

  test(
    'danmaku settings filter words, modes and density and can restore events',
    () async {
      final engine = _FakeEngine();
      final repository = _FakeRepository(autoResolve: true);
      final session = PlaybackSession(
        engine: engine,
        repository: repository,
        progress: _FakeProgress(),
        accountScope: () => 'guest',
      );
      session.configureSettings(
        AppSettings(
          autoPlay: false,
          danmakuBlockedWords: ['blocked'],
          danmakuTopEnabled: false,
          danmakuMaxPerSecond: 1,
        ),
      );
      final owner = Object();
      session.attach(owner);
      await session.activate(owner, _detail('one'), _part('one'));
      TimedComment comment(String id, String text, int mode, int second) =>
          TimedComment(
            id: id,
            position: Duration(seconds: second),
            text: text,
            mode: mode,
            color: 0xffffff,
            fontSize: 24,
          );
      repository.pendingComments['one:1']!.complete([
        comment('bad', 'blocked message', 1, 1),
        comment('top', 'top', 5, 1),
        comment('one', 'one', 1, 1),
        comment('two', 'two', 1, 1),
        comment('bottom', 'bottom', 4, 2),
      ]);
      await _flush();
      expect(session.danmaku.pendingCount, 2);
      session.configureSettings(AppSettings(autoPlay: false));
      expect(session.danmaku.pendingCount, 5);
      await session.close();
    },
  );

  test('color and weight filtering, unlimited density and offset apply without reopening media', () async {
    final engine = _FakeEngine();
    final repository = _FakeRepository(autoResolve: true);
    final session = PlaybackSession(
      engine: engine,
      repository: repository,
      progress: _FakeProgress(),
      accountScope: () => 'guest',
    );
    addTearDown(session.close);
    final settings = AppSettings(
      autoPlay: false,
      danmakuBlockColored: true,
      danmakuMinimumWeight: 5,
      danmakuOffset: const Duration(seconds: 2),
      danmakuMaxPerSecond: 0,
    );
    session.configureSettings(settings);
    final owner = Object();
    session.attach(owner);
    await session.activate(owner, _detail('one'), _part('one'));
    repository.pendingComments['one:1']!.complete([
      const TimedComment(
        id: 'color',
        position: Duration(seconds: 1),
        text: 'red',
        mode: 1,
        color: 0xff0000,
        fontSize: 24,
        weight: 10,
      ),
      const TimedComment(
        id: 'low',
        position: Duration(seconds: 1),
        text: 'low',
        mode: 1,
        color: 0xffffff,
        fontSize: 24,
        weight: 4,
      ),
      for (var i = 0; i < 25; i++)
        TimedComment(
          id: '$i',
          position: const Duration(seconds: 1),
          text: '$i',
          mode: 1,
          color: 0xffffff,
          fontSize: 24,
          weight: 5,
        ),
    ]);
    await _flush();
    session.danmaku.setViewport(width: 800, height: 450);
    expect(session.danmaku.pendingCount, 25);
    await session.seek(const Duration(seconds: 2));
    expect(session.danmaku.frame(), isEmpty);
    await session.seek(const Duration(seconds: 3));
    expect(
      session.danmaku.frame().map((p) => p.event.id),
      isNot(contains('color')),
    );
    expect(
      session.danmaku.frame().map((p) => p.event.id),
      isNot(contains('low')),
    );
    session.configureSettings(
      settings.copyWith(
        danmakuBlockColored: false,
        danmakuMinimumWeight: 0,
        danmakuOffset: Duration.zero,
      ),
    );
    expect(session.danmaku.pendingCount, 27);
    expect(engine.openedUris, hasLength(1));
  });

  test('pause before deferred automatic skip prevents seek', () async {
    final engine = _FakeEngine();
    final sponsor = _FakeSponsor();
    final session = PlaybackSession(
      engine: engine,
      repository: _FakeRepository(autoResolve: true),
      progress: _FakeProgress(),
      accountScope: () => 'guest',
      sponsorRepository: sponsor,
    );
    session.configureSettings(
      AppSettings(sponsorBlockMode: SponsorBlockMode.automatic),
    );
    final owner = Object();
    session.attach(owner);
    await session.activate(owner, _detail('one'), _part('one'));
    sponsor.pending['one']!.complete([_sponsorSegment]);
    await _flush();
    engine.emit(
      engine.currentSnapshot.copyWith(position: const Duration(seconds: 11)),
    );
    await session.pause();
    await _flush();
    expect(engine.seekTargets, isEmpty);
    await session.close();
  });

  test(
    'automatic sponsor skip follows the playing owner on an ordinary tab',
    () async {
      final engine = _FakeEngine();
      final sponsor = _FakeSponsor();
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        progress: _FakeProgress(),
        accountScope: () => 'guest',
        sponsorRepository: sponsor,
      );
      session.configureSettings(
        AppSettings(sponsorBlockMode: SponsorBlockMode.automatic),
      );
      final owner = Object();
      session.attach(owner);
      await session.activate(owner, _detail('one'), _part('one'));
      sponsor.pending['one']!.complete([_sponsorSegment]);
      await _flush();
      await session.deactivate(owner);
      engine.emit(
        engine.currentSnapshot.copyWith(position: const Duration(seconds: 11)),
      );
      await _flush();
      expect(engine.seekTargets, [const Duration(seconds: 20)]);
      expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
      await session.close();
    },
  );

  test('explicit subtitle off survives quality change with default subtitles enabled', () async {
    final engine = _FakeEngine();
    final repository = _FakeRepository(autoResolve: true);
    final session = PlaybackSession(
      engine: engine,
      repository: repository,
      progress: _FakeProgress(),
      accountScope: () => 'guest',
    );
    session.configureSettings(AppSettings(subtitlesEnabled: true));
    final owner = Object();
    session.attach(owner);
    await session.activate(owner, _detail('one'), _part('one'));
    final tracks = [SubtitleTrack('中文', Uri.https('example.com', '/subtitle'))];
    repository.pendingSubtitles['one']!.complete(tracks);
    await _flush();
    expect(session.selectedSubtitle, 0);
    await session.selectSubtitle(-1);
    await session.changeQuality(64);
    repository.pendingSubtitles['one']!.complete(tracks);
    await _flush();
    expect(session.selectedSubtitle, -1);
    await session.close();
  });

  test('new owner uses configured playback defaults and disabled sponsor never requests', () async {
    final engine = _FakeEngine();
    final sponsor = _FakeSponsor();
    final session = PlaybackSession(
      engine: engine,
      repository: _FakeRepository(autoResolve: true),
      progress: _FakeProgress(),
      accountScope: () => 'guest',
      sponsorRepository: sponsor,
    );
    session.configureSettings(
      AppSettings(
        autoPlay: false,
        resumePlayback: false,
        preferredQuality: 64,
        defaultPlaybackRate: 1.5,
        defaultVolume: 35,
      ),
    );
    final owner = Object();
    session.attach(owner);
    await session.activate(owner, _detail('one'), _part('one'));
    expect(engine.openOptions.single.play, false);
    expect(engine.openOptions.single.rate, 1.5);
    expect(engine.openOptions.single.volume, 35);
    expect(
      engine.openOptions.single.maxBufferAhead,
      const Duration(minutes: 5),
    );
    expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
    expect(sponsor.pending, isEmpty);
    await session.close();
  });

  test(
    'automatic sponsor skip is once per source and manual seek back stays',
    () async {
      final engine = _FakeEngine();
      final sponsor = _FakeSponsor();
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        progress: _FakeProgress(),
        accountScope: () => 'guest',
        sponsorRepository: sponsor,
      );
      session.configureSettings(
        AppSettings(sponsorBlockMode: SponsorBlockMode.automatic),
      );
      final owner = Object();
      session.attach(owner);
      await session.activate(owner, _detail('one'), _part('one'));
      sponsor.pending['one']!.complete([_sponsorSegment]);
      await _flush();
      engine.emit(
        engine.currentSnapshot.copyWith(position: const Duration(seconds: 10)),
      );
      await _flush();
      expect(engine.seekTargets, [const Duration(seconds: 20)]);
      await session.seek(const Duration(seconds: 12));
      await _flush();
      expect(engine.seekTargets, [
        const Duration(seconds: 20),
        const Duration(seconds: 12),
      ]);
      await session.close();
    },
  );

  test('stale sponsor source response cannot seek new part; duration mismatch excluded', () async {
    final engine = _FakeEngine();
    final sponsor = _FakeSponsor();
    final session = PlaybackSession(
      engine: engine,
      repository: _FakeRepository(autoResolve: true),
      progress: _FakeProgress(),
      accountScope: () => 'guest',
      sponsorRepository: sponsor,
    );
    session.configureSettings(
      AppSettings(sponsorBlockMode: SponsorBlockMode.automatic),
    );
    final owner = Object();
    session.attach(owner);
    await session.activate(owner, _detail('one'), _part('one'));
    await session.activate(owner, _detail('two'), _part('two'));
    sponsor.pending['one']!.complete([_sponsorSegment]);
    sponsor.pending['two']!.complete([
      const SponsorSegment(
        id: 'bad',
        category: 'sponsor',
        start: Duration(seconds: 10),
        end: Duration(seconds: 20),
        videoDuration: Duration(seconds: 125),
      ),
    ]);
    await _flush();
    engine.emit(
      engine.currentSnapshot.copyWith(position: const Duration(seconds: 11)),
    );
    await _flush();
    expect(session.sponsorSegments, isEmpty);
    expect(engine.seekTargets, isEmpty);
    await session.close();
  });

  test('workspace owners preserve sub-five-second progress and playback preferences', () async {
    final engine = _FakeEngine(openDuration: const Duration(seconds: 3));
    final repository = _FakeRepository(autoResolve: true);
    final session = PlaybackSession(
      engine: engine,
      repository: repository,
      progress: _FakeProgress(),
      accountScope: () => 'guest',
    );
    final first = Object();
    final second = Object();
    session.attach(first);
    session.attach(second);
    await session.activate(first, _detail('one'), _part('one'));
    await session.seek(const Duration(milliseconds: 1234));
    await session.setRate(1.5);
    await session.setVolume(42);
    await session.changeQuality(64);
    await session.pause();
    await session.deactivate(first);
    await session.activate(second, _detail('two'), _part('two'));
    expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
    await session.activate(first, _detail('one'), _part('one'));
    expect(
      engine.openOptions.last.startPosition,
      const Duration(milliseconds: 1234),
    );
    expect(engine.currentSnapshot.rate, 1.5);
    expect(engine.currentSnapshot.volume, 42);
    expect(repository.qualities.last, 64);
    expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
    expect(engine.maxSimultaneousPlayers, 1);
    session.detach(second);
    await _flush();
    expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
    session.detach(first);
    await _flush();
    expect(engine.currentSnapshot.phase, PlaybackPhase.idle);
    await session.close();
  });

  test(
    'failed owner restoration retains the last confirmed progress and intent',
    () async {
      final engine = _FakeEngine();
      final repository = _FakeRepository(autoResolve: true);
      final session = PlaybackSession(
        engine: engine,
        repository: repository,
        progress: _FakeProgress(),
        accountScope: () => 'guest',
      );
      final first = Object();
      final second = Object();
      session.attach(first);
      session.attach(second);
      await session.activate(first, _detail('one'), _part('one'));
      await session.seek(const Duration(milliseconds: 1700));
      await session.setRate(1.5);
      await session.setVolume(42);
      await session.pause();
      await session.activate(second, _detail('two'), _part('two'));
      repository.failNextResolve = true;
      await session.activate(first, _detail('one'), _part('one'));
      expect(session.error, isNotNull);
      expect(session.media, isNull);
      expect(engine.currentSnapshot.position, Duration.zero);
      await session.activate(second, _detail('two'), _part('two'));
      await session.activate(first, _detail('one'), _part('one'));
      expect(
        engine.currentSnapshot.position,
        const Duration(milliseconds: 1700),
      );
      expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
      expect(engine.currentSnapshot.rate, 1.5);
      expect(engine.currentSnapshot.volume, 42);
      await session.close();
    },
  );

  test(
    'retry after failed restoration retains pending position and quality',
    () async {
      final engine = _FakeEngine();
      final repository = _FakeRepository(autoResolve: true);
      final session = PlaybackSession(
        engine: engine,
        repository: repository,
        progress: _FakeProgress(),
        accountScope: () => 'guest',
      );
      final first = Object();
      final second = Object();
      session.attach(first);
      session.attach(second);
      await session.activate(first, _detail('one'), _part('one'));
      await session.seek(const Duration(milliseconds: 1700));
      await session.setRate(1.5);
      await session.setVolume(42);
      await session.changeQuality(64);
      await session.pause();
      await session.activate(second, _detail('two'), _part('two'));
      repository.failNextResolve = true;
      await session.activate(first, _detail('one'), _part('one'));
      expect(session.error, isNotNull);
      await session.retry();
      expect(
        engine.currentSnapshot.position,
        const Duration(milliseconds: 1700),
      );
      expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
      expect(engine.currentSnapshot.rate, 1.5);
      expect(engine.currentSnapshot.volume, 42);
      expect(repository.qualities.last, 64);
      // After a source was accepted, retry uses the new confirmed location.
      await session.seek(const Duration(milliseconds: 2400));
      await session.retry();
      expect(
        engine.currentSnapshot.position,
        const Duration(milliseconds: 2400),
      );
      await session.close();
    },
  );

  test('closing suspended owner retains unclosed owner checkpoints', () async {
    final engine = _FakeEngine();
    final session = PlaybackSession(
      engine: engine,
      repository: _FakeRepository(autoResolve: true),
      progress: _FakeProgress(),
      accountScope: () => 'guest',
    );
    final first = Object();
    final second = Object();
    session.attach(first);
    session.attach(second);
    await session.activate(first, _detail('one'), _part('one'));
    await session.seek(const Duration(milliseconds: 1700));
    await session.pause();
    await session.activate(second, _detail('two'), _part('two'));
    await session.deactivate(second);
    session.detach(second);
    await _flush();
    expect(engine.currentSnapshot.phase, PlaybackPhase.idle);
    await session.activate(first, _detail('one'), _part('one'));
    expect(engine.currentSnapshot.position, const Duration(milliseconds: 1700));
    expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
    await session.close();
  });

  for (final paused in [false, true]) {
    test(
      'ordinary tab keeps the same source and intent while paused=$paused',
      () async {
        final engine = _FakeEngine();
        final session = PlaybackSession(
          engine: engine,
          repository: _FakeRepository(autoResolve: true),
          progress: _FakeProgress(),
          accountScope: () => 'guest',
        );
        final owner = Object();
        session.attach(owner);
        await session.activate(owner, _detail('one'), _part('one'));
        await session.seek(const Duration(milliseconds: 321));
        if (paused) await session.pause();
        final generation = engine.currentSnapshot.generation;
        final playCount = engine.playCount;
        final pauseCount = engine.pauseCount;
        final stopCount = engine.stopCount;
        await session.deactivate(owner);
        expect(session.ownsPlayback(owner), isTrue);
        expect(
          engine.currentSnapshot.phase,
          paused ? PlaybackPhase.paused : PlaybackPhase.playing,
        );
        // Confirm that return uses the live engine location, not the checkpoint
        // captured when the video tab first became hidden.
        final retainedPosition = Duration(milliseconds: paused ? 321 : 1987);
        engine.emit(
          engine.currentSnapshot.copyWith(position: retainedPosition),
        );
        await session.activate(owner, _detail('one'), _part('one'));
        expect(
          engine.currentSnapshot.phase,
          paused ? PlaybackPhase.paused : PlaybackPhase.playing,
        );
        expect(engine.currentSnapshot.position, retainedPosition);
        expect(engine.currentSnapshot.generation, generation);
        expect(engine.openedUris, hasLength(1));
        expect(engine.seekTargets, [const Duration(milliseconds: 321)]);
        expect(engine.playCount, playCount);
        expect(engine.pauseCount, pauseCount);
        expect(engine.stopCount, stopCount);
        expect(engine.maxSimultaneousPlayers, 1);
        await session.close();
      },
    );
  }

  for (final paused in [false, true]) {
    test(
      'hidden resolution completes with the intended paused=$paused state',
      () async {
        final engine = _FakeEngine();
        final repository = _FakeRepository();
        final session = PlaybackSession(
          engine: engine,
          repository: repository,
          progress: _FakeProgress(),
          accountScope: () => 'guest',
        );
        session.configureSettings(AppSettings(autoPlay: !paused));
        final owner = Object();
        session.attach(owner);
        final pending = session.activate(owner, _detail('one'), _part('one'));
        await _flush();
        await session.deactivate(owner);
        repository.completeResolve('one');
        await pending;
        expect(
          engine.currentSnapshot.phase,
          paused ? PlaybackPhase.paused : PlaybackPhase.playing,
        );
        expect(session.ownsPlayback(owner), isTrue);
        expect(engine.openedUris, hasLength(1));
        await session.close();
      },
    );
  }

  test('fast hidden owner switching isolates late responses', () async {
    final engine = _FakeEngine();
    final repository = _FakeRepository();
    final session = PlaybackSession(
      engine: engine,
      repository: repository,
      progress: _FakeProgress(),
      accountScope: () => 'guest',
    );
    final first = Object();
    final second = Object();
    session.attach(first);
    session.attach(second);
    final pending = session.activate(first, _detail('one'), _part('one'));
    await _flush();
    final oldFirst = repository.pendingResolves['one'];
    await session.deactivate(first);
    final next = session.activate(second, _detail('two'), _part('two'));
    await _flush();
    final latest = session.activate(first, _detail('one'), _part('one'));
    await _flush();
    repository.completeResolve('one');
    await latest;
    repository.completeResolve('two');
    oldFirst?.complete(_media('one', 80, const Duration(minutes: 2)));
    await Future.wait([pending, next]);
    expect(session.part?.cid, 'one');
    expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
    expect(engine.openedUris, hasLength(1));
    expect(engine.maxSimultaneousPlayers, 1);
    expect(session.ownsPlayback(first), isTrue);
    expect(session.ownsPlayback(second), isFalse);
    await session.close();
  });

  test(
    'switching from an ordinary tab captures its latest background position',
    () async {
      final engine = _FakeEngine();
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        progress: _FakeProgress(),
        accountScope: () => 'guest',
      );
      final first = Object();
      final second = Object();
      session.attach(first);
      session.attach(second);
      await session.activate(first, _detail('one'), _part('one'));
      await session.seek(const Duration(milliseconds: 1234));
      await session.deactivate(first);
      engine.emit(
        engine.currentSnapshot.copyWith(
          position: const Duration(milliseconds: 4567),
        ),
      );
      await session.activate(second, _detail('two'), _part('two'));
      await session.pause();
      await session.seek(const Duration(milliseconds: 2345));
      await session.activate(first, _detail('one'), _part('one'));
      expect(
        engine.openOptions.last.startPosition,
        const Duration(milliseconds: 4567),
      );
      expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
      await session.activate(second, _detail('two'), _part('two'));
      expect(
        engine.openOptions.last.startPosition,
        const Duration(milliseconds: 2345),
      );
      expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
      expect(engine.maxSimultaneousPlayers, 1);
      await session.close();
    },
  );

  test(
    'overlapping temporary rate restorations cannot save or change a new owner',
    () async {
      final engine = _FakeEngine();
      final progress = _FakeProgress();
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        progress: progress,
        accountScope: () => 'guest',
      );
      final first = Object();
      final second = Object();
      session.attach(first);
      session.attach(second);
      await session.activate(first, _detail('one'), _part('one'));
      await session.setRate(1.5);
      await session.beginTemporaryRate(3);
      final sourceGeneration = engine.currentSnapshot.generation;
      final releaseGate = Completer<void>();
      engine.nextRate = releaseGate;
      final release = session.endTemporaryRate(
        expectedGeneration: sourceGeneration,
      );
      final restoreGate = Completer<void>();
      engine.nextRate = restoreGate;
      final hiding = session.deactivate(first);
      await _flush();
      await session.activate(second, _detail('two'), _part('two'));
      progress.writes.clear();
      releaseGate.complete();
      restoreGate.complete();
      await Future.wait([release, hiding]);
      expect(progress.writes, isEmpty);
      expect(session.ownsPlayback(second), isTrue);
      expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
      expect(engine.currentSnapshot.rate, 1.5);
      await session.activate(first, _detail('one'), _part('one'));
      expect(engine.currentSnapshot.rate, 1.5);
      expect(engine.maxSimultaneousPlayers, 1);
      await session.close();
    },
  );

  test(
    'closing another tab leaves background playback; closing its owner stops',
    () async {
      final engine = _FakeEngine();
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        progress: _FakeProgress(),
        accountScope: () => 'guest',
      );
      final owner = Object();
      final other = Object();
      session.attach(owner);
      session.attach(other);
      await session.activate(owner, _detail('one'), _part('one'));
      await session.deactivate(owner);
      final generation = engine.currentSnapshot.generation;
      session.detach(other);
      await _flush();
      expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
      expect(engine.currentSnapshot.generation, generation);
      expect(session.ownsPlayback(owner), isTrue);
      session.detach(owner);
      await _flush();
      expect(engine.currentSnapshot.phase, PlaybackPhase.idle);
      expect(session.ownsPlayback(owner), isFalse);
      await session.close();
    },
  );

  for (final accountChanged in [false, true]) {
    test(
      'hidden pending source cannot play after ${accountChanged ? 'account stop' : 'owner close'}',
      () async {
        final engine = _FakeEngine();
        final repository = _FakeRepository();
        var scope = 'first-account';
        final session = PlaybackSession(
          engine: engine,
          repository: repository,
          progress: _FakeProgress(),
          accountScope: () => scope,
        );
        final owner = Object();
        session.attach(owner);
        final pending = session.activate(owner, _detail('one'), _part('one'));
        await _flush();
        await session.deactivate(owner);
        if (accountChanged) {
          scope = 'second-account';
          await session.stop();
        } else {
          session.detach(owner);
          await _flush();
        }
        repository.completeResolve('one');
        await pending;
        expect(engine.openedUris, isEmpty);
        expect(engine.playCount, 0);
        expect(engine.currentSnapshot.phase, PlaybackPhase.idle);
        expect(session.ownsPlayback(owner), isFalse);
        await session.close();
      },
    );
  }

  test('account stop discards workspace checkpoints', () async {
    final engine = _FakeEngine();
    var scope = 'first-account';
    final session = PlaybackSession(
      engine: engine,
      repository: _FakeRepository(autoResolve: true),
      progress: _FakeProgress(),
      accountScope: () => scope,
    );
    final owner = Object();
    session.attach(owner);
    await session.activate(owner, _detail('one'), _part('one'));
    await session.seek(const Duration(milliseconds: 4567));
    await session.deactivate(owner);
    await session.stop();
    scope = 'second-account';
    await session.activate(owner, _detail('one'), _part('one'));
    expect(engine.openOptions.last.startPosition, Duration.zero);
    await session.close();
  });

  test(
    'rapid open accepts only the latest resolution and late failure is ignored',
    () async {
      final engine = _FakeEngine();
      final repository = _FakeRepository();
      final session = PlaybackSession(
        engine: engine,
        repository: repository,
        progress: _FakeProgress(),
        accountScope: () => 'guest',
      );
      final first = session.open(_detail('one'), _part('one'));
      await _flush();
      final oldGeneration = engine.currentSnapshot.generation;
      final second = session.open(_detail('two'), _part('two'));
      await _flush();
      repository.completeResolve('two');
      await second;
      repository.completeResolve('one');
      await first;
      engine.emitFailure(oldGeneration);
      expect(session.part?.cid, 'two');
      expect(session.error, isNull);
      expect(engine.openedUris, hasLength(1));
      expect(engine.openedUris.single.path, contains('two'));
      await session.close();
    },
  );

  test(
    'old progress write keeps its scope and failure cannot mark the new source',
    () async {
      final engine = _FakeEngine();
      final repository = _FakeRepository(autoResolve: true);
      final progress = _FakeProgress();
      var scope = 'old-account';
      final session = PlaybackSession(
        engine: engine,
        repository: repository,
        progress: progress,
        accountScope: () => scope,
      );
      await session.open(_detail('one'), _part('one'));
      progress.writes.clear();
      final lateWrite = Completer<void>();
      progress.nextWrite = lateWrite;
      final oldSave = session.seek(const Duration(seconds: 9));
      await _flush();
      scope = 'new-account';
      await session.open(_detail('two'), _part('two'));
      expect(progress.writes.first.scope, 'old-account');
      expect(progress.writes.first.cid, 'one');
      lateWrite.completeError(StateError('disk full'));
      await oldSave;
      expect(session.part?.cid, 'two');
      expect(session.auxiliaryMessage, isNull);
      await session.close();
    },
  );

  test(
    'quality change preserves paused intent, position, rate, and volume',
    () async {
      final engine = _FakeEngine();
      final repository = _FakeRepository(autoResolve: true);
      final session = PlaybackSession(
        engine: engine,
        repository: repository,
        progress: _FakeProgress(),
        accountScope: () => 'guest',
      );
      await session.open(_detail('one'), _part('one'));
      await session.pause();
      await session.setRate(1.5);
      await session.setVolume(42);
      await session.seek(const Duration(seconds: 23));
      await session.changeQuality(64);
      expect(repository.qualities.last, 64);
      expect(
        engine.openOptions.last.startPosition,
        const Duration(seconds: 23),
      );
      expect(engine.openOptions.last.rate, 1.5);
      expect(engine.openOptions.last.volume, 42);
      expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
      await session.close();
    },
  );

  test('late comments and subtitle results from old source cannot enter new source', () async {
    final engine = _FakeEngine();
    final repository = _FakeRepository(autoResolve: true);
    final session = PlaybackSession(
      engine: engine,
      repository: repository,
      progress: _FakeProgress(),
      accountScope: () => 'guest',
    );
    await session.open(_detail('one'), _part('one'));
    await _flush();
    final oldComment = repository.pendingComments['one:1'];
    final oldSubtitle = repository.pendingSubtitles['one'];
    await session.open(_detail('two'), _part('two'));
    oldComment?.complete([
      const TimedComment(
        id: 'old',
        position: Duration.zero,
        text: 'old',
        mode: 1,
        color: 0xffffff,
        fontSize: 24,
      ),
    ]);
    oldSubtitle?.complete([
      SubtitleTrack('old', Uri.parse('https://example.test/old')),
    ]);
    await _flush();
    expect(session.subtitleTracks, isEmpty);
    expect(
      session.danmaku.frame().map((e) => e.event.id),
      isNot(contains('old')),
    );
    await session.close();
  });

  test('old stop waiting for progress cannot clear a later reopen', () async {
    final engine = _FakeEngine();
    final repository = _FakeRepository(autoResolve: true);
    final progress = _FakeProgress();
    final session = PlaybackSession(
      engine: engine,
      repository: repository,
      progress: progress,
      accountScope: () => 'guest',
    );
    await session.open(_detail('one'), _part('one'));
    final writeGate = Completer<void>();
    progress.nextWrite = writeGate;
    final oldStop = session.stop();
    await _flush();
    await session.open(_detail('two'), _part('two'));
    writeGate.complete();
    await oldStop;
    expect(session.part?.cid, 'two');
    expect(session.media, isNotNull);
    expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
    await session.close();
  });

  for (final paused in [false, true]) {
    test('same source can reopen during stop while paused=$paused', () async {
      final engine = _FakeEngine();
      final repository = _FakeRepository(autoResolve: true);
      final progress = _FakeProgress();
      final session = PlaybackSession(
        engine: engine,
        repository: repository,
        progress: progress,
        accountScope: () => 'guest',
      );
      await session.open(_detail('one'), _part('one'));
      if (paused) await session.pause();
      final writesBeforeStop = progress.writes.length;
      final writeGate = Completer<void>();
      progress.nextWrite = writeGate;
      final oldStop = session.stop();
      await _flush();
      expect(progress.writes, hasLength(writesBeforeStop + 1));
      expect(progress.writes.last.cid, 'one');
      await session.open(_detail('one'), _part('one'));
      final stopsAfterReopen = engine.stopCount;
      // Complete the older progress write only after the new source is ready.
      writeGate.complete();
      await oldStop;
      expect(engine.openedUris, hasLength(2));
      expect(session.media, isNotNull);
      expect(
        engine.currentSnapshot.phase,
        paused ? PlaybackPhase.paused : PlaybackPhase.playing,
      );
      expect(engine.stopCount, stopsAfterReopen);
      expect(engine.maxSimultaneousPlayers, 1);
      await session.stop();
      expect(session.media, isNull);
      expect(engine.stopCount, stopsAfterReopen + 1);
      await session.close();
      expect(engine.disposed, isTrue);
      expect(engine.subscriptionsActiveAtDispose, isFalse);
    });
  }

  test('stop invalidates a same-source resolution before it yields', () async {
    final engine = _FakeEngine();
    final repository = _FakeRepository();
    final session = PlaybackSession(
      engine: engine,
      repository: repository,
      progress: _FakeProgress(),
      accountScope: () => 'guest',
    );
    final firstOpen = session.open(_detail('one'), _part('one'));
    await _flush();
    final firstResolution = repository.pendingResolves['one'];
    final oldStop = session.stop();
    final reopened = session.open(_detail('one'), _part('one'));
    await _flush();
    expect(repository.qualities, hasLength(2));
    repository.completeResolve('one');
    await reopened;
    firstResolution?.complete(_media('one', 80, const Duration(minutes: 2)));
    await Future.wait([firstOpen, oldStop]);
    expect(session.media, isNotNull);
    expect(engine.openedUris, hasLength(1));
    expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
    expect(engine.maxSimultaneousPlayers, 1);
    await session.close();
  });

  test(
    'repeated stop and temporary owner transfer leave a single engine',
    () async {
      final engine = _FakeEngine();
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        progress: _FakeProgress(),
        accountScope: () => 'guest',
      );
      final oldOwner = Object();
      final newOwner = Object();
      session.attach(oldOwner);
      await session.open(_detail('one'), _part('one'));
      final before = engine.stopCount;
      session.detach(oldOwner);
      session.attach(newOwner);
      await _flush();
      expect(engine.stopCount, before);
      await Future.wait([session.stop(), session.stop()]);
      expect(engine.stopCount, before + 1);
      expect(session.media, isNull);
      await session.open(_detail('two'), _part('two'));
      expect(engine.maxSimultaneousPlayers, 1);
      await session.close();
    },
  );

  test(
    'short video does not prefetch a segment beyond resolved duration',
    () async {
      final engine = _FakeEngine(openDuration: Duration.zero);
      final repository = _FakeRepository(
        autoResolve: true,
        mediaDuration: const Duration(seconds: 267),
      );
      final session = PlaybackSession(
        engine: engine,
        repository: repository,
        progress: _FakeProgress(),
        accountScope: () => 'guest',
      );
      await session.open(_detail('short'), _part('short'));
      expect(repository.pendingComments.keys, contains('short:1'));
      expect(repository.pendingComments.keys, isNot(contains('short:2')));
      expect(session.auxiliaryMessage, isNull);
      await session.close();
    },
  );

  test(
    'prefetch failure stays quiet and current segment failure is reported',
    () async {
      final engine = _FakeEngine(openDuration: Duration.zero);
      final repository = _FakeRepository(
        autoResolve: true,
        mediaDuration: const Duration(minutes: 8),
      );
      final session = PlaybackSession(
        engine: engine,
        repository: repository,
        progress: _FakeProgress(),
        accountScope: () => 'guest',
      );
      await session.open(_detail('long'), _part('long'));
      final prefetch = repository.pendingComments['long:2'];
      expect(prefetch, isNotNull);
      prefetch?.completeError(StateError('prefetch unavailable'));
      await _flush();
      expect(session.auxiliaryMessage, isNull);

      engine.emit(
        engine.currentSnapshot.copyWith(position: const Duration(seconds: 361)),
      );
      final current = repository.pendingComments['long:2'];
      expect(current, isNot(same(prefetch)));
      current?.completeError(StateError('current unavailable'));
      await _flush();
      expect(session.auxiliaryMessage, contains('弹幕暂时不可用'));
      await session.close();
    },
  );

  test(
    'tapping play after completion seeks to zero and resumes immediately',
    () async {
      final engine = _FakeEngine();
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        progress: _FakeProgress(),
        accountScope: () => 'guest',
      );
      await session.open(_detail('ended'), _part('ended'));
      engine.emit(
        engine.currentSnapshot.copyWith(
          phase: PlaybackPhase.ended,
          position: const Duration(minutes: 2),
          desiredPlaying: false,
        ),
      );
      await session.togglePlaying();
      expect(engine.seekTargets.last, Duration.zero);
      expect(engine.currentSnapshot.position, Duration.zero);
      expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
      await session.togglePlaying();
      expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
      await session.close();
    },
  );

  test('close releases resources even when stop throws', () async {
    final engine = _FakeEngine();
    final session = PlaybackSession(
      engine: engine,
      repository: _FakeRepository(autoResolve: true),
      progress: _FakeProgress(),
      accountScope: () => 'guest',
    );
    await session.open(_detail('one'), _part('one'));
    engine.failStop = true;
    await expectLater(session.close(), throwsA(isA<StateError>()));
    expect(engine.disposed, isTrue);
    expect(engine.subscriptionsActiveAtDispose, isFalse);
  });

  test(
    'watch-later completion runs remaining parts then next video once',
    () async {
      final engine = _FakeEngine();
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        progress: _FakeProgress(),
        accountScope: () => 'user:7',
      );
      addTearDown(session.close);
      session.configureSettings(AppSettings(autoPlay: false));
      final first = VideoDetail(
        summary: _detail('one').summary,
        description: '',
        parts: [_part('one'), _part('one-p2')],
      );
      final second = _detail('two');
      final queue = WatchLaterQueue(
        id: 'test',
        scope: 'user:7',
        sessionEpoch: 0,
        items: [
          WatchLaterQueueItem(video: first.summary),
          WatchLaterQueueItem(video: second.summary),
        ],
      );
      final playback = WatchLaterQueuePlayback();
      final owner = Object();
      session.attach(owner);
      await session.activate(owner, first, first.parts.first);
      expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
      await session.togglePlaying();
      engine.emit(engine.currentSnapshot.copyWith(phase: PlaybackPhase.ended));
      final nextPart = playback.completed(queue, session, first.summary.id);
      expect(nextPart?.part?.cid, 'one-p2');
      expect(nextPart?.video, isNull);
      expect(playback.completed(queue, session, first.summary.id), isNull);
      await session.deactivate(owner);
      await session.activate(owner, first, first.parts.last);
      expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
      playback.reset();
      engine.emit(engine.currentSnapshot.copyWith(phase: PlaybackPhase.ended));
      final nextVideo = playback.completed(queue, session, first.summary.id);
      expect(nextVideo?.video, second.summary.id);
      expect(playback.completed(queue, session, first.summary.id), isNull);
      await session.activate(owner, second, second.parts.first);
      expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
      playback.reset();
      engine.emit(engine.currentSnapshot.copyWith(phase: PlaybackPhase.ended));
      expect(playback.completed(queue, session, second.summary.id), isNull);
      expect(session.engine, same(engine));
      expect(engine.maxSimultaneousPlayers, 1);
    },
  );

  test(
    'watch-later explicit selection keeps pause and rejects old account epoch',
    () async {
      var scope = 'user:7';
      var epoch = 4;
      final engine = _FakeEngine();
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        progress: _FakeProgress(),
        accountScope: () => scope,
        sessionEpoch: () => epoch,
      );
      addTearDown(session.close);
      session.configureSettings(AppSettings(autoPlay: false));
      final first = _detail('one');
      final second = _detail('two');
      final queue = WatchLaterQueue(
        id: 'test',
        scope: scope,
        sessionEpoch: epoch,
        items: [
          WatchLaterQueueItem(video: first.summary),
          WatchLaterQueueItem(video: second.summary),
        ],
      );
      final playback = WatchLaterQueuePlayback();
      final owner = Object();
      session.attach(owner);
      await session.activate(owner, first, first.parts.first);
      expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
      expect(playback.select(queue, session, second.summary.id), isTrue);
      await session.activate(owner, second, second.parts.first);
      expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
      expect(
        playback.adjacent(queue, session, second.summary.id, -1),
        first.summary.id,
      );
      epoch++;
      expect(playback.select(queue, session, first.summary.id), isFalse);
      expect(playback.adjacent(queue, session, second.summary.id, -1), isNull);
      engine.emit(engine.currentSnapshot.copyWith(phase: PlaybackPhase.ended));
      expect(playback.completed(queue, session, second.summary.id), isNull);
      scope = 'user:8';
      expect(playback.select(queue, session, first.summary.id), isFalse);
    },
  );

  test(
    'watch-later pending play intent cannot cross a session epoch',
    () async {
      var epoch = 4;
      final engine = _FakeEngine();
      final session = PlaybackSession(
        engine: engine,
        repository: _FakeRepository(autoResolve: true),
        progress: _FakeProgress(),
        accountScope: () => 'user:7',
        sessionEpoch: () => epoch,
      );
      addTearDown(session.close);
      session.configureSettings(AppSettings(autoPlay: false));
      final owner = Object();
      session.attach(owner);
      final first = _detail('one');
      final second = _detail('two');
      await session.activate(owner, first, first.parts.first);
      await session.togglePlaying();
      engine.emit(engine.currentSnapshot.copyWith(phase: PlaybackPhase.ended));
      expect(
        session.prepareNextVideo(
          first.summary.id,
          first.parts.first.cid,
          nextId: second.summary.id,
          completed: true,
        ),
        isTrue,
      );
      epoch++;
      await session.activate(owner, second, second.parts.first);
      expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
      await session.togglePlaying();
      expect(
        session.prepareNextVideo(
          second.summary.id,
          second.parts.first.cid,
          nextId: first.summary.id,
        ),
        isTrue,
      );
      await session.stop();
      await session.activate(owner, first, first.parts.first);
      expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
    },
  );
}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

PlaybackManager _manager({
  PlaybackRepository? repository,
  PlaybackRateMemory? rateMemory,
}) {
  final rates = rateMemory ?? PlaybackRateMemory();
  return PlaybackManager(
    createSession: () => PlaybackSession(
      engine: _FakeEngine(),
      repository: repository ?? _FakeRepository(autoResolve: true),
      progress: _FakeProgress(),
      accountScope: () => 'guest',
      rateMemory: rates,
    ),
  );
}

const _timelineMetadata = PlaybackMetadata(
  subtitles: [],
  chapters: [
    VideoChapter(
      start: Duration.zero,
      end: Duration(seconds: 20),
      title: 'Chapter one',
    ),
  ],
);
final _storyboard = VideoStoryboard(
  columns: 1,
  rows: 1,
  tileWidth: 160,
  tileHeight: 90,
  images: [Uri.parse('https://i0.hdslb.com/story.jpg')],
  times: [Duration.zero],
);

final class _FakeMetadataRepository implements PlaybackMetadataRepository {
  final metadataPending = <String, Completer<PlaybackMetadata>>{};
  final storyboardPending = <String, Completer<VideoStoryboard?>>{};
  final storyboardTokens = <String, RequestCancellation>{};
  final storyboardCalls = <String>[];
  @override
  Future<PlaybackMetadata> metadata(
    VideoDetail video,
    VideoPart part, {
    required RequestCancellation cancellation,
  }) {
    final gate = Completer<PlaybackMetadata>();
    metadataPending[part.cid] = gate;
    return gate.future;
  }

  @override
  Future<VideoStoryboard?> storyboard(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  }) {
    storyboardCalls.add(cid);
    final gate = Completer<VideoStoryboard?>();
    storyboardPending[cid] = gate;
    storyboardTokens[cid] = cancellation;
    return gate.future;
  }
}

VideoDetail _detail(String id) => VideoDetail(
  summary: VideoSummary(
    id: VideoId('BV12345678$id'),
    title: id,
    coverUrl: '',
    author: '',
    duration: const Duration(minutes: 2),
  ),
  description: '',
  parts: [_part(id)],
);

VideoPart _part(String id) => VideoPart(
  cid: id,
  page: 1,
  title: id,
  duration: const Duration(minutes: 2),
);

PlaybackMedia _media(String id, int quality, Duration duration) =>
    PlaybackMedia(
      video: PlaybackTrack(
        urls: [Uri.parse('https://cdn.example/$id-video.m4s')],
        codec: 'avc1',
        bandwidth: 1000,
      ),
      audio: PlaybackTrack(
        urls: [Uri.parse('https://cdn.example/$id-audio.m4s')],
        codec: 'mp4a',
        bandwidth: 128,
      ),
      quality: quality,
      qualities: const [64, 80],
      duration: duration,
      headers: const {'Referer': 'https://www.bilibili.com'},
    );

PlaybackMedia _backupMedia() => PlaybackMedia(
  video: PlaybackTrack(
    urls: [
      Uri.parse('https://primary.mcdn.bilivideo.cn/v.m4s?k=primary'),
      Uri.parse('https://node.edge.mountaintoys.cn/v.m4s?k=edge'),
      Uri.parse('https://upos-sz-mirrorcos.bilivideo.com/v%2F1.m4s?k=regular'),
    ],
    codec: 'avc1',
    bandwidth: 1000,
  ),
  audio: PlaybackTrack(
    urls: [
      Uri.parse('https://audio.mcdn.bilivideo.cn/a.m4s?k=primary'),
      Uri.parse('https://audio.edge.mountaintoys.cn/a.m4s?k=edge'),
      Uri.parse('https://upos-sz-mirrorhw.bilivideo.com/a.m4s?k=regular'),
    ],
    codec: 'mp4a',
    bandwidth: 100,
  ),
  quality: 80,
  qualities: const [80],
  duration: const Duration(minutes: 2),
  headers: const {},
);

final class _FakeRepository implements PlaybackRepository {
  _FakeRepository({
    this.autoResolve = false,
    this.mediaDuration = const Duration(minutes: 2),
  });
  final bool autoResolve;
  bool failNextResolve = false;
  final Duration mediaDuration;
  final pendingResolves = <String, Completer<PlaybackMedia>>{};
  final pendingComments = <String, Completer<List<TimedComment>>>{};
  final commentCancellations = <String, RequestCancellation>{};
  final pendingSubtitles = <String, Completer<List<SubtitleTrack>>>{};
  final qualities = <int>[];
  final codecs = <VideoCodecPreference>[];

  void completeResolve(String cid) => pendingResolves[cid]?.complete(
    _media(cid, qualities.last, mediaDuration),
  );

  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) {
    qualities.add(quality);
    codecs.add(preferredCodec);
    if (failNextResolve) {
      failNextResolve = false;
      return Future.error(StateError('resolution failed'));
    }
    if (autoResolve) return Future.value(_media(cid, quality, mediaDuration));
    final gate = Completer<PlaybackMedia>();
    pendingResolves[cid] = gate;
    return gate.future;
  }

  @override
  Future<List<TimedComment>> comments(
    String cid,
    int segment, {
    required RequestCancellation cancellation,
  }) {
    final gate = Completer<List<TimedComment>>();
    pendingComments['$cid:$segment'] = gate;
    commentCancellations['$cid:$segment'] = cancellation;
    return gate.future;
  }

  @override
  Future<List<SubtitleTrack>> subtitles(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  }) {
    final gate = Completer<List<SubtitleTrack>>();
    pendingSubtitles[cid] = gate;
    return gate.future;
  }

  @override
  Future<List<SubtitleCue>> subtitleCues(
    SubtitleTrack track, {
    required RequestCancellation cancellation,
  }) => Future.value(const []);
}

final class _VoiceRepository extends Fake
    implements PlaybackRepository, VoicePlaybackRepository {
  static const english = PlaybackVoice(
    languageCode: 'en',
    label: 'English',
    productionType: 2,
    subtitleLanguage: 'ai-en',
  );
  static const japanese = PlaybackVoice(
    languageCode: 'ja',
    label: '日本語',
    productionType: 2,
    subtitleLanguage: 'ai-ja',
  );
  bool delayVoices = false, delayCues = false;
  final pending = <String, Completer<PlaybackMedia>>{};
  final voiceCancellations = <String, RequestCancellation>{};
  final requestedQualities = <String, int>{};
  final cues = <Completer<List<SubtitleCue>>>[];
  PlaybackMedia _resolved(int quality, PlaybackVoice voice) => PlaybackMedia(
    video: PlaybackTrack(
      urls: [Uri.https('example.test', '/video/${voice.languageCode}')],
      codec: 'avc1',
      bandwidth: 1000,
    ),
    audio: PlaybackTrack(
      urls: [Uri.https('example.test', '/audio/${voice.languageCode}')],
      codec: 'mp4a',
      bandwidth: 128,
    ),
    quality: quality,
    qualities: const [64, 80],
    duration: const Duration(minutes: 2),
    headers: const {},
    voices: const [english, japanese],
    voice: voice,
  );
  void completeVoice(String language) => pending[language]!.complete(
    _resolved(
      requestedQualities[language]!,
      language == 'en' ? english : japanese,
    ),
  );
  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => _resolved(quality, const PlaybackVoice.original());
  @override
  Future<PlaybackMedia> resolveVoice(
    VideoId video,
    String cid, {
    required PlaybackVoice voice,
    required int quality,
    required VideoCodecPreference preferredCodec,
    required RequestCancellation cancellation,
  }) {
    voiceCancellations[voice.languageCode] = cancellation;
    requestedQualities[voice.languageCode] = quality;
    if (!delayVoices) return Future.value(_resolved(quality, voice));
    final gate = Completer<PlaybackMedia>();
    pending[voice.languageCode] = gate;
    return gate.future;
  }

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
  }) async => [
    SubtitleTrack(
      '中文',
      Uri.https('example.test', '/zh'),
      languageCode: 'ai-zh',
    ),
    SubtitleTrack(
      'English',
      Uri.https('example.test', '/en'),
      languageCode: 'ai-en',
    ),
    SubtitleTrack(
      '日本語',
      Uri.https('example.test', '/ja'),
      languageCode: 'ai-ja',
    ),
  ];
  @override
  Future<List<SubtitleCue>> subtitleCues(
    SubtitleTrack track, {
    required RequestCancellation cancellation,
  }) {
    if (!delayCues) return Future.value([]);
    final gate = Completer<List<SubtitleCue>>();
    cues.add(gate);
    return gate.future;
  }
}

final class _ProgressWrite {
  const _ProgressWrite(this.scope, this.cid, this.episodeId);
  final String scope;
  final String cid;
  final String? episodeId;
}

final class _FakeHistory implements PlaybackHistoryRepository {
  Duration? readValue;
  AppFailure? readFailure;
  Completer<Duration?>? nextRead;
  final reads =
      <({PlaybackHistoryTarget target, RequestCancellation cancellation})>[];
  final reports = <PlaybackHistoryRecord>[];
  @override
  Future<Duration?> read(
    PlaybackHistoryTarget target, {
    required String scope,
    required RequestCancellation cancellation,
  }) {
    reads.add((target: target, cancellation: cancellation));
    final pending = nextRead;
    nextRead = null;
    if (readFailure != null) return Future.error(readFailure!);
    return pending?.future ?? Future.value(readValue);
  }

  @override
  Future<void> report(
    PlaybackHistoryRecord record, {
    required String scope,
    required RequestCancellation cancellation,
  }) async {
    reports.add(record);
  }
}

final class _FakeProgress implements PlaybackProgressStore {
  final writes = <_ProgressWrite>[];
  Completer<void>? nextWrite;
  Duration? readValue = Duration.zero;
  Completer<Duration?>? nextRead;

  @override
  Future<Duration?> read(String scope, VideoId video, String cid) {
    final pending = nextRead;
    nextRead = null;
    return pending?.future ?? Future.value(readValue);
  }

  @override
  Future<void> write(
    String scope,
    VideoSummary video,
    VideoPart part,
    Duration position,
    Duration duration, {
    String? episodeId,
  }) {
    writes.add(_ProgressWrite(scope, part.cid, episodeId));
    final gate = nextWrite;
    nextWrite = null;
    return gate?.future ?? Future.value();
  }
}

final class _FakeEngine implements PlayerEngine {
  _FakeEngine({this.openDuration = const Duration(minutes: 2)});
  final Duration openDuration;
  final _snapshots = StreamController<PlaybackSnapshot>.broadcast(sync: true);
  final _failures = StreamController<PlayerFailure>.broadcast(sync: true);
  PlaybackSnapshot _current = const PlaybackSnapshot(
    phase: PlaybackPhase.idle,
    generation: 0,
  );
  int stopCount = 0;
  int playCount = 0;
  int pauseCount = 0;
  int maxSimultaneousPlayers = 0;
  bool failStop = false;
  bool disposed = false;
  bool subscriptionsActiveAtDispose = false;
  int _players = 0;
  final openedUris = <Uri>[];
  final openOptions = <OpenOptions>[];
  final sources = <ResolvedMediaSource>[];
  final seekTargets = <Duration>[];
  Completer<void>? nextRate;
  Completer<void>? nextVolume;
  int volumeCalls = 0;
  Completer<void>? nextPause;
  Completer<void>? nextOpen;
  PlayerFailureKind? nextOpenFailure;
  void Function()? onOpenFailure;

  @override
  PlaybackSnapshot get currentSnapshot => _current;
  @override
  Stream<PlaybackSnapshot> get snapshots => _snapshots.stream;
  @override
  Stream<PlayerFailure> get failures => _failures.stream;
  @override
  PlayerCapabilities get capabilities =>
      const PlayerCapabilities(externalAudio: true, externalAudioHeaders: true);

  void emit(PlaybackSnapshot value) {
    _current = value;
    _snapshots.add(value);
  }

  void emitFailure(int generation) => _failures.add(
    PlayerFailure(PlayerFailureKind.nativePlayback, 'old failure', generation),
  );

  @override
  Future<void> open(ResolvedMediaSource source, OpenOptions options) async {
    _players++;
    if (_players > maxSimultaneousPlayers) maxSimultaneousPlayers = _players;
    sources.add(source);
    openedUris.add(switch (source) {
      DashPairSource(:final video) => video.uri,
      DashVideoSource(:final video) => video.uri,
      ManifestSource(:final media) => media.uri,
      ProgressiveSource(:final media) => media.uri,
    });
    openOptions.add(options);
    final pending = nextOpen;
    nextOpen = null;
    final generation = _current.generation;
    if (pending != null) await pending.future;
    if (disposed || generation != _current.generation) return;
    final failure = nextOpenFailure;
    nextOpenFailure = null;
    if (failure != null) {
      _players--;
      emit(
        _current.copyWith(
          phase: PlaybackPhase.failed,
          generation: generation + 1,
        ),
      );
      onOpenFailure?.call();
      throw PlayerFailure(failure, 'fixture open failure', _current.generation);
    }
    emit(
      PlaybackSnapshot(
        phase: PlaybackPhase.paused,
        generation: _current.generation + 1,
        position: options.startPosition,
        duration: openDuration,
        rate: options.rate,
        volume: options.volume,
        desiredPlaying: options.play,
      ),
    );
  }

  @override
  Future<void> play() async {
    playCount++;
    emit(_current.copyWith(phase: PlaybackPhase.playing, desiredPlaying: true));
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    final pending = nextPause;
    nextPause = null;
    if (pending != null) await pending.future;
    emit(_current.copyWith(phase: PlaybackPhase.paused, desiredPlaying: false));
  }

  @override
  Future<void> seek(Duration target) async {
    seekTargets.add(target);
    emit(_current.copyWith(position: target));
  }

  @override
  Future<void> setRate(double rate) async {
    final generation = _current.generation;
    final gate = nextRate;
    nextRate = null;
    if (gate != null) await gate.future;
    // Match the native adapter's generation-scoped command contract.
    if (generation == _current.generation) emit(_current.copyWith(rate: rate));
  }

  @override
  Future<void> setVolume(double volume) async {
    volumeCalls++;
    final generation = _current.generation;
    final gate = nextVolume;
    nextVolume = null;
    if (gate != null) await gate.future;
    if (generation == _current.generation) {
      emit(_current.copyWith(volume: volume));
    }
  }

  @override
  Future<void> stop() async {
    stopCount++;
    if (failStop) throw StateError('stop failed');
    _players = 0;
    emit(
      PlaybackSnapshot(
        phase: PlaybackPhase.idle,
        generation: _current.generation + 1,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    subscriptionsActiveAtDispose =
        _snapshots.hasListener || _failures.hasListener;
    disposed = true;
    await _snapshots.close();
    await _failures.close();
  }
}

const _sponsorSegment = SponsorSegment(
  id: 'skip',
  category: 'sponsor',
  start: Duration(seconds: 10),
  end: Duration(seconds: 20),
  videoDuration: Duration.zero,
);

final class _FakeSponsor implements SponsorRepository {
  final pending = <String, Completer<List<SponsorSegment>>>{};
  @override
  Future<List<SponsorSegment>> segments(
    VideoId video,
    String cid, {
    required List<String> categories,
    required RequestCancellation cancellation,
  }) {
    final result = Completer<List<SponsorSegment>>();
    pending[cid] = result;
    return result.future;
  }
}

final class _FakeContentRepository implements ContentPlaybackRepository {
  _FakeContentRepository({this.duration = const Duration(minutes: 2)});
  final Duration duration;
  final targets = <ContentPlaybackTarget>[];
  final qualities = <int>[];
  final codecs = <VideoCodecPreference>[];
  final cancellations = <RequestCancellation>[];
  Completer<PlaybackMedia>? pending;
  @override
  Future<PlaybackMedia> resolve(
    ContentPlaybackTarget target, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) {
    targets.add(target);
    qualities.add(quality);
    codecs.add(preferredCodec);
    cancellations.add(cancellation);
    final gate = pending;
    pending = null;
    if (gate != null) return gate.future;
    if (target is OfflinePlaybackTarget) {
      return Future.value(_media('offline', quality, duration));
    }
    if (target is PgcPlaybackTarget) {
      return Future.value(_media(target.episodeId, quality, duration));
    }
    return Future.value(
      PlaybackMedia(
        video: PlaybackTrack(
          urls: [Uri.parse('https://example.test/live.m3u8')],
          codec: 'avc',
          bandwidth: 0,
        ),
        audio: null,
        quality: quality,
        qualities: const [400, 10000],
        duration: Duration.zero,
        headers: const {},
        kind: PlaybackMediaKind.liveHls,
      ),
    );
  }
}

TimedComment _comment(String id, int second) => TimedComment(
  id: id,
  position: Duration(seconds: second),
  text: id,
  mode: 1,
  color: 0xffffff,
  fontSize: 24,
);
