import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('fsplayer.test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final track = MediaTrack(
    uri: Uri.parse('https://example.com/v.mp4'),
    requestPolicy: MediaRequestPolicy(),
  );
  final source = DashPairSource(
    video: track,
    audio: track,
    duration: const Duration(seconds: 180),
  );
  late List<String> calls;
  late Map<String, Object?> status;
  late FsPlayerEngine engine;
  Completer<void>? creation, seek;
  int id = 0;

  setUp(() {
    calls = [];
    creation = seek = null;
    status = {
      'prepared': true,
      'videoFrame': true,
      'audioDecoded': true,
      'width': 320,
      'height': 180,
      'seekDone': true,
      'positionMs': 1000,
      'decoder': 'mediacodec',
      'output': 'Vulkan / Flutter.Texture',
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'create') {
        await creation?.future;
        return {'id': ++id, 'texture': id};
      }
      if (call.method == 'status') {
        if (seek != null) await seek!.future;
        return status;
      }
      return null;
    });
    engine = FsPlayerEngine(channel: channel);
  });
  tearDown(() async {
    if (creation != null && !creation!.isCompleted) creation!.complete();
    if (seek != null && !seek!.isCompleted) seek!.complete();
    await engine.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('one core primes silently and honors paused open', () async {
    await engine.open(
      source,
      const OpenOptions(play: false, rate: 2, volume: 37),
    );
    expect(calls.where((s) => s == 'create'), hasLength(1));
    expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
    expect(engine.currentSnapshot.desiredPlaying, isFalse);
    expect(engine.currentSnapshot.rate, 2);
    expect(engine.currentSnapshot.volume, 37);
    final info = await engine.inspectPlaybackInformation();
    expect(info?.diagnostics?.hasDecodedAudio, isTrue);
    expect(info?.backend, startsWith('fsplayer'));
  });
  test(
    'new source waits for native disposal before creating another core',
    () async {
      await engine.open(source, const OpenOptions());
      calls.clear();
      await engine.open(source, const OpenOptions(play: true));
      expect(calls.indexOf('dispose'), lessThan(calls.indexOf('create')));
      expect(engine.currentSnapshot.desiredPlaying, isTrue);
    },
  );
  test('stop during native creation releases the late runtime', () async {
    creation = Completer<void>();
    final opening = engine.open(source, const OpenOptions(play: true));
    while (!calls.contains('create')) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    final stopping = engine.stop();
    creation!.complete();
    await Future.wait([opening, stopping]);
    expect(calls.where((s) => s == 'dispose'), hasLength(1));
    expect(engine.currentSnapshot.phase, PlaybackPhase.idle);
  });
  test('manual pause during seek prevents automatic resume', () async {
    await engine.open(source, const OpenOptions(play: true));
    seek = Completer<void>();
    final seeking = engine.seek(const Duration(seconds: 10));
    while (!engine.currentSnapshot.isSeeking) {
      await Future<void>.delayed(Duration.zero);
    }
    await engine.pause();
    seek!.complete();
    await seeking;
    expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
    expect(engine.currentSnapshot.desiredPlaying, isFalse);
  });
  test('native failure is classified without leaking native text', () async {
    status['error'] = 'https://private/?token=secret';
    await expectLater(
      engine.open(source, const OpenOptions()),
      throwsA(
        isA<PlayerFailure>().having(
          (e) => e.message,
          'sanitized',
          isNot(contains('secret')),
        ),
      ),
    );
    expect(calls, contains('dispose'));
    expect(engine.currentSnapshot.phase, PlaybackPhase.failed);
  });
  test(
    'dispose is idempotent and invalid source creates no native player',
    () async {
      await expectLater(
        engine.open(
          DashPairSource(video: track, audio: null),
          const OpenOptions(),
        ),
        throwsA(isA<PlayerFailure>()),
      );
      expect(calls, isEmpty);
      await engine.dispose();
      await engine.dispose();
      await expectLater(
        engine.open(source, const OpenOptions()),
        throwsA(isA<PlayerFailure>()),
      );
    },
  );
}
