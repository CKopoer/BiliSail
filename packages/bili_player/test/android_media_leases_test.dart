import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bili_player/src/android_media_leases.dart';
import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/native_readiness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.bilisail/download_storage');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'openMedia') {
            final count = calls.where((c) => c.method == 'openMedia').length;
            return {'lease': 'lease$count', 'fd': 40 + count};
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test(
    'video and external audio keep distinct leases until disposal',
    () async {
      final leases = AndroidMediaLeases();
      final video = await leases.open(
        MediaTrack(
          uri: Uri.parse('content://media/external/downloads/1'),
          requestPolicy: MediaRequestPolicy(),
        ),
      );
      final audio = await leases.open(
        MediaTrack(
          uri: Uri.parse('content://media/external/downloads/2'),
          requestPolicy: MediaRequestPolicy(),
        ),
      );
      expect(video.uri.toString(), 'fd://41');
      expect(audio.uri.toString(), 'fd://42');
      expect(calls.where((c) => c.method == 'closeMedia'), isEmpty);
      await leases.close();
      await leases.close();
      expect(
        calls
            .where((c) => c.method == 'closeMedia')
            .map((c) => c.arguments['lease']),
        ['lease1', 'lease2'],
      );
    },
  );

  test('private media needs no Android channel', () async {
    final leases = AndroidMediaLeases();
    final track = MediaTrack(
      uri: Uri.file('/private/video.mp4'),
      requestPolicy: MediaRequestPolicy(),
    );
    expect(await leases.open(track), same(track));
    await leases.close();
    expect(calls, isEmpty);
  });
  test(
    'close waits for a pending provider lease and releases its late descriptor',
    () async {
      final reply = Completer<Map<String, Object>>();
      final closed = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'openMedia') return reply.future;
            if (call.method == 'closeMedia') {
              closed.add((call.arguments as Map)['lease'] as String);
            }
            return null;
          });
      final leases = AndroidMediaLeases();
      final opened = expectLater(
        leases.open(
          MediaTrack(
            uri: Uri.parse('content://provider/video'),
            requestPolicy: MediaRequestPolicy(),
          ),
        ),
        throwsA(isA<SourceSuperseded>()),
      );
      var done = false;
      final closing = leases.close().then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(done, false);
      reply.complete({'fd': 42, 'lease': 'late'});
      await Future.wait([opened, closing]);
      expect(closed, ['late']);
    },
  );
}
