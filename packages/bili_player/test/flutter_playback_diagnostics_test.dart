import 'dart:ui';

import 'package:bili_player/src/flutter_playback_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

FrameTiming timing(int buildMs, int rasterMs) => FrameTiming(
  vsyncStart: 0,
  buildStart: 0,
  buildFinish: buildMs * 1000,
  rasterStart: buildMs * 1000,
  rasterFinish: (buildMs + rasterMs) * 1000,
  rasterFinishWallTime: (buildMs + rasterMs) * 1000,
);

void main() {
  test(
    'frame timing aggregation uses milliseconds and does not claim video FPS',
    () {
      final sample = PlayerFrameSample.fromTimings([
        for (var i = 1; i <= 20; i++) timing(i, i * 2),
      ], windowMs: 500);
      expect(sample.frames, 20);
      expect(sample.buildP95Ms, 19);
      expect(sample.rasterP95Ms, 38);
      expect(sample.rasterMaxMs, 40);
      expect(sample.rasterOver16Ms, 12);
      expect(sample.toJson()['scope'], 'flutterApp');
      expect(sample.toJson().containsKey('fps'), isFalse);
    },
  );

  testWidgets('timing storage is bounded, resets per window and detaches', (
    tester,
  ) async {
    final collector = FlutterPlaybackDiagnostics();
    tester.binding.platformDispatcher.onReportTimings?.call([
      for (var i = 0; i < 260; i++) timing(1, 2),
    ]);
    final sample = collector.take();
    expect(sample.frames, 240);
    expect(sample.discarded, 20);
    expect(collector.take().frames, 0);
    collector.dispose();
    tester.binding.platformDispatcher.onReportTimings?.call([timing(1, 2)]);
    expect(collector.take().frames, 0);
  });
}
