import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/playback/domain/content_playback.dart';
import 'package:bilisail/features/playback/domain/sponsor_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bili_player/bili_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('optional timeline failures preserve ready media and do not repeat on hover', () async {
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
      expect(session.snapshots.value.rate, 1);
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
      expect(engine.currentSnapshot.rate, 1);
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
}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
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

final class _ProgressWrite {
  const _ProgressWrite(this.scope, this.cid, this.episodeId);
  final String scope;
  final String cid;
  final String? episodeId;
}

final class _FakeProgress implements PlaybackProgressStore {
  final writes = <_ProgressWrite>[];
  Completer<void>? nextWrite;

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
      ManifestSource(:final media) => media.uri,
      ProgressiveSource(:final media) => media.uri,
    });
    openOptions.add(options);
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
  Future<void> setVolume(double volume) async =>
      emit(_current.copyWith(volume: volume));
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
