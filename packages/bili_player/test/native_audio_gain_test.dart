import 'dart:async';

import 'package:bili_player/src/native_audio_gain.dart';
import 'package:bili_player/src/native_readiness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a new source clears gain inherited from a reused player', () async {
    final values = <String, String>{};
    NativeAudioGain sourceControl() => NativeAudioGain(
      write: (key, value) async => values[key] = value,
      read: (key) async => values[key] ?? '',
      isCurrent: () => true,
    );
    final previous = sourceControl();
    await previous.apply(8, smooth: false);
    previous.cancel();
    await sourceControl().apply(0, smooth: false);
    expect(values['replaygain-fallback'], '0.0');
  });
  test(
    'native gain preserves user volume and ramps to exact targets',
    () async {
      final values = <String, String>{
        'volume': '35',
        'replaygain-fallback': '0',
      };
      final gains = <double>[];
      final delays = <Duration>[];
      final control = NativeAudioGain(
        write: (key, value) async {
          values[key] = value;
          if (key == 'replaygain-fallback') gains.add(double.parse(value));
        },
        read: (key) async => values[key] ?? '',
        isCurrent: () => true,
        delay: (duration) async {
          delays.add(duration);
        },
      );
      await control.apply(2.7, smooth: false);
      expect(gains, [2.7]);
      expect(delays, isEmpty);
      expect(values['replaygain'], 'no');
      await control.apply(-7.3);
      expect(gains.length, 10);
      for (var i = 1; i < gains.length; i++) {
        expect(gains[i], lessThan(gains[i - 1]));
      }
      expect(gains.last, -7.3);
      expect(delays.length, 9);
      await control.apply(0);
      expect(control.gainDb, 0);
      expect(values['volume'], '35');
    },
  );
  test('readback detects silent property errors', () async {
    final control = NativeAudioGain(
      write: (_, value) async {},
      read: (key) async => key == 'replaygain' ? 'no' : '0',
      isCurrent: () => true,
    );
    await expectLater(control.apply(3, smooth: false), throwsStateError);
    expect(control.gainDb, 0);
  });
  for (final cancel in [false, true]) {
    test(
      'source replacement or cancellation prevents later writes: $cancel',
      () async {
        final gate = Completer<void>();
        var current = true;
        final writes = <String>[];
        final control = NativeAudioGain(
          write: (key, value) async {
            writes.add(key);
          },
          read: (key) async => key == 'replaygain' ? 'no' : '0',
          isCurrent: () => current,
          delay: (_) => gate.future,
        );
        final operation = control.apply(5);
        final checked = expectLater(
          operation,
          throwsA(isA<SourceSuperseded>()),
        );
        await Future<void>.delayed(Duration.zero);
        if (cancel) {
          control.cancel();
        } else {
          current = false;
        }
        gate.complete();
        await checked;
        expect(writes, ['replaygain']);
      },
    );
  }
  testWidgets('timed out ramp cannot write when its pending delay ends', (
    tester,
  ) async {
    final gate = Completer<void>();
    final writes = <String>[];
    final control = NativeAudioGain(
      write: (key, value) async {
        writes.add(key);
      },
      read: (key) async => key == 'replaygain' ? 'no' : '0',
      isCurrent: () => true,
      delay: (_) => gate.future,
    );
    final checked = expectLater(
      control.apply(5),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await checked;
    gate.complete();
    await tester.pump();
    expect(writes, ['replaygain']);
    expect(control.gainDb, 0);
  });
  test('rejects non-finite and excessive gain before native calls', () {
    final control = NativeAudioGain(
      write: (_, _) async => fail('write'),
      read: (_) async => '',
      isCurrent: () => true,
    );
    for (final value in [double.nan, double.infinity, -61.0, 31.0]) {
      expect(() => control.apply(value), throwsArgumentError);
    }
  });
}
