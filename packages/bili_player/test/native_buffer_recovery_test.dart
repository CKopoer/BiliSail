import 'dart:async';
import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/native_buffer_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const playing = PlaybackSnapshot(
    generation: 1,
    phase: PlaybackPhase.playing,
    desiredPlaying: true,
    position: Duration(seconds: 10),
    buffered: Duration(seconds: 90),
    duration: Duration(minutes: 10),
  );
  late PlaybackSnapshot snapshot;
  late NativeBufferRecovery recovery;
  late int probes, recoveries, cancellations;
  late bool online;
  late List<NativeBufferRecoveryReason> reasons;
  setUp(() {
    snapshot = playing;
    probes = recoveries = cancellations = 0;
    online = false;
    reasons = [];
    recovery = NativeBufferRecovery(
      snapshot: () => snapshot,
      probe: () async {
        probes++;
        return online;
      },
      cancelProbe: () => cancellations++,
      onRecoveryRequired: (reason) {
        reasons.add(reason);
        recoveries++;
      },
    );
  });
  tearDown(() => recovery.dispose());

  for (final message in [
    'stream 0, offset 0x1234: partial file',
    'root atom offset 0x1234: partial file',
    'Stream ends prematurely at 100, should be 200',
    'Failed to open segment 3 of playlist 0',
    'Failed to reload playlist 0',
    'TLS certificate verification failed',
    'HTTP error 403 Forbidden',
    'Connection reset by peer',
    'Connection timed out',
    'Input/output error',
    'Error in the pull function',
  ]) {
    test(
      'media read error recovers while cached playback advances: $message',
      () {
        recovery.readingChanged(false, endOfInput: true);
        snapshot = snapshot.copyWith(position: const Duration(seconds: 15));
        recovery.update();
        final error = NativeErrorSummary.classify(
          message,
          prefix: 'ffmpeg/demuxer',
        );
        recovery.reportError(error);
        expect(recoveries, 1);
        expect(reasons, [NativeBufferRecoveryReason.readError]);
        expect(probes, 0);
        expect(snapshot.position, lessThan(snapshot.buffered));
        recovery.reportError(error);
        expect(
          recoveries,
          1,
          reason: 'Duplicate SDK events share one recovery',
        );
      },
    );
  }

  for (final message in [
    'Packet corrupt (stream = 0)',
    'Non-monotonous DTS in output stream',
    'Consider trying --profile=fast and/or --hwdec=auto',
    'Property not found',
    'No such file',
    'Failed to open audio device',
    'Unrecognized diagnostic message',
  ]) {
    test(
      'unrelated diagnostics do not become media read failures: $message',
      () {
        recovery.readingChanged(false);
        recovery.reportError(NativeErrorSummary.classify(message));
        expect(recoveries, 0);
        expect(probes, 0);
      },
    );
  }

  for (final buffering in [false, true]) {
    test('confirmed prefetch error retries before cache drain: $buffering', () {
      snapshot = snapshot.copyWith(
        phase: buffering ? PlaybackPhase.buffering : PlaybackPhase.playing,
        isBuffering: buffering,
      );
      // No reachability probe is needed, even when the old origin is offline.
      recovery.reportNetworkError(immediate: true);
      expect(recoveries, 1);
      expect(reasons, [NativeBufferRecoveryReason.readError]);
      expect(probes, 0);
      expect(snapshot.position, lessThan(snapshot.buffered));
      recovery.reportNetworkError(immediate: true);
      recovery.readingChanged(false, endOfInput: true);
      expect(recoveries, 1);
    });
  }

  test(
    'a confirmed error during an empty buffering state retries immediately',
    () {
      snapshot = snapshot.copyWith(
        phase: PlaybackPhase.buffering,
        isBuffering: true,
        buffered: snapshot.position,
      );
      recovery.reportNetworkError(immediate: true);
      expect(recoveries, 1);
      expect(probes, 0);
    },
  );

  testWidgets('an immediate retry cancels an in-flight silent-stall probe', (
    tester,
  ) async {
    recovery.dispose();
    final result = Completer<bool>();
    recovery = NativeBufferRecovery(
      snapshot: () => snapshot,
      probe: () {
        probes++;
        return result.future;
      },
      cancelProbe: () => cancellations++,
      onRecoveryRequired: (_) => recoveries++,
    );
    recovery.reportNetworkError();
    await tester.pump(const Duration(seconds: 5));
    expect(probes, 1);
    recovery.reportNetworkError(immediate: true);
    expect(recoveries, 1);
    result.complete(true);
    await tester.pump();
    expect(recoveries, 1);
  });

  for (final action in ['pause', 'seek', 'ended', 'full', 'dispose']) {
    test(
      'confirmed error does not restart an inactive/full source: $action',
      () {
        switch (action) {
          case 'pause':
            snapshot = snapshot.copyWith(desiredPlaying: false);
          case 'seek':
            snapshot = snapshot.copyWith(isSeeking: true);
          case 'ended':
            snapshot = snapshot.copyWith(phase: PlaybackPhase.ended);
          case 'full':
            snapshot = snapshot.copyWith(buffered: snapshot.duration);
          case 'dispose':
            recovery.dispose();
        }
        recovery.reportNetworkError(immediate: true);
        expect(recoveries, 0);
        expect(probes, 0);
      },
    );
  }

  testWidgets(
    'playing packets remain eligible before native cache time arrives',
    (tester) async {
      snapshot = snapshot.copyWith(buffered: snapshot.position);
      recovery.readingChanged(true);
      online = true;
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      expect(recoveries, 1);
    },
  );

  testWidgets('input EOF alone leaves cached playback to the native player', (
    tester,
  ) async {
    recovery.readingChanged(false, endOfInput: true);
    expect(recoveries, 0);
    expect(probes, 0);
    await tester.pump(const Duration(seconds: 5));
    snapshot = snapshot.copyWith(position: const Duration(seconds: 15));
    recovery.readingChanged(false, endOfInput: true);
    online = true;
    await tester.pump(const Duration(seconds: 5));
    expect(recoveries, 0);
  });

  for (final reading in [false, true]) {
    testWidgets('unequal DASH tails do not request recovery: $reading', (
      tester,
    ) async {
      snapshot = playing.copyWith(
        position: const Duration(milliseconds: 19633),
        duration: const Duration(milliseconds: 140500),
        buffered: const Duration(milliseconds: 139853),
        rate: 2,
      );
      recovery.readingChanged(reading, endOfInput: true);
      online = true;
      await tester.pump(const Duration(minutes: 1));
      expect(recoveries, 0);
      expect(probes, 0);
    });
  }

  testWidgets(
    'input EOF with unknown duration does not probe a healthy origin',
    (tester) async {
      snapshot = playing.copyWith(duration: Duration.zero);
      recovery.readingChanged(false, endOfInput: true);
      online = true;
      await tester.pump(const Duration(minutes: 1));
      expect(recoveries, 0);
      expect(probes, 0);
    },
  );

  testWidgets('input EOF cancels an unresolved silent-read probe', (
    tester,
  ) async {
    recovery.dispose();
    final result = Completer<bool>();
    recovery = NativeBufferRecovery(
      snapshot: () => snapshot,
      probe: () {
        probes++;
        return result.future;
      },
      cancelProbe: () => cancellations++,
      onRecoveryRequired: (_) => recoveries++,
    );
    recovery.readingChanged(true);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    expect(probes, 1);
    recovery.readingChanged(false, endOfInput: true);
    result.complete(true);
    await tester.pump(const Duration(minutes: 1));
    expect(recoveries, 0);
    expect(cancellations, greaterThan(0));
  });

  testWidgets('normal EOF cannot use a stale SDK buffer to request recovery', (
    tester,
  ) async {
    recovery.readingChanged(false, endOfInput: true);
    online = true;
    await tester.pump(const Duration(seconds: 10));
    expect(recoveries, 0);
    expect(probes, 0);
    expect(snapshot.buffered, const Duration(seconds: 90));
  });

  test('a real network error after input EOF still requests recovery once', () {
    recovery.readingChanged(false, endOfInput: true);
    recovery.reportNetworkError(immediate: true);
    recovery.reportNetworkError(immediate: true);
    expect(recoveries, 1);
    expect(probes, 0);
  });

  testWidgets('blocked native prefetch is detected without an error log', (
    tester,
  ) async {
    recovery.readingChanged(true);
    await tester.pump(const Duration(seconds: 5));
    snapshot = snapshot.copyWith(position: const Duration(seconds: 15));
    recovery.update();
    online = true;
    await tester.pump(const Duration(seconds: 5));
    expect(recoveries, 1);
    expect(snapshot.position, lessThan(snapshot.buffered));
    expect(reasons, [NativeBufferRecoveryReason.stalledRead]);
  });

  testWidgets(
    'native idle backpressure does not probe or reopen a full cache',
    (tester) async {
      recovery.readingChanged(true);
      await tester.pump(const Duration(seconds: 4));
      recovery.readingChanged(false);
      online = true;
      await tester.pump(const Duration(seconds: 10));
      expect(probes, 0);
      recovery.readingChanged(true);
      await tester.pump(const Duration(seconds: 4));
      snapshot = snapshot.copyWith(buffered: const Duration(seconds: 95));
      recovery.update();
      recovery.readingChanged(false);
      await tester.pump(const Duration(seconds: 10));
      expect(probes, 0);
    },
  );

  testWidgets('native idle cancels an already armed silent-read episode', (
    tester,
  ) async {
    addTearDown(() => recovery.dispose());
    recovery.readingChanged(true);
    await tester.pump(const Duration(seconds: 5));
    // The read deadline has elapsed, but native then reports cache backpressure
    // before the reachability probe. This is no longer a blocked read.
    recovery.readingChanged(false);
    online = true;
    await tester.pump(const Duration(seconds: 10));
    expect(probes, 0);
    expect(recoveries, 0);
    recovery.reportNetworkError(immediate: true);
    expect(recoveries, 1);
    expect(reasons, [NativeBufferRecoveryReason.readError]);
  });

  testWidgets('native idle retires a late successful silent-read probe', (
    tester,
  ) async {
    addTearDown(() => recovery.dispose());
    recovery.dispose();
    final result = Completer<bool>();
    recovery = NativeBufferRecovery(
      snapshot: () => snapshot,
      probe: () {
        probes++;
        return result.future;
      },
      cancelProbe: () => cancellations++,
      onRecoveryRequired: (_) => recoveries++,
    );
    recovery.readingChanged(true);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    expect(probes, 1);
    recovery.readingChanged(false);
    result.complete(true);
    await tester.pump();
    expect(recoveries, 0);
    // A later real read stall still has its own observation window.
    recovery.readingChanged(true);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    expect(recoveries, 1);
  });

  testWidgets('backward seek discards the previous cache high-water mark', (
    tester,
  ) async {
    addTearDown(() => recovery.dispose());
    recovery.readingChanged(true);
    snapshot = snapshot.copyWith(
      isSeeking: true,
      buffered: const Duration(seconds: 40),
      position: const Duration(seconds: 20),
    );
    recovery.update();
    snapshot = snapshot.copyWith(isSeeking: false);
    recovery.update();
    online = true;
    // This healthy endpoint remains below the old 90-second cache. Its growth
    // must restart the observation window, rather than inherit the seek's timer.
    await tester.pump(const Duration(seconds: 3));
    snapshot = snapshot.copyWith(buffered: const Duration(seconds: 43));
    recovery.update();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 2));
    expect(probes, 0);
    expect(recoveries, 0);
    snapshot = snapshot.copyWith(buffered: const Duration(seconds: 46));
    recovery.update();
    recovery.dispose();
  });

  testWidgets('prefetch recovers before cached playback runs out', (
    tester,
  ) async {
    recovery.reportNetworkError();
    await tester.pump(const Duration(seconds: 5));
    expect(probes, 1);
    expect(recoveries, 0);
    snapshot = snapshot.copyWith(position: const Duration(seconds: 15));
    recovery.update();
    online = true;
    await tester.pump(const Duration(seconds: 5));
    expect(probes, 2);
    expect(recoveries, 1);
    expect(snapshot.position, lessThan(snapshot.buffered));
  });

  testWidgets('native cache growth cancels recovery; position alone does not', (
    tester,
  ) async {
    recovery.reportNetworkError();
    snapshot = snapshot.copyWith(position: const Duration(seconds: 11));
    recovery.update();
    await tester.pump(const Duration(seconds: 5));
    expect(probes, 1);
    snapshot = snapshot.copyWith(buffered: const Duration(seconds: 91));
    recovery.update();
    online = true;
    await tester.pump(const Duration(seconds: 10));
    expect(probes, 1);
    expect(recoveries, 0);
  });

  testWidgets('repeated errors do not extend the two minute budget', (
    tester,
  ) async {
    recovery.reportNetworkError();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(seconds: 5));
      recovery.reportNetworkError();
    }
    final count = probes;
    expect(count, greaterThan(0));
    expect(count, lessThanOrEqualTo(NativeBufferRecovery.maximumAttempts));
    online = true;
    await tester.pump(const Duration(seconds: 10));
    expect(probes, count);
    expect(recoveries, 0);
    snapshot = snapshot.copyWith(buffered: const Duration(seconds: 92));
    recovery.update();
    recovery.reportNetworkError();
    await tester.pump(const Duration(seconds: 5));
    expect(recoveries, 1);
  });

  testWidgets('single flight and late results are cancelled on cache growth', (
    tester,
  ) async {
    recovery.dispose();
    final result = Completer<bool>();
    recovery = NativeBufferRecovery(
      snapshot: () => snapshot,
      probe: () {
        probes++;
        return result.future;
      },
      cancelProbe: () => cancellations++,
      onRecoveryRequired: (_) => recoveries++,
    );
    recovery.reportNetworkError();
    await tester.pump(const Duration(seconds: 5));
    recovery.reportNetworkError();
    await tester.pump(const Duration(seconds: 20));
    expect(probes, 1);
    snapshot = snapshot.copyWith(buffered: const Duration(seconds: 100));
    recovery.update();
    result.complete(true);
    await tester.pump();
    expect(recoveries, 0);
    expect(cancellations, greaterThan(0));
  });

  for (final action in ['pause', 'seek', 'dispose', 'ended', 'full', 'empty']) {
    testWidgets('$action cancels pending prefetch recovery', (tester) async {
      recovery.reportNetworkError();
      switch (action) {
        case 'pause':
          snapshot = snapshot.copyWith(desiredPlaying: false);
        case 'seek':
          snapshot = snapshot.copyWith(isSeeking: true);
        case 'dispose':
          recovery.dispose();
        case 'ended':
          snapshot = snapshot.copyWith(phase: PlaybackPhase.ended);
        case 'full':
          snapshot = snapshot.copyWith(buffered: snapshot.duration);
        case 'empty':
          snapshot = snapshot.copyWith(
            buffered: snapshot.position,
            phase: PlaybackPhase.buffering,
          );
      }
      recovery.update();
      online = true;
      await tester.pump(const Duration(seconds: 6));
      expect(probes, 0);
      expect(recoveries, 0);
    });
  }

  test(
    'media probe uses bounded ranges and checks both DASH origins',
    () async {
      final paths = <String>[];
      var status = 206;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        expect(request.headers.value('range'), 'bytes=0-0');
        expect(request.headers.value('referer'), 'https://example.test/');
        paths.add(request.uri.path);
        request.response.statusCode = status;
        request.response.contentLength = 1;
        request.response.add([0]);
        await request.response.close();
      });
      final probe = NativeMediaProbe([
        for (final path in ['/video', '/audio'])
          MediaTrack(
            uri: Uri.parse('http://127.0.0.1:${server.port}$path?sign=private'),
            requestPolicy: MediaRequestPolicy(
              headers: {'Referer': 'https://example.test/'},
            ),
          ),
      ]);
      try {
        expect(
          await HttpOverrides.runWithHttpOverrides(
            probe.check,
            _NetworkOverrides(),
          ),
          true,
        );
        expect(paths, ['/video', '/audio']);
        status = 503;
        expect(
          await HttpOverrides.runWithHttpOverrides(
            probe.check,
            _NetworkOverrides(),
          ),
          false,
        );
        status = 403;
        expect(
          await HttpOverrides.runWithHttpOverrides(
            probe.check,
            _NetworkOverrides(),
          ),
          true,
          reason: 'Expired URLs need session resolution',
        );
      } finally {
        probe.cancel();
        await server.close(force: true);
      }
    },
  );

  test(
    'probe does not follow redirects and cancels stalled responses',
    () async {
      final requestArrived = Completer<void>();
      var redirect = true;
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests++;
        if (redirect) {
          request.response.statusCode = 302;
          request.response.headers.set('Location', '/other');
          await request.response.close();
        } else if (!requestArrived.isCompleted) {
          requestArrived.complete();
        }
      });
      final probe = NativeMediaProbe([
        MediaTrack(
          uri: Uri.parse('http://127.0.0.1:${server.port}/video'),
          requestPolicy: MediaRequestPolicy(),
        ),
      ]);
      try {
        expect(
          await HttpOverrides.runWithHttpOverrides(
            probe.check,
            _NetworkOverrides(),
          ),
          true,
        );
        expect(requests, 1);
        redirect = false;
        final pending = HttpOverrides.runWithHttpOverrides(
          probe.check,
          _NetworkOverrides(),
        );
        await requestArrived.future;
        probe.cancel();
        expect(await pending, false);
      } finally {
        probe.cancel();
        await server.close(force: true);
      }
    },
  );
}

final class _NetworkOverrides extends HttpOverrides {}
