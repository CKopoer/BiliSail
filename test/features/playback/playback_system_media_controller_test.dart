import 'package:bilisail/core/platform/system_media_controls.dart';
import 'package:bilisail/features/playback/application/playback_manager.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/content_playback.dart';
import 'package:bili_player/bili_player.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/system_media_playback_fixture.dart';
import '../../support/video_card_fake_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Controls controls;
  late PlaybackManager manager;
  late List<_Engine> engines;
  late int epoch;
  setUp(() {
    controls = _Controls();
    engines = [];
    epoch = 0;
    manager = PlaybackManager(
      systemMediaControls: controls,
      createSession: () {
        final engine = _Engine();
        engines.add(engine);
        final repository = SystemMediaFixtureRepository();
        return PlaybackSession(
          engine: engine,
          repository: repository,
          contentRepository: SystemMediaFixtureContent(repository),
          progress: SystemMediaFixtureProgress(),
          accountScope: () => 'guest',
          sessionEpoch: () => epoch,
        );
      },
    );
    addTearDown(manager.close);
  });

  Future<PlaybackSession> open(String tab, {bool concurrent = true}) async {
    final session = manager.acquire(tab);
    await manager.updateWorkspace(
      allowConcurrent: concurrent,
      activeTabId: tab,
    );
    await session.open(systemMediaVideo(tab), systemMediaPart);
    return session;
  }

  test(
    'metadata and commands reuse the same engine; play is idempotent',
    () async {
      await open('video');
      expect(controls.state?.title, 'video');
      expect(controls.state?.artist, 'fixture');
      expect(controls.state?.playing, isTrue);
      final opens = engines.single.opens;
      await controls.command(SystemMediaAction.pause);
      expect(engines.single.currentSnapshot.desiredPlaying, isFalse);
      await controls.command(SystemMediaAction.play);
      await controls.command(SystemMediaAction.play);
      expect(engines.single.currentSnapshot.desiredPlaying, isTrue);
      expect(engines.single.opens, opens);
      await controls.command(
        SystemMediaAction.seek,
        const Duration(seconds: 400),
      );
      expect(
        engines.single.currentSnapshot.position,
        const Duration(seconds: 20),
      );
      await controls.command(
        SystemMediaAction.seek,
        const Duration(seconds: -1),
      );
      expect(engines.single.currentSnapshot.position, Duration.zero);
    },
  );

  test(
    'ten-second controls use the current position and clamp to duration',
    () async {
      await open('video');
      final engine = engines.single;
      engine.advance(const Duration(seconds: 4));
      await controls.command(SystemMediaAction.rewind);
      expect(engine.currentSnapshot.position, Duration.zero);
      engine.advance(const Duration(seconds: 15));
      await controls.command(SystemMediaAction.fastForward);
      expect(engine.currentSnapshot.position, const Duration(seconds: 20));
    },
  );

  test(
    'completion clears controls, rejects stale commands and replay republishes',
    () async {
      final session = await open('video');
      final engine = engines.single;
      final id = controls.state!.id;
      engine.publish(engine.snapshot.copyWith(phase: PlaybackPhase.ended));
      expect(controls.state, isNull);
      await controls.onCommand!(SystemMediaCommand(id, SystemMediaAction.play));
      expect(engine.currentSnapshot.phase, PlaybackPhase.ended);
      await session.play();
      expect(controls.state?.title, 'video');
      expect(controls.state?.playing, isTrue);
      engine.publish(engine.snapshot.copyWith(phase: PlaybackPhase.ended));
      expect(controls.state, isNull);
      await session.open(
        systemMediaVideo('next'),
        systemMediaPart,
        force: true,
      );
      expect(controls.state?.title, 'next');
    },
  );

  test('completion falls back to another retained session', () async {
    await open('one');
    await open('two');
    engines.last.publish(
      engines.last.snapshot.copyWith(phase: PlaybackPhase.ended),
    );
    expect(controls.state?.title, 'one');
    engines.first.publish(
      engines.first.snapshot.copyWith(phase: PlaybackPhase.ended),
    );
    expect(controls.state, isNull);
  });

  test('selected media owns controls across normal pages', () async {
    final first = await open('one');
    await open('two');
    expect(controls.state?.title, 'two');
    final staleId = controls.state!.id;
    await manager.updateWorkspace(allowConcurrent: true, activeTabId: 'home');
    expect(controls.state?.title, 'two');
    await manager.updateWorkspace(allowConcurrent: true, activeTabId: 'one');
    await controls.onCommand!(
      SystemMediaCommand(staleId, SystemMediaAction.pause),
    );
    expect(first.snapshots.value.desiredPlaying, isTrue);
    await controls.command(SystemMediaAction.pause);
    expect(first.snapshots.value.desiredPlaying, isFalse);
    expect(engines.last.currentSnapshot.desiredPlaying, isTrue);
  });

  test('source switch rejects delayed system actions', () async {
    final session = await open('old');
    final id = controls.state!.id;
    await session.open(systemMediaVideo('new'), systemMediaPart, force: true);
    await controls.onCommand!(SystemMediaCommand(id, SystemMediaAction.stop));
    expect(controls.state?.title, 'new');
    expect(session.media, isNotNull);
  });

  test(
    'system play retries a failed source using its existing session',
    () async {
      final session = await open('video');
      final opens = engines.single.opens;
      session.error = 'fixture failure';
      await controls.command(SystemMediaAction.play);
      expect(session.error, isNull);
      expect(engines.single.opens, opens + 1);
      expect(controls.state?.playing, isTrue);
    },
  );

  test(
    'stop clears notification; closing selected tab falls back to survivor',
    () async {
      await open('one');
      final second = await open('two');
      manager.release('two', second);
      expect(controls.state?.title, 'one');
      await controls.command(SystemMediaAction.stop);
      expect(controls.state, isNull);
      expect(engines.first.currentSnapshot.phase, PlaybackPhase.idle);
    },
  );

  test(
    'closing the last playback page clears paused and playing targets',
    () async {
      for (final paused in [false, true]) {
        final session = await open('video');
        if (paused) await session.pause();
        final id = controls.state!.id;
        manager.release('video', session);
        expect(controls.state, isNull);
        expect(manager.sessions, isEmpty);
        await controls.onCommand!(
          SystemMediaCommand(id, SystemMediaAction.play),
        );
        expect(controls.state, isNull);
      }
      await open('next');
      expect(controls.state?.title, 'next');
      expect(controls.state?.playing, isTrue);
    },
  );

  test(
    'account stop clears every target and old actions cannot resume',
    () async {
      await open('one');
      await open('two');
      final id = controls.state!.id;
      await manager.stop();
      expect(controls.state, isNull);
      await controls.onCommand!(SystemMediaCommand(id, SystemMediaAction.play));
      expect(engines.every((e) => !e.currentSnapshot.desiredPlaying), isTrue);
    },
  );

  test(
    'system actions reject an expired account epoch before cleanup finishes',
    () async {
      await open('one');
      await controls.command(SystemMediaAction.pause);
      epoch++;
      await controls.command(SystemMediaAction.play);
      expect(engines.single.currentSnapshot.desiredPlaying, isFalse);
      await manager.stop();
      expect(controls.state, isNull);
    },
  );

  test('removing the Android task stops every concurrent session', () async {
    await open('one');
    await open('two');
    await controls.command(SystemMediaAction.stopAll);
    expect(controls.state, isNull);
    expect(
      engines.every((e) => e.currentSnapshot.phase == PlaybackPhase.idle),
      isTrue,
    );
  });

  test(
    'live controls have no duration or seek; PGC and offline share commands',
    () async {
      final session = manager.acquire('content');
      await manager.updateWorkspace(
        allowConcurrent: true,
        activeTabId: 'content',
      );
      for (final target in const <ContentPlaybackTarget>[
        PgcPlaybackTarget('1'),
        OfflinePlaybackTarget('local'),
        LivePlaybackTarget('1'),
      ]) {
        await session.open(null, null, target: target, title: target.key);
        expect(controls.state?.title, target.key);
        expect(controls.state?.canSeek, target is! LivePlaybackTarget);
        final seeks = engines.single.seeks;
        await controls.command(
          SystemMediaAction.seek,
          const Duration(seconds: 4),
        );
        expect(
          engines.single.seeks,
          seeks + (target is LivePlaybackTarget ? 0 : 1),
        );
      }
      expect(controls.state?.duration, Duration.zero);
    },
  );

  test('position samples publish once per second; buffering and pause are immediate', () async {
    await open('one');
    final engine = engines.single;
    engine.advance(const Duration(seconds: 2));
    final count = controls.updates.length;
    engine.advance(const Duration(milliseconds: 2100));
    engine.advance(const Duration(milliseconds: 2200));
    expect(controls.updates.length, count);
    engine.publish(engine.snapshot.copyWith(isBuffering: true));
    expect(controls.state?.phase, SystemMediaPhase.buffering);
    await controls.command(SystemMediaAction.pause);
    expect(controls.state?.playing, isFalse);
  });

  test(
    'only public artwork is published and close detaches callbacks',
    () async {
      final session = await open('one');
      await session.open(
        systemMediaVideo(
          'cover',
          cover: 'https://i0.hdslb.com/a.jpg?token=secret#x',
        ),
        systemMediaPart,
        force: true,
      );
      expect(controls.state?.artUri.toString(), 'https://i0.hdslb.com/a.jpg');
      await session.open(
        systemMediaVideo('cover', cover: 'https://private.test/a?token=secret'),
        systemMediaPart,
        force: true,
      );
      expect(controls.state?.artUri, isNull);
      await manager.close();
      expect(controls.closed, isTrue);
      expect(controls.onCommand, isNull);
    },
  );
}

class _Controls extends SystemMediaControls {
  SystemMediaState? state;
  final updates = <SystemMediaState?>[];
  bool closed = false;
  @override
  void publish(SystemMediaState? value) {
    state = value;
    updates.add(value);
  }

  Future<void> command(SystemMediaAction action, [Duration? position]) async {
    await onCommand?.call(
      SystemMediaCommand(state!.id, action, position: position),
    );
  }

  @override
  Future<void> close() async {
    publish(null);
    closed = true;
    onCommand = null;
  }
}

class _Engine extends CardFakeEngine {
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
  @override
  Future<void> setRate(double rate) async =>
      publish(snapshot.copyWith(rate: rate));
  @override
  Future<void> setVolume(double volume) async =>
      publish(snapshot.copyWith(volume: volume));
}
