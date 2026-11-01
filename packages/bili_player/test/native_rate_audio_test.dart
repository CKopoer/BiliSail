import 'dart:async';

import 'package:bili_player/src/native_readiness.dart';
import 'package:bili_player/src/native_rate_audio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'prepares responsive rate audio without changing network buffer or gain',
    () async {
      final properties = <String, String>{
        'volume': '35',
        'replaygain-fallback': '3',
        'cache-secs': '300',
        'cache-pause-wait': '2',
      };
      final operations = <String>[];
      await configureNativeRateAudio(
        write: (key, value) async {
          operations.add('write:$key=$value');
          properties[key] = value;
        },
        read: (key) async {
          operations.add('read:$key');
          return properties[key] ?? '';
        },
        isCurrent: () => true,
        timeout: const Duration(seconds: 2),
      );
      expect(operations, [
        'write:audio-buffer=0.05',
        'read:audio-buffer',
        'write:af=scaletempo2',
        'read:af',
      ]);
      expect(properties['volume'], '35');
      expect(properties['replaygain-fallback'], '3');
      expect(properties['cache-secs'], '300');
      expect(properties['cache-pause-wait'], '2');
      expect(
        properties.keys,
        unorderedEquals([
          'volume',
          'replaygain-fallback',
          'cache-secs',
          'cache-pause-wait',
          'audio-buffer',
          'af',
        ]),
      );
    },
  );

  test('accepts normalized output buffer readback', () async {
    await configureNativeRateAudio(
      write: (_, _) async {},
      read: (key) async => key == 'audio-buffer' ? '0.050000' : 'scaletempo2',
      isCurrent: () => true,
      timeout: const Duration(seconds: 2),
    );
  });

  for (final applied in ['', '0.2', '0', 'NaN', 'invalid']) {
    test(
      'rejects an unapplied output buffer before installing filters: $applied',
      () async {
        final writes = <String>[];
        await expectLater(
          configureNativeRateAudio(
            write: (key, _) async => writes.add(key),
            read: (_) async => applied,
            isCurrent: () => true,
            timeout: const Duration(seconds: 2),
          ),
          throwsStateError,
        );
        expect(writes, ['audio-buffer']);
      },
    );
  }

  for (final applied in ['', 'scaletempo', 'other']) {
    test('rejects an unapplied tempo filter: $applied', () async {
      await expectLater(
        configureNativeRateAudio(
          write: (_, _) async {},
          read: (key) async => key == 'audio-buffer' ? '0.050000' : applied,
          isCurrent: () => true,
          timeout: const Duration(seconds: 2),
        ),
        throwsStateError,
      );
    });
  }

  for (var supersedeAfter = 0; supersedeAfter <= 4; supersedeAfter++) {
    test(
      'source replacement stops rate preparation after operation $supersedeAfter',
      () async {
        var current = supersedeAfter != 0;
        final operations = <String>[];
        void record(String operation) {
          operations.add(operation);
          if (operations.length == supersedeAfter) current = false;
        }

        await expectLater(
          configureNativeRateAudio(
            write: (key, _) async {
              record('write:$key');
            },
            read: (key) async {
              record('read:$key');
              return key == 'audio-buffer' ? '0.05' : 'scaletempo2';
            },
            isCurrent: () => current,
            timeout: const Duration(seconds: 2),
          ),
          throwsA(isA<SourceSuperseded>()),
        );
        expect(operations.length, supersedeAfter);
      },
    );
  }

  testWidgets('a timed out preparation cannot continue after a late write', (
    tester,
  ) async {
    final gate = Completer<void>();
    var reads = 0;
    final checked = expectLater(
      configureNativeRateAudio(
        write: (_, _) => gate.future,
        read: (_) async {
          reads++;
          return 'scaletempo2';
        },
        isCurrent: () => true,
        timeout: const Duration(seconds: 2),
      ),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump(const Duration(seconds: 2));
    await checked;
    gate.complete();
    await tester.pump();
    expect(reads, 0);
  });

  test('buffer and filter preparation share one deadline', () async {
    final operations = <String>[];
    await expectLater(
      configureNativeRateAudio(
        write: (key, _) async {
          operations.add('write:$key');
          await Future<void>.delayed(const Duration(milliseconds: 300));
        },
        read: (key) async {
          operations.add('read:$key');
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return key == 'audio-buffer' ? '0.05' : 'scaletempo2';
        },
        isCurrent: () => true,
        timeout: const Duration(milliseconds: 500),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(
      operations,
      anyOf(
        equals(['write:audio-buffer']),
        equals(['write:audio-buffer', 'read:audio-buffer']),
      ),
    );
  });
}
