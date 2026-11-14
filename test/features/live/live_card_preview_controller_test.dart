import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/live/application/live_card_preview_controller.dart';
import 'package:bilisail/features/live/domain/live_room.dart';
import 'package:bilisail/features/playback/application/card_preview_playback.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/live_card_preview_fakes.dart';
import '../../support/video_card_fake_engine.dart';

void main() {
  late LivePreviewFakeRepository repository;
  late CardPreviewPlayback playback;
  late LiveCardPreviewController controller;
  late List<CardFakeEngine> engines;
  setUp(() {
    repository = LivePreviewFakeRepository();
    engines = [];
    playback = CardPreviewPlayback(
      createEngine: () {
        final engine = CardFakeEngine();
        engines.add(engine);
        return engine;
      },
    );
    controller = LiveCardPreviewController(
      repository: repository,
      playback: playback,
    );
  });
  tearDown(() async {
    controller.dispose();
    await playback.close();
  });

  test(
    'prefers AVC fMP4, opens muted live source with bounded buffer',
    () async {
      repository.info = LivePlayInfo(
        roomId: const RoomId('12'),
        isLive: true,
        streams: [
          livePreviewStream(format: 'flv'),
          livePreviewStream(codec: 'hevc'),
          livePreviewStream(),
        ],
      );
      final token = RequestCancellation();
      expect(await controller.preview(const RoomId('12'), token), isNotNull);
      final engine = engines.single;
      final source = engine.source as ManifestSource;
      expect(source.isLive, isTrue);
      expect(source.media.codec, 'avc');
      expect(
        source.media.uri.toString(),
        'https://cdn0.bilivideo.com/live/avc.fmp4?token=a%2Fb&v=1',
      );
      expect(
        source.media.requestPolicy.headers['Referer'],
        'https://live.bilibili.com/',
      );
      expect(engine.options?.volume, 0);
      expect(engine.options?.play, isTrue);
      expect(engine.options?.openTimeout, const Duration(seconds: 3));
      expect(engine.options?.maxBufferAhead, const Duration(seconds: 5));
      token.cancel();
      await playback.stop();
      expect(engine.disposals, 1);
    },
  );

  test('FLV fallback retains live semantics', () async {
    repository.info = LivePlayInfo(
      roomId: const RoomId('12'),
      isLive: true,
      streams: [livePreviewStream(format: 'flv')],
    );
    await controller.preview(const RoomId('12'), RequestCancellation());
    expect((engines.single.source as ProgressiveSource).isLive, isTrue);
  });

  for (final invalidation in [
    'cancel',
    'scope',
    'epoch',
    'dispose',
    'new room',
  ]) {
    test('late response after $invalidation never starts an engine', () async {
      repository.pending = Completer<LivePlayInfo>();
      final token = RequestCancellation();
      final pending = controller.preview(const RoomId('12'), token);
      switch (invalidation) {
        case 'cancel':
          token.cancel();
        case 'scope':
          repository.accountScope = 'user:42';
        case 'epoch':
          repository.sessionEpoch++;
        case 'dispose':
          controller.dispose();
        case 'new room':
          final newer = controller.preview(
            const RoomId('13'),
            RequestCancellation(),
          );
          controller.dispose();
          expect(token.isCancelled, isTrue);
          unawaited(newer);
      }
      repository.pending!.complete(repository.info);
      expect(await pending, isNull);
      expect(engines, isEmpty);
    });
  }

  test(
    'offline, empty, invalid and cancelled requests do not open players',
    () async {
      await controller.preview(const RoomId('0'), RequestCancellation());
      await controller.preview(
        const RoomId('12'),
        RequestCancellation()..cancel(),
      );
      expect(repository.rooms, isEmpty);
      for (final live in [false, true]) {
        repository.info = LivePlayInfo(
          roomId: const RoomId('12'),
          isLive: live,
          streams: [],
        );
        expect(
          await controller.preview(const RoomId('12'), RequestCancellation()),
          isNull,
        );
      }
      expect(engines, isEmpty);
    },
  );

  test('read failure cancels the optional preview', () async {
    repository.failure = const AppFailure(AppFailureKind.network, 'offline');
    final token = RequestCancellation();
    await expectLater(
      controller.preview(const RoomId('12'), token),
      throwsA(isA<AppFailure>()),
    );
    expect(token.isCancelled, isTrue);
    expect(engines, isEmpty);
  });

  test(
    'video to live transition waits for release and cancels the video',
    () async {
      final videoToken = RequestCancellation();
      await playback.start(cardPreviewMedia(), videoToken);
      final first = engines.single..releasing = Completer<void>();
      final next = controller.preview(
        const RoomId('12'),
        RequestCancellation(),
      );
      await Future<void>.delayed(Duration.zero);
      expect(videoToken.isCancelled, isTrue);
      expect(engines, hasLength(1));
      first.releasing!.complete();
      expect(await next, isNotNull);
      expect(first.disposals, 1);
      expect(engines.last.source, isA<ManifestSource>());
      final liveToken = repository.tokens.single;
      await playback.start(cardPreviewMedia(), RequestCancellation());
      expect(liveToken.isCancelled, isTrue);
      expect(engines[1].disposals, 1);
      expect(engines.last.source, isA<DashVideoSource>());
    },
  );

  test(
    'failed live URLs try at most three addresses after releasing each',
    () async {
      repository.info = LivePlayInfo(
        roomId: const RoomId('12'),
        isLive: true,
        streams: [livePreviewStream(urls: 5)],
      );
      var active = 0;
      final manager = CardPreviewPlayback(
        createEngine: () {
          expect(engines.every((e) => e.disposals == 1), isTrue);
          final engine = CardFakeEngine()..opening = Completer<void>();
          engines.add(engine);
          active++;
          scheduleMicrotask(
            () => engine.opening!.completeError(
              const PlayerFailure(
                PlayerFailureKind.nativePlayback,
                'unavailable',
                1,
              ),
            ),
          );
          return engine;
        },
      );
      addTearDown(manager.close);
      final resolver = LiveCardPreviewController(
        repository: repository,
        playback: manager,
      );
      addTearDown(resolver.dispose);
      expect(
        await resolver.preview(const RoomId('12'), RequestCancellation()),
        isNull,
      );
      expect(active, 3);
      expect(engines.every((e) => e.disposals == 1), isTrue);
    },
  );
}
