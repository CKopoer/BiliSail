import 'dart:async';

import 'package:bili_player/src/native_playback_policy.dart';
import 'package:bili_player/src/native_readiness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final android in [false, true]) {
    for (final curl in ['', 'yes', 'no']) {
      test(
        'Android=$android curl=$curl uses PiliPlus playback policy',
        () async {
          final values = {
            'curl-enabled': curl,
            'video-sync': 'audio',
            'autosync': '0',
            'ao': 'opensles',
            'hr-seek': 'yes',
            'hr-seek-framedrop': 'no',
            'cache-on-disk': 'yes',
            'audio-buffer': '0.200000',
            'af': '',
            'vd-queue-enable': 'no',
            'volume': '35',
          };
          final writes = <String>[];
          await configureNativePlaybackPolicy(
            isAndroid: android,
            write: (key, value) async {
              writes.add(key);
              values[key] = value;
            },
            read: (key) async => values[key] ?? '',
            isCurrent: () => true,
            timeout: const Duration(seconds: 2),
          );
          expect(values['curl-enabled'], curl.isEmpty ? '' : 'no');
          expect(writes.contains('curl-enabled'), curl.isNotEmpty);
          expect(values['stream-lavf-o'], 'rw_timeout=5000000');
          expect(values['video-sync'], 'display-resample');
          expect(values['autosync'], android ? '30' : '0');
          expect(
            values['ao'],
            android ? 'opensles,aaudio,audiotrack' : 'opensles',
          );
          expect(values['hr-seek'], 'default');
          expect(values['hr-seek-framedrop'], 'yes');
          expect(values['cache-on-disk'], 'no');
          expect(values['audio-buffer'], '0.200000');
          expect(values['af'], isEmpty);
          expect(values['vd-queue-enable'], 'no');
          expect(values['volume'], '35');
        },
      );
    }
  }

  test('ignored native writes fail instead of silently using curl', () async {
    await expectLater(
      configureNativePlaybackPolicy(
        isAndroid: false,
        write: (_, _) async {},
        read: (_) async => 'yes',
        isCurrent: () => true,
        timeout: const Duration(seconds: 2),
      ),
      throwsStateError,
    );
  });

  test('source cancellation prevents subsequent native commands', () async {
    var active = true;
    final writes = <String>[];
    await expectLater(
      configureNativePlaybackPolicy(
        isAndroid: false,
        write: (key, _) async => writes.add(key),
        read: (_) async {
          active = false;
          return 'yes';
        },
        isCurrent: () => active,
        timeout: const Duration(seconds: 2),
      ),
      throwsA(isA<SourceSuperseded>()),
    );
    expect(writes, isEmpty);
  });

  test('capability inspection shares the configuration deadline', () async {
    await expectLater(
      configureNativePlaybackPolicy(
        isAndroid: false,
        write: (_, _) async {},
        read: (_) => Completer<String>().future,
        isCurrent: () => true,
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('cancellation during a write prevents the next native read', () async {
    var active = true;
    final reads = <String>[];
    await expectLater(
      configureNativePlaybackPolicy(
        isAndroid: false,
        write: (_, _) async => active = false,
        read: (key) async {
          reads.add(key);
          return 'yes';
        },
        isCurrent: () => active,
        timeout: const Duration(seconds: 2),
      ),
      throwsA(isA<SourceSuperseded>()),
    );
    expect(reads, ['curl-enabled']);
  });
}
