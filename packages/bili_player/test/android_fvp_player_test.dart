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
