import 'dart:async';

import 'package:bili_player/src/native_readiness.dart';
import 'package:bili_player/src/native_tempo_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'prepares persistent pitch correction without changing volume or gain',
    () async {
      final properties = <String, String>{
        'volume': '35',
        'replaygain-fallback': '3',
      };
      final operations = <String>[];
      await configureNativeTempoFilter(
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
      expect(operations, ['write:af=scaletempo2', 'read:af']);
      expect(properties['volume'], '35');
      expect(properties['replaygain-fallback'], '3');
      expect(
        properties.keys,
        unorderedEquals(['volume', 'replaygain-fallback', 'af']),
      );
    },
  );

  for (final applied in ['', 'scaletempo', 'other']) {
    test('rejects an unapplied tempo filter: $applied', () async {
      await expectLater(
        configureNativeTempoFilter(
          write: (_, _) async {},
          read: (_) async => applied,
          isCurrent: () => true,
          timeout: const Duration(seconds: 2),
        ),
        throwsStateError,
      );
    });
  }

  for (final replaceDuringRead in [false, true]) {
    test(
      'source replacement stops tempo preparation during read=$replaceDuringRead',
      () async {
        var current = true;
        final operations = <String>[];
        await expectLater(
          configureNativeTempoFilter(
            write: (_, _) async {
              operations.add('write');
              if (!replaceDuringRead) current = false;
            },
            read: (_) async {
              operations.add('read');
              current = false;
              return 'scaletempo2';
            },
            isCurrent: () => current,
            timeout: const Duration(seconds: 2),
          ),
          throwsA(isA<SourceSuperseded>()),
        );
        expect(operations, replaceDuringRead ? ['write', 'read'] : ['write']);
      },
    );
  }

  testWidgets('a timed out preparation cannot continue after a late write', (
    tester,
  ) async {
    final gate = Completer<void>();
    var reads = 0;
    final checked = expectLater(
      configureNativeTempoFilter(
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
}
