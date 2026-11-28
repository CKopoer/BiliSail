import 'dart:async';

import 'package:bili_player/android_audio_output.dart';
import 'package:bili_player/src/native_playback_policy.dart';
import 'package:bili_player/src/native_readiness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('changing the driver or an active OpenSL mode reloads once', () async {
    final properties = {
      'ao': 'opensles,aaudio,audiotrack',
      'current-ao': 'opensles',
      'opensles-performance-mode': 'LATENCY',
    };
    final changes = <String>[];
    Future<void> apply(
      AndroidAudioDriver driver,
      OpenSlPerformanceMode mode,
    ) async {
      changes.clear();
      await applyAndroidAudioOutput(
        (driver: driver, mode: mode),
        read: (k) => properties[k]!,
        write: (k, v) {
          properties[k] = v;
          changes.add('$k=$v');
        },
        reload: () async => changes.add('reload'),
      );
    }

    await apply(AndroidAudioDriver.auto, OpenSlPerformanceMode.latency);
    expect(changes, isEmpty);
    await apply(AndroidAudioDriver.auto, OpenSlPerformanceMode.none);
    expect(changes, ['opensles-performance-mode=NONE', 'reload']);
    for (final driver in [
      AndroidAudioDriver.aaudio,
      AndroidAudioDriver.audiotrack,
      AndroidAudioDriver.opensles,
      AndroidAudioDriver.auto,
    ]) {
      await apply(driver, OpenSlPerformanceMode.powerSaving);
      expect(changes.last, 'ao=${driver.mpvValue}');
      expect(changes, isNot(contains('reload')));
    }
    properties['current-ao'] = 'aaudio';
    await apply(AndroidAudioDriver.auto, OpenSlPerformanceMode.latencyEffects);
    expect(changes, ['opensles-performance-mode=LATENCY_EFFECTS']);
  });

  for (final platform in ['android', 'macos', 'other']) {
    final android = platform == 'android';
    for (final curl in ['', 'yes', 'no']) {
      test(
        '$platform curl=$curl applies transport, sync and audio output policy',
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
            isMacOS: platform == 'macos',
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
          expect(values['audio-format'], platform == 'macos' ? 'float' : null);
          expect(writes, isNot(contains('audio-samplerate')));
          expect(writes, isNot(contains('audio-spdif')));
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
        isMacOS: false,
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
        isMacOS: false,
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
        isMacOS: false,
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
        isMacOS: false,
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
