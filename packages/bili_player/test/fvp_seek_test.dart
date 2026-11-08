import 'dart:async';

import 'package:bili_player/src/fvp_seek.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final code in [-2, -3, -8]) {
    test('restores an EOF race ($code) before confirming the target', () async {
      final paused = Completer<bool>();
      final calls = <String>[];
      var seeks = 0;
      final result = seekFvpTarget(
        isCancelled: () => false,
        needsPrepare: () => false,
        prepare: () async {
          calls.add('prepare');
          return 9000;
        },
        pauseAndWait: () {
          calls.add('pause');
          return seeks == 0 ? Future.value(true) : paused.future;
        },
        seek: () async {
          calls.add('seek');
          return seeks++ == 0 ? code : 9375;
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['pause', 'seek', 'prepare', 'pause']);
      paused.complete(true);
      expect(await result, 9375);
      expect(calls.last, 'seek');
    });
  }

  test(
    'EOF during pause restores the source instead of waiting forever',
    () async {
      var prepared = false;
      expect(
        await seekFvpTarget(
          isCancelled: () => false,
          needsPrepare: () => false,
          prepare: () async {
            prepared = true;
            return 2000;
          },
          pauseAndWait: () async => prepared,
          seek: () async => 2000,
        ),
        2000,
      );
      expect(prepared, true);
    },
  );

  test(
    'an EOF during a restored seek receives a fresh bounded prepare',
    () async {
      var preparations = 0;
      var seeks = 0;
      expect(
        await seekFvpTarget(
          isCancelled: () => false,
          needsPrepare: () => true,
          prepare: () async {
            preparations++;
            return 2000;
          },
          pauseAndWait: () async => true,
          seek: () async => seeks++ == 0 ? -3 : 2000,
        ),
        2000,
      );
      expect(preparations, 2);
      expect(seeks, 2);
    },
  );

  for (final boundary in ['prepare', 'pause', 'seek']) {
    test(
      'superseding during $boundary cannot issue another native command',
      () async {
        var cancelled = false;
        var seeks = 0;
        expect(
          await seekFvpTarget(
            isCancelled: () => cancelled,
            needsPrepare: () => boundary == 'prepare',
            prepare: () async {
              cancelled = true;
              return 2000;
            },
            pauseAndWait: () async {
              if (boundary == 'pause') cancelled = true;
              return true;
            },
            seek: () async {
              seeks++;
              cancelled = true;
              return -3;
            },
          ),
          -2,
        );
        expect(seeks, boundary == 'seek' ? 1 : 0);
      },
    );
  }

  test('a rejected native seek restores the source once', () async {
    var seeks = 0;
    var preparations = 0;
    expect(
      await seekFvpTarget(
        isCancelled: () => false,
        needsPrepare: () => false,
        prepare: () async {
          preparations++;
          return 2000;
        },
        pauseAndWait: () async => true,
        seek: () async => seeks++ == 0 ? -10 : 2000,
      ),
      2000,
    );
    expect(preparations, 1);
    expect(seeks, 2);
  });

  test('an interrupted HTTP prepare is retired and retried once', () async {
    var preparations = 0;
    expect(
      await seekFvpTarget(
        isCancelled: () => false,
        needsPrepare: () => true,
        prepare: () async => preparations++ == 0 ? -8 : 325000,
        pauseAndWait: () async => true,
        seek: () async => 325000,
      ),
      325000,
    );
    expect(preparations, 2);
  });

  for (final code in [-1, -2, -3, -4, -8, -10]) {
    test('failure $code has a bounded recovery budget', () async {
      var preparations = 0;
      var seeks = 0;
      expect(
        await seekFvpTarget(
          isCancelled: () => false,
          needsPrepare: () => false,
          prepare: () async {
            preparations++;
            return 2000;
          },
          pauseAndWait: () async => true,
          seek: () async {
            seeks++;
            return code;
          },
        ),
        code,
      );
      expect(preparations, {-2, -3, -8, -10}.contains(code) ? 1 : 0);
      expect(seeks, preparations + 1);
    });
  }
}
