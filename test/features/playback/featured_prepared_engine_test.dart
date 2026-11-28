import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/playback/application/featured_prepared_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/video_card_fake_engine.dart';

void main() {
  late List<CardFakeEngine> engines;
  late FeaturedPreparedEngine standby;

  setUp(() {
    engines = [];
    standby = FeaturedPreparedEngine(
      createEngine: () => CardFakeEngine()..alsoRecord(engines),
    );
  });
  tearDown(() => standby.clear());

  test(
    'closing another tab leaves the shared standby with its requesting session',
    () async {
      final feed = Object(), other = Object();
      standby.prepare(
        'next',
        (_) async => (source: _dash(), options: const OpenOptions()),
        owner: feed,
      );
      await _turn();
      await standby.clear(owner: other);
      expect(
        standby.take(
          'next',
          _dash(),
          const OpenOptions(),
          RequestCancellation(),
          owner: other,
        ),
        isNull,
      );
      final prepared = await standby.take(
        'next',
        _dash(),
        const OpenOptions(),
        RequestCancellation(),
        owner: feed,
      );
      expect(prepared, same(engines.single));
      await prepared?.dispose();
    },
  );

  test(
    'hands off the exact paused engine without reopening or stopping it',
    () async {
      const foreground = OpenOptions(
        startPosition: Duration(seconds: 2),
        play: true,
        rate: 1.25,
        volume: 41,
        audioGainDb: -4,
        cacheLimits: (forwardMiB: 8, backwardMiB: 4),
      );
      standby.prepare(
        'next',
        (_) async => (source: _dash(), options: foreground),
      );
      await _turn();
      final engine = engines.single;
      expect(engine.options?.play, isFalse);
      expect(engine.options?.volume, 0);
      expect(engine.options?.startPosition, foreground.startPosition);
      expect(engine.options?.rate, foreground.rate);
      expect(engine.options?.audioGainDb, foreground.audioGainDb);
      expect(engine.options?.cacheLimits, foreground.cacheLimits);
      expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
      expect(standby.preview('next'), same(engine));
      expect(standby.preview('next', owner: Object()), isNull);

      final foregroundToken = RequestCancellation();
      final transferred = await standby.take(
        'next',
        _dash(),
        foreground,
        foregroundToken,
      );
      addTearDown(engine.dispose);
      expect(transferred, same(engine));
      expect(standby.preview('next'), isNull);
      expect(engine.opens, 1);
      foregroundToken.cancel();
      await standby.clear();
      expect(engine.stops, 0);
      expect(engine.disposals, 0);
    },
  );

  for (final (description, source, options)
      in <(String, ResolvedMediaSource, OpenOptions)>[
        ('signed URL', _dash(videoQuery: 'changed'), const OpenOptions()),
        (
          'headers',
          _dash(referer: 'https://example.com/other'),
          const OpenOptions(),
        ),
        ('HDR', _dash(hdr: true), const OpenOptions()),
        ('audio codec', _dash(audioCodec: 'ec-3'), const OpenOptions()),
        ('audio track', _dash(silent: true), const OpenOptions()),
        (
          'start position',
          _dash(),
          const OpenOptions(startPosition: Duration(seconds: 1)),
        ),
        ('rate', _dash(), const OpenOptions(rate: 2)),
        (
          'decoder',
          _dash(),
          const OpenOptions(videoDecoding: VideoDecodingMode.software),
        ),
        (
          'Android texture',
          _dash(),
          const OpenOptions(
            androidVideoOutput: AndroidVideoOutputMode.directTexture,
          ),
        ),
        (
          'Android audio device',
          _dash(),
          const OpenOptions(
            androidAudioOutput: (
              driver: AndroidAudioDriver.audiotrack,
              mode: OpenSlPerformanceMode.latency,
            ),
          ),
        ),
        (
          'packet cache',
          _dash(),
          const OpenOptions(cacheLimits: (forwardMiB: 8, backwardMiB: 4)),
        ),
        (
          'cache duration',
          _dash(),
          const OpenOptions(maxBufferAhead: Duration(seconds: 10)),
        ),
      ]) {
    test(
      'does not wait for native teardown on $description mismatch',
      () async {
        standby.prepare(
          'next',
          (_) async => (source: _dash(), options: const OpenOptions()),
        );
        await _turn();
        final engine = engines.single;
        final releasing = engine.releasing = Completer<void>();
        addTearDown(() {
          if (!releasing.isCompleted) releasing.complete();
        });

        expect(
          standby.take('next', source, options, RequestCancellation()),
          isNull,
        );
        expect(engine.stops, 1);
        expect(engine.disposals, 0);
        releasing.complete();
        await standby.clear();
        expect(engine.disposals, 1);
      },
    );
  }

  test('moving ahead while a handoff is in flight waits to allocate the next engine', () async {
    final open = Completer<void>();
    standby = FeaturedPreparedEngine(
      createEngine: () => CardFakeEngine()
        ..opening = engines.isEmpty ? open : null
        ..alsoRecord(engines),
    );
    final source = _dash();
    const options = OpenOptions();
    standby.prepare('first', (_) async => (source: source, options: options));
    await _turn();
    final first = engines.single;
    final claim = standby.take(
      'first',
      source,
      options,
      RequestCancellation(),
    )!;
    standby.prepare('second', (_) async => (source: source, options: options));
    await _turn();
    expect(engines, [first]);

    open.complete();
    expect(await claim, same(first));
    addTearDown(first.dispose);
    await _turn();
    expect(engines, hasLength(2));
    expect(first.stops, 0);
    expect(engines.last.opens, 1);
  });

  test(
    'a slow foreground claim falls back while teardown remains in flight',
    () async {
      final gate = Completer<void>();
      final disposing = Completer<void>();
      standby = FeaturedPreparedEngine(
        createEngine: () => CardFakeEngine()
          ..opening = engines.isEmpty ? gate : null
          ..disposing = engines.isEmpty ? disposing : null
          ..alsoRecord(engines),
        handoffTimeout: const Duration(milliseconds: 5),
      );
      addTearDown(() {
        if (!disposing.isCompleted) disposing.complete();
        if (!gate.isCompleted) gate.complete();
      });
      const options = OpenOptions();
      standby.prepare('slow', (_) async => (source: _dash(), options: options));
      await _turn();
      expect(
        await standby.take('slow', _dash(), options, RequestCancellation()),
        isNull,
      );
      expect(engines.single.stops, 1);
      final closing = standby.clear();
      expect(standby.clear(), same(closing));

      standby.prepare('soon', (_) async => (source: _dash(), options: options));
      await _turn();
      expect(engines, hasLength(1));
      disposing.complete();
      await closing;
      await _turn();
      expect(engines, hasLength(2));
      gate.complete();
    },
  );

  test('clear cancels unresolved metadata without waiting for it', () async {
    final unresolved = Completer<FeaturedEnginePlan>();
    late RequestCancellation token;
    standby.prepare('unresolved', (cancellation) {
      token = cancellation;
      return unresolved.future;
    });
    await standby.clear();
    expect(token.isCancelled, isTrue);
    unresolved.complete((source: _dash(), options: const OpenOptions()));
    await _turn();
    expect(engines, isEmpty);
  });

  test('foreground cancellation interrupts an opening engine', () async {
    final opening = Completer<void>();
    final engine = CardFakeEngine()..opening = opening;
    standby = FeaturedPreparedEngine(createEngine: () => engine);
    const options = OpenOptions();
    standby.prepare('next', (_) async => (source: _dash(), options: options));
    await _turn();
    final token = RequestCancellation();
    final taking = standby.take('next', _dash(), options, token)!;
    token.cancel();
    expect(await taking, isNull);
    await standby.clear();
    expect(engine.stops, 1);
    expect(engine.disposals, 1);
    opening.complete();
  });

  test(
    'expiry cancels a prepared engine and permits ordinary playback',
    () async {
      standby = FeaturedPreparedEngine(
        createEngine: () => CardFakeEngine()..alsoRecord(engines),
        maximumAge: Duration.zero,
      );
      const options = OpenOptions();
      standby.prepare('next', (_) async => (source: _dash(), options: options));
      await _turn();
      expect(
        standby.take('next', _dash(), options, RequestCancellation()),
        isNull,
      );
      await standby.clear();
      expect(engines.single.disposals, 1);
    },
  );

  test('speculative failures discard the engine', () async {
    const options = OpenOptions();
    standby.prepare('next', (_) async => (source: _dash(), options: options));
    await _turn();
    final engine = engines.single;
    engine.errors.add(
      const PlayerFailure(
        PlayerFailureKind.nativePlayback,
        'fixture failure',
        1,
      ),
    );
    expect(
      standby.take('next', _dash(), options, RequestCancellation()),
      isNull,
    );
    await standby.clear();
    expect(engine.disposals, 1);
  });
}

Future<void> _turn() => Future<void>.delayed(Duration.zero);

DashPairSource _dash({
  String videoQuery = 'original',
  String referer = 'https://www.bilibili.com/',
  String audioCodec = 'mp4a',
  bool hdr = false,
  bool silent = false,
}) {
  final policy = MediaRequestPolicy(headers: {'Referer': referer});
  return DashPairSource(
    video: MediaTrack(
      uri: Uri.https('media.example.com', '/video', {'signature': videoQuery}),
      requestPolicy: policy,
      codec: 'avc1',
      isHdr: hdr,
    ),
    audio: silent
        ? null
        : MediaTrack(
            uri: Uri.https('media.example.com', '/audio'),
            requestPolicy: policy,
            codec: audioCodec,
          ),
    isIntentionallySilent: silent,
    duration: const Duration(seconds: 20),
  );
}

extension on CardFakeEngine {
  void alsoRecord(List<CardFakeEngine> engines) => engines.add(this);
}
