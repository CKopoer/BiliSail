import 'package:bili_player/src/fvp_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('paired native buffer', () {
    test('intersects endpoints rather than remaining durations', () {
      expect(
        fvpBufferedMilliseconds(
          position: 10000,
          buffered: 10000,
          audioPosition: 9800,
          audioBuffered: 10100,
        ),
        9900,
      );
      expect(
        fvpBufferedMilliseconds(
          position: 10000,
          buffered: 10000,
          audioPosition: 10200,
          audioBuffered: 9900,
        ),
        10000,
      );
    });

    test('supports a single track and empty or invalid native queues', () {
      expect(fvpBufferedMilliseconds(position: 10000, buffered: 3000), 3000);
      expect(fvpBufferedMilliseconds(position: -1, buffered: -1), 0);
      expect(
        fvpBufferedMilliseconds(
          position: 10000,
          buffered: 3000,
          audioPosition: 9000,
          audioBuffered: 0,
        ),
        0,
      );
    });
  });

  group('fvp buffer display', () {
    late FvpBufferDisplay display;
    setUp(() => display = FvpBufferDisplay());
    Duration sample(int position, int end, {bool buffering = false}) =>
        display.update(
          position: Duration(milliseconds: position),
          buffered: Duration(milliseconds: end),
          buffering: buffering,
        );

    test('suppresses small decoder queue jitter and accepts new data', () {
      expect(sample(10000, 20000), const Duration(seconds: 20));
      expect(sample(10250, 19920), const Duration(seconds: 20));
      expect(sample(10500, 19980), const Duration(seconds: 20));
      expect(sample(10750, 20500), const Duration(milliseconds: 20500));
    });

    test('does not accumulate small decreases into an unbounded maximum', () {
      sample(10000, 20000);
      sample(10250, 19800);
      expect(sample(10500, 19600), const Duration(milliseconds: 19600));
      expect(sample(10750, 18000), const Duration(seconds: 18));
    });

    test(
      'shows native buffering and empty or nearly empty queues immediately',
      () {
        sample(10000, 20000);
        expect(
          sample(10250, 19920, buffering: true),
          const Duration(milliseconds: 19920),
        );
        sample(19600, 20000);
        expect(sample(19750, 19920), const Duration(milliseconds: 19920));
        expect(sample(19800, 19800), const Duration(milliseconds: 19800));
      },
    );

    test('backward positions and seek resets discard previous evidence', () {
      sample(10000, 20000);
      expect(sample(9900, 19920), const Duration(milliseconds: 19920));
      display.reset();
      expect(sample(10000, 19800), const Duration(milliseconds: 19800));
    });
  });
}
