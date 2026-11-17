import 'dart:async';
import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/native_readiness.dart';
import 'package:bili_player/src/native_video_frame_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final isAndroid in [true, false]) {
    test(
      'Android=$isAndroid keeps native queue defaults without an override',
      () {
        expect(
          resolveVideoFrameQueueEnabled(
            isAndroid: isAndroid,
            buildOverride: '',
          ),
          false,
        );
        expect(
          resolveVideoFrameQueueEnabled(
            isAndroid: isAndroid,
            buildOverride: 'invalid',
          ),
          false,
        );
      },
    );

    for (final enabled in [true, false]) {
      test('build flag=$enabled overrides Android=$isAndroid', () {
        expect(
          resolveVideoFrameQueueEnabled(
            isAndroid: isAndroid,
            buildOverride: enabled.toString(),
          ),
          enabled,
        );
        expect(
          resolveVideoFrameQueueEnabled(
            isAndroid: isAndroid,
            enabledOverride: !enabled,
            buildOverride: enabled.toString(),
          ),
          !enabled,
        );
      });
    }
  }

  test(
    'compiled build flag reaches the engine and platform default policy',
    () async {
      const flag = String.fromEnvironment('BILISAIL_VIDEO_FRAME_QUEUE');
      for (final isAndroid in [true, false]) {
        final expected = switch (flag) {
          'true' => true,
          'false' => false,
          _ => false,
        };
        expect(resolveVideoFrameQueueEnabled(isAndroid: isAndroid), expected);
      }
      final engine = MediaKitEngine();
      expect(
        engine.experimentalVideoFrameQueue,
        resolveVideoFrameQueueEnabled(isAndroid: Platform.isAndroid),
      );
      await engine.dispose();
      for (final enabled in [true, false]) {
        final overridden = MediaKitEngine(experimentalVideoFrameQueue: enabled);
        expect(overridden.experimentalVideoFrameQueue, enabled);
        await overridden.dispose();
      }
    },
  );

  test('verifies bounded limits before enabling the video queue', () async {
    final values = <String, String>{};
    final writes = <String>[];
    await configureNativeVideoFrameQueue(
      write: (key, value) async {
        values[key] = value;
        writes.add(key);
        if (key == 'vd-queue-enable') {
          expect(values['vd-queue-max-samples'], '8');
          expect(values['vd-queue-max-secs'], '0.1');
          expect(values['vd-queue-max-bytes'], '67108864');
        }
      },
      read: (key) async =>
          key == 'vd-queue-max-secs' ? '0.100000' : values[key] ?? '',
      isCurrent: () => true,
      timeout: const Duration(seconds: 1),
    );
    expect(writes.last, 'vd-queue-enable');
    expect(values['vd-queue-enable'], 'yes');
    expect(writes, isNot(contains('hwdec')));
    expect(writes, isNot(contains('ad-queue-enable')));
  });

  for (final rejectedKey in nativeVideoFrameQueueProperties.keys) {
    test('native rejection of $rejectedKey fails the experiment', () async {
      final values = <String, String>{};
      final writes = <String>[];
      await expectLater(
        configureNativeVideoFrameQueue(
          write: (key, value) async {
            values[key] = value;
            writes.add(key);
          },
          read: (key) async => key == rejectedKey ? 'no' : values[key] ?? '',
          isCurrent: () => true,
          timeout: const Duration(seconds: 1),
        ),
        throwsStateError,
      );
      expect(writes.last, rejectedKey);
    });
  }

  test('superseding the source prevents later property calls', () async {
    var current = true;
    final calls = <String>[];
    await expectLater(
      configureNativeVideoFrameQueue(
        write: (key, value) async {
          calls.add('write:$key');
          current = false;
        },
        read: (key) async {
          calls.add('read:$key');
          return '';
        },
        isCurrent: () => current,
        timeout: const Duration(seconds: 1),
      ),
      throwsA(isA<SourceSuperseded>()),
    );
    expect(calls, ['write:vd-queue-max-samples']);
  });

  test('expired budget prevents native calls', () async {
    await expectLater(
      configureNativeVideoFrameQueue(
        write: (_, _) async => fail('write after deadline'),
        read: (_) async => fail('read after deadline'),
        isCurrent: () => true,
        timeout: Duration.zero,
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  testWidgets('a timed out read cannot enable the queue later', (tester) async {
    final pending = Completer<String>();
    final writes = <String>[];
    final checked = expectLater(
      configureNativeVideoFrameQueue(
        write: (key, value) async => writes.add(key),
        read: (_) => pending.future,
        isCurrent: () => true,
        timeout: const Duration(seconds: 1),
      ),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await checked;
    pending.complete('8');
    await tester.pump();
    expect(writes, ['vd-queue-max-samples']);
  });
}
