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
  setUp(() {
    snapshot = playing;
    probes = recoveries = cancellations = 0;
    online = false;
    recovery = NativeBufferRecovery(
      snapshot: () => snapshot,
      probe: () async {
        probes++;
        return online;
      },
      cancelProbe: () => cancellations++,
      onReachable: () => recoveries++,
    );
  });
  tearDown(() => recovery.dispose());

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

  testWidgets(
    'premature native input EOF remains armed while cache is consumed',
    (tester) async {
      recovery.readingChanged(false, endOfInput: true);
      await tester.pump(const Duration(seconds: 5));
      snapshot = snapshot.copyWith(position: const Duration(seconds: 15));
      recovery.readingChanged(false, endOfInput: true);
      online = true;
      await tester.pump(const Duration(seconds: 5));
      expect(recoveries, 1);
    },
  );

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
      onReachable: () => recoveries++,
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
