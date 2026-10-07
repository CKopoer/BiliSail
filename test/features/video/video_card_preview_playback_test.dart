import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/video/application/video_card_preview_playback.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/video_card_fake_engine.dart';

void main() {
  late List<CardFakeEngine> engines;
  late VideoCardPreviewPlayback previews;
  setUp(() {
    engines = [];
    previews = VideoCardPreviewPlayback(
      createEngine: () {
        final engine = CardFakeEngine();
        engines.add(engine);
        return engine;
      },
    );
  });
  tearDown(() => previews.close());

  test('plays video DASH without fetching audio, muted from zero and releases on cancel', () async {
    final token = RequestCancellation();
    final session = await previews.start(cardPreviewMedia(), token);
    final engine = engines.single;
    final source = engine.source as DashVideoSource;
    expect(
      source.video.requestPolicy.headers['Referer'],
      'https://www.bilibili.com/',
    );
    expect(engine.options?.play, true);
    expect(engine.options?.volume, 0);
    expect(engine.options?.startPosition, Duration.zero);
    expect(engine.options?.openTimeout, const Duration(seconds: 3));
    expect(engine.options?.maxBufferAhead, const Duration(seconds: 15));
    token.cancel();
    expect(engine.currentSnapshot.phase, PlaybackPhase.idle);
    await previews.stop();
    expect(session?.closed, true);
    expect(engine.stops, 1);
    expect(engine.disposals, 1);
  });

  test('leaving during open invalidates late native completion', () async {
    final engine = CardFakeEngine()..opening = Completer<void>();
    final manager = VideoCardPreviewPlayback(createEngine: () => engine);
    addTearDown(manager.close);
    final token = RequestCancellation();
    final pending = manager.start(cardPreviewMedia(), token);
    await Future<void>.delayed(Duration.zero);
    token.cancel();
    await manager.stop();
    engine.opening!.complete();
    expect(await pending, isNull);
    expect(engine.currentSnapshot.desiredPlaying, false);
    expect(engine.disposals, 1);
  });

  test(
    'waits for native release and only newest queued hover starts',
    () async {
      final firstToken = RequestCancellation();
      await previews.start(cardPreviewMedia(), firstToken);
      engines.single.releasing = Completer<void>();
      final secondToken = RequestCancellation();
      final second = previews.start(cardPreviewMedia(), secondToken);
      final third = previews.start(cardPreviewMedia(), RequestCancellation());
      await Future<void>.delayed(Duration.zero);
      expect(firstToken.isCancelled, true);
      expect(engines.length, 1);
      engines.first.releasing!.complete();
      expect(await second, isNull);
      expect(await third, isNotNull);
      expect(engines.length, 2);
      expect(engines.first.disposals, 1);
    },
  );

  test(
    'confirmed player failure closes preview and process close rejects starts',
    () async {
      final token = RequestCancellation();
      final session = await previews.start(cardPreviewMedia(), token);
      engines.single.errors.add(
        const PlayerFailure(PlayerFailureKind.nativePlayback, 'failed', 1),
      );
      await previews.stop();
      expect(token.isCancelled, true);
      expect(session?.closed, true);
      await previews.close();
      expect(
        await previews.start(cardPreviewMedia(), RequestCancellation()),
        isNull,
      );
      expect(engines.length, 1);
    },
  );

  test('explicit video preview does not depend on companion audio', () async {
    final media = cardPreviewMedia();
    final missingAudio = PlaybackMedia(
      video: media.video,
      audio: null,
      quality: media.quality,
      qualities: media.qualities,
      duration: media.duration,
      headers: media.headers,
    );
    expect(
      await previews.start(missingAudio, RequestCancellation()),
      isNotNull,
    );
    expect(engines.single.source, isA<DashVideoSource>());
  });

  test(
    'opening failure without a backup releases the native engine once',
    () async {
      final engine = CardFakeEngine()..opening = Completer<void>();
      final manager = VideoCardPreviewPlayback(createEngine: () => engine);
      addTearDown(manager.close);
      final token = RequestCancellation();
      final pending = manager.start(cardPreviewMedia(), token);
      await Future<void>.delayed(Duration.zero);
      engine.opening!.completeError(
        const PlayerFailure(PlayerFailureKind.nativePlayback, 'failed', 1),
      );
      expect(await pending, isNull);
      expect(token.isCancelled, true);
      expect(engine.stops, 1);
      expect(engine.disposals, 1);
    },
  );

  test(
    'open failure event retains hover and tries the backup video without audio',
    () async {
      // The first open emits the same failure event/future pair as native open.
      final first = CardFakeEngine()..opening = Completer<void>();
      final manager = VideoCardPreviewPlayback(
        createEngine: () {
          final engine = engines.isEmpty ? first : CardFakeEngine();
          engines.add(engine);
          return engine;
        },
      );
      addTearDown(manager.close);
      final hover = RequestCancellation();
      final result = manager.start(cardPreviewMedia(backups: true), hover);
      await Future<void>.delayed(Duration.zero);
      const failure = PlayerFailure(
        PlayerFailureKind.nativePlayback,
        'failed',
        1,
      );
      first.errors.add(failure);
      expect(hover.isCancelled, false);
      first.opening!.completeError(failure);
      final session = await result;
      expect(session, isNotNull);
      expect(engines, hasLength(2));
      expect(first.disposals, 1);
      final source = engines.last.source as DashVideoSource;
      expect(source.video.uri.host, 'backup.example.com');
      expect(engines.last.options?.volume, 0);
      expect(hover.isCancelled, false);
    },
  );

  test('stalled open times out, releases before backup and ignores late completion', () async {
    final first = CardFakeEngine()..opening = Completer<void>();
    final second = CardFakeEngine();
    var created = 0;
    final manager = VideoCardPreviewPlayback(
      openTimeout: const Duration(milliseconds: 20),
      createEngine: () {
        if (created++ == 0) return first;
        expect(first.disposals, 1);
        return second;
      },
    );
    addTearDown(manager.close);
    final session = await manager.start(
      cardPreviewMedia(backups: true),
      RequestCancellation(),
    );
    expect(session?.engine, same(second));
    expect(first.stops, 1);
    first.opening!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(first.currentSnapshot.phase, PlaybackPhase.disposed);
    expect(second.currentSnapshot.desiredPlaying, true);
  });

  test(
    'leaving while failed primary releases prevents backup creation',
    () async {
      final first = CardFakeEngine()
        ..opening = Completer<void>()
        ..releasing = Completer<void>();
      var created = 0;
      final manager = VideoCardPreviewPlayback(
        createEngine: () {
          created++;
          return first;
        },
      );
      addTearDown(manager.close);
      final token = RequestCancellation();
      final pending = manager.start(cardPreviewMedia(backups: true), token);
      await Future<void>.delayed(Duration.zero);
      first.opening!.completeError(
        const PlayerFailure(PlayerFailureKind.nativePlayback, 'failed', 1),
      );
      await Future<void>.delayed(Duration.zero);
      token.cancel();
      first.releasing!.complete();
      expect(await pending, isNull);
      expect(created, 1);
      expect(first.disposals, 1);
    },
  );

  test('confirmed dispose after failed stop allows later previews', () async {
    final first = await previews.start(
      cardPreviewMedia(),
      RequestCancellation(),
    );
    engines.single.stopFailure = const PlayerFailure(
      PlayerFailureKind.nativePlayback,
      'failed',
      1,
    );
    await previews.stop();
    expect(first?.closed, true);
    expect(engines.single.disposals, 1);
    expect(
      await previews.start(cardPreviewMedia(), RequestCancellation()),
      isNotNull,
    );
    expect(engines, hasLength(2));
  });

  test(
    'uses the third distinct video URL and never exceeds three attempts',
    () async {
      final base = cardPreviewMedia();
      final media = PlaybackMedia(
        video: PlaybackTrack(
          urls: [
            for (var i = 0; i < 4; i++)
              Uri.parse('https://cdn$i.example/video'),
          ],
          codec: base.video.codec,
          bandwidth: base.video.bandwidth,
        ),
        audio: null,
        quality: base.quality,
        qualities: base.qualities,
        duration: base.duration,
        headers: base.headers,
      );
      final created = <CardFakeEngine>[];
      final manager = VideoCardPreviewPlayback(
        createEngine: () {
          final engine = CardFakeEngine()..opening = Completer<void>();
          created.add(engine);
          scheduleMicrotask(
            () => engine.opening!.completeError(
              const PlayerFailure(
                PlayerFailureKind.nativePlayback,
                'failed',
                1,
              ),
            ),
          );
          return engine;
        },
      );
      addTearDown(manager.close);
      expect(await manager.start(media, RequestCancellation()), isNull);
      expect(created, hasLength(3));
      expect(
        (created.last.source as DashVideoSource).video.uri.host,
        'cdn2.example',
      );
      expect(created.every((engine) => engine.disposals == 1), true);
    },
  );

  test('uncertain dispose still blocks overlapping native engines', () async {
    await previews.start(cardPreviewMedia(), RequestCancellation());
    engines.single.disposeFailure = const PlayerFailure(
      PlayerFailureKind.nativePlayback,
      'failed',
      1,
    );
    await previews.stop();
    expect(
      await previews.start(cardPreviewMedia(), RequestCancellation()),
      isNull,
    );
    expect(engines, hasLength(1));
  });
}
