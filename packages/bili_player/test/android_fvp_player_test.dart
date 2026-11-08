import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/android_fvp_player.dart';
import 'package:bili_player/src/fvp_native_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'direct output crosses Binder only for automatic hardware decoding',
    () async {
      final messenger = binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('dev.bilisail/fvp_process/events'),
        (_) async => null,
      );
      final requests = <Map<Object?, Object?>>[];
      messenger.setMockMethodCallHandler(AndroidFvpPlayer.channel, (
        call,
      ) async {
        if (call.method == 'create') return 100;
        if (call.method == 'prepare') {
          requests.add(call.arguments as Map<Object?, Object?>);
          return {'duration': 5000, 'width': 320, 'height': 180, 'audio': true};
        }
        return null;
      });
      final port = await AndroidFvpPlayer.create();
      final activity = port as FvpAudioActivityPort;
      expect(activity.decodedAudioFrames, 0);
      final delivered = Completer<void>();
      messenger.handlePlatformMessage(
        'dev.bilisail/fvp_process/events',
        const StandardMethodCodec().encodeSuccessEnvelope({
          'kind': 'sample',
          'player': 100,
          'position': 1250,
          'buffered': 2000,
          'audioFrames': 47,
        }),
        (_) => delivered.complete(),
      );
      await delivered.future;
      expect(activity.decodedAudioFrames, 47);
      for (final decoding in VideoDecodingMode.values) {
        await port.prepare(
          MediaTrack(
            uri: Uri.parse('file:///public-fixture.mp4'),
            requestPolicy: MediaRequestPolicy(),
          ),
          null,
          OpenOptions(
            videoDecoding: decoding,
            androidVideoOutput: AndroidVideoOutputMode.directTexture,
          ),
          silent: false,
        );
      }
      expect(requests[0]['directSurface'], true);
      expect(requests[1]['directSurface'], false);
      await port.dispose();
      messenger.setMockMethodCallHandler(AndroidFvpPlayer.channel, null);
    },
  );
  test('startup pause waits for the worker acknowledgement', () async {
    final messenger = binding.defaultBinaryMessenger;
    final paused = Completer<void>();
    messenger.setMockMethodCallHandler(AndroidFvpPlayer.channel, (call) async {
      if (call.method == 'create') return 100;
      if (call.method == 'pause') await paused.future;
      return null;
    });
    final port = await AndroidFvpPlayer.create();
    var done = false;
    final waiting = port.pauseAndWait().then((_) => done = true);
    await Future<void>.delayed(Duration.zero);
    expect(done, false);
    paused.complete();
    await waiting;
    expect(done, true);
    await port.dispose();
    messenger.setMockMethodCallHandler(AndroidFvpPlayer.channel, null);
  });
  test(
    'mute, play and rate barriers wait for their worker acknowledgements',
    () async {
      final messenger = binding.defaultBinaryMessenger;
      for (final method in ['volume', 'play', 'rate']) {
        final acknowledged = Completer<void>();
        messenger.setMockMethodCallHandler(AndroidFvpPlayer.channel, (
          call,
        ) async {
          if (call.method == 'create') return 101;
          if (call.method == method) await acknowledged.future;
          return null;
        });
        final player = await AndroidFvpPlayer.create();
        final commands = player as FvpCommandCompletionPort;
        var done = false;
        final waiting = (switch (method) {
          'volume' => commands.setVolumeAndWait(0, -3),
          'play' => commands.playAndWait(),
          _ => commands.setRateAndWait(1.5),
        }).then((_) => done = true);
        await Future<void>.delayed(Duration.zero);
        expect(done, false);
        acknowledged.complete();
        await waiting;
        expect(done, true);
        await player.dispose();
      }
      messenger.setMockMethodCallHandler(AndroidFvpPlayer.channel, null);
    },
  );
  test(
    'pause confirmation returns native evidence from the worker reply',
    () async {
      final messenger = binding.defaultBinaryMessenger;
      for (final confirmed in [false, true]) {
        final reply = Completer<bool>();
        messenger.setMockMethodCallHandler(AndroidFvpPlayer.channel, (
          call,
        ) async {
          if (call.method == 'create') return 102;
          if (call.method == 'pause') return reply.future;
          return null;
        });
        final port = await AndroidFvpPlayer.create();
        var done = false;
        final waiting = (port as FvpPauseConfirmationPort)
            .pauseAndConfirm()
            .then((value) {
              done = true;
              return value;
            });
        await Future<void>.delayed(Duration.zero);
        expect(done, false);
        reply.complete(confirmed);
        expect(await waiting, confirmed);
        await port.dispose();
      }
      messenger.setMockMethodCallHandler(AndroidFvpPlayer.channel, null);
    },
  );

  test('seek confirmation rejects queued samples and EOF from the previous timeline', () async {
    final messenger = binding.defaultBinaryMessenger;
    final seeks = <Completer<int>>[];
    final revisions = <int>[];
    messenger.setMockMethodCallHandler(AndroidFvpPlayer.channel, (call) async {
      if (call.method == 'create') return 100;
      if (call.method == 'seek') {
        revisions.add((call.arguments as Map)['seekRevision'] as int);
        final result = Completer<int>();
        seeks.add(result);
        return result.future;
      }
      return null;
    });
    final port = await AndroidFvpPlayer.create();
    final statuses = <FvpNativeStatus>[];
    final subscription = port.statuses.listen(statuses.add);
    Future<void> sample(int revision, int position, {String? status}) async {
      final delivered = Completer<void>();
      messenger.handlePlatformMessage(
        'dev.bilisail/fvp_process/events',
        const StandardMethodCodec().encodeSuccessEnvelope({
          'kind': status == null ? 'sample' : 'status',
          'player': 100,
          'seekRevision': revision,
          'position': position,
          'status': ?status,
        }),
        (_) => delivered.complete(),
      );
      await delivered.future;
    }

    await sample(0, 11958);
    final seeking = port.seek(const Duration(seconds: 2));
    await Future<void>.delayed(Duration.zero);
    seeks.single.complete(2000);
    await seeking;
    expect(port.positionMilliseconds, 2000);
    await sample(0, 11958, status: 'ended');
    expect(statuses, isEmpty);
    await sample(1, 2000, status: 'buffered');
    expect(statuses, [FvpNativeStatus.buffered]);
    await sample(0, 11958);
    expect(port.positionMilliseconds, 2000);
    await sample(1, 2100);
    expect(port.positionMilliseconds, 2100);
    final old = port.seek(const Duration(seconds: 9));
    final latest = port.seek(const Duration(seconds: 3));
    await Future<void>.delayed(Duration.zero);
    seeks.last.complete(3000);
    await latest;
    seeks[1].complete(9000);
    await old;
    expect(port.positionMilliseconds, 3000);
    expect(revisions, [1, 2, 3]);
    await port.dispose();
    await subscription.cancel();
    messenger.setMockMethodCallHandler(AndroidFvpPlayer.channel, null);
  });
  test('Binder loss rejects pending preparation, retires the port, and allows a new worker', () async {
    final messenger = binding.defaultBinaryMessenger;
    const events = MethodChannel('dev.bilisail/fvp_process/events');
    messenger.setMockMethodCallHandler(events, (_) async => null);
    final preparing = Completer<Object?>();
    final calls = <String>[];
    var nextId = 0;
    messenger.setMockMethodCallHandler(AndroidFvpPlayer.channel, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'create' => ++nextId,
        'prepare' when nextId == 1 => preparing.future,
        'prepare' => {
          'duration': 5000,
          'width': 320,
          'height': 180,
          'audio': true,
        },
        _ => null,
      };
    });
    final port = await AndroidFvpPlayer.create();
    final statuses = <FvpNativeStatus>[];
    final subscription = port.statuses.listen(statuses.add);
    final opening = port.prepare(
      MediaTrack(
        uri: Uri.parse('https://example.com/video'),
        requestPolicy: MediaRequestPolicy(),
      ),
      null,
      const OpenOptions(),
      silent: false,
    );
    final rejected = expectLater(opening, throwsA(isA<FvpProcessException>()));
    preparing.completeError(PlatformException(code: 'native_process_exited'));
    await rejected;
    expect(statuses, [FvpNativeStatus.processExited]);
    port.play();
    port.pause();
    port.interrupt();
    await port.dispose();
    expect(calls, ['create', 'prepare', 'dispose']);
    await subscription.cancel();
    final next = await AndroidFvpPlayer.create();
    final info = await next.prepare(
      MediaTrack(
        uri: Uri.parse('https://example.com/video'),
        requestPolicy: MediaRequestPolicy(),
      ),
      null,
      const OpenOptions(),
      silent: false,
    );
    expect(info.dimensions, const VideoDimensions(320, 180));
    await next.dispose();
    messenger.setMockMethodCallHandler(AndroidFvpPlayer.channel, null);
  });
}
