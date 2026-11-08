import 'package:bili_player/src/fvp_surface_preroll.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a pre-binding renderer success cannot confirm the direct Surface',
    () async {
      final frame = FvpFirstVideoFrame()..rendered(true);
      var ready = false;
      final waiting = frame
          .ready(directSurface: true)
          .then((_) => ready = true);
      await Future<void>.delayed(Duration.zero);
      expect(ready, false);
      frame.surfaceConsumed();
      await waiting;
      expect(ready, true);
    },
  );

  test(
    'renderer failure and duplicate callbacks do not poison direct output',
    () async {
      final frame = FvpFirstVideoFrame()..rendered(false);
      frame.surfaceConsumed();
      frame.surfaceConsumed();
      frame.rendered(true);
      expect(await frame.ready(directSurface: true), true);
      expect(await frame.ready(directSurface: false), false);
    },
  );

  test('Surface consumption cannot replace renderer readiness', () async {
    final frame = FvpFirstVideoFrame()..surfaceConsumed();
    var ready = false;
    final waiting = frame.ready(directSurface: false).then((_) => ready = true);
    await Future<void>.delayed(Duration.zero);
    expect(ready, false);
    frame.rendered(true);
    await waiting;
    expect(ready, true);
  });
}
