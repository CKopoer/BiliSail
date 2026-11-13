import 'dart:async';

import 'package:bili_player/src/native_rate_audio.dart';
import 'package:bili_player/src/native_readiness.dart';
import 'package:flutter_test/flutter_test.dart';

const _original = {
  'audio-buffer': '0.200000',
  'af': '',
  'autosync': '0',
  'video-sync': 'display-resample',
};
const _responsive = {
  'audio-buffer': '0.05',
  'af': 'scaletempo2',
  'autosync': '30',
  'video-sync': 'audio',
};

void main() {
  test(
    'prepares both rate directions while preserving network and gain',
    () async {
      final values = {
        ..._original,
        'cache-secs': '120',
        'volume': '35',
        'replaygain-fallback': '3',
      };
      final policy = NativeRateAudio(
        write: (key, value) async => values[key] = value,
        read: (key) async => values[key] ?? '',
      );
      await policy.configure(
        enabled: true,
        isCurrent: () => true,
        timeout: const Duration(seconds: 2),
      );
      expect(values, {
        ..._responsive,
        'cache-secs': '120',
        'volume': '35',
        'replaygain-fallback': '3',
      });
      // A second VOD must not capture the first VOD's policy as its defaults.
      await policy.configure(
        enabled: true,
        isCurrent: () => true,
        timeout: const Duration(seconds: 2),
      );
      for (var cycle = 0; cycle < 2; cycle++) {
        await policy.configure(
          enabled: false,
          isCurrent: () => true,
          timeout: const Duration(seconds: 2),
        );
        expect(values, {
          ..._original,
          'cache-secs': '120',
          'volume': '35',
          'replaygain-fallback': '3',
        });
        await policy.configure(
          enabled: true,
          isCurrent: () => true,
          timeout: const Duration(seconds: 2),
        );
        expect(values['autosync'], '30');
        expect(values['af'], 'scaletempo2');
      }
    },
  );

  test(
    'live and silent sources on a fresh player keep native defaults',
    () async {
      final policy = NativeRateAudio(
        write: (_, _) async => fail('Unexpected write'),
        read: (_) async => throw StateError('Unexpected read'),
      );
      await policy.configure(
        enabled: false,
        isCurrent: () => true,
        timeout: const Duration(seconds: 2),
      );
    },
  );

  test(
    'validation autosync override is verified and restored on reuse',
    () async {
      final values = {..._original};
      final policy = NativeRateAudio(
        write: (key, value) async => values[key] = value,
        read: (key) async => values[key] ?? '',
      );
      await policy.configure(
        enabled: true,
        isCurrent: () => true,
        timeout: const Duration(seconds: 2),
        experimentalAutosync: 0,
      );
      expect(values, {..._responsive, 'autosync': '0'});
      await policy.configure(
        enabled: false,
        isCurrent: () => true,
        timeout: const Duration(seconds: 2),
      );
      expect(values, _original);
    },
  );

  for (final restore in [false, true]) {
    for (final rejected in _responsive.keys) {
      test(
        'rejects ignored $rejected writes when restoring=$restore',
        () async {
          final values = {..._original};
          var reject = !restore;
          final policy = NativeRateAudio(
            write: (key, value) async {
              if (reject && key == rejected) return;
              values[key] = value;
            },
            read: (key) async => values[key] ?? '',
          );
          if (restore) {
            await policy.configure(
              enabled: true,
              isCurrent: () => true,
              timeout: const Duration(seconds: 2),
            );
            reject = true;
          }
          await expectLater(
            policy.configure(
              enabled: !restore,
              isCurrent: () => true,
              timeout: const Duration(seconds: 2),
            ),
            throwsStateError,
          );
        },
      );
    }
  }

  test('accepts normalized numeric readback', () async {
    final values = {..._original};
    final policy = NativeRateAudio(
      write: (key, value) async => values[key] = value,
      read: (key) async {
        final value = values[key] ?? '';
        return double.tryParse(value)?.toStringAsFixed(6) ?? value;
      },
    );
    await policy.configure(
      enabled: true,
      isCurrent: () => true,
      timeout: const Duration(seconds: 2),
    );
  });

  // Four original reads plus four write/read pairs, including the final read.
  for (var supersedeAfter = 0; supersedeAfter <= 12; supersedeAfter++) {
    test('cancellation stops after operation $supersedeAfter', () async {
      final values = {..._original};
      var operations = 0;
      final policy = NativeRateAudio(
        write: (key, value) async {
          operations++;
          values[key] = value;
        },
        read: (key) async {
          operations++;
          return values[key] ?? '';
        },
      );
      await expectLater(
        policy.configure(
          enabled: true,
          isCurrent: () => operations < supersedeAfter,
          timeout: const Duration(seconds: 2),
        ),
        throwsA(isA<SourceSuperseded>()),
      );
      expect(operations, supersedeAfter);
    });
  }

  testWidgets('late write after timeout cannot continue configuration', (
    tester,
  ) async {
    final gate = Completer<void>();
    var reads = 0;
    var writes = 0;
    final policy = NativeRateAudio(
      write: (_, _) {
        writes++;
        return gate.future;
      },
      read: (key) async {
        reads++;
        return _original[key] ?? '';
      },
    );
    final checked = expectLater(
      policy.configure(
        enabled: true,
        isCurrent: () => true,
        timeout: const Duration(seconds: 2),
      ),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await checked;
    gate.complete();
    await tester.pump();
    expect(reads, 4);
    expect(writes, 1);
  });
}
