import 'package:flutter/scheduler.dart';

/// Flutter app timing, not decoded video FPS or physical presentation timing.
final class PlayerFrameSample {
  PlayerFrameSample.fromTimings(
    List<FrameTiming> timings, {
    required this.windowMs,
    this.discarded = 0,
  }) {
    frames = timings.length;
    final builds = timings.map((f) => f.buildDuration.inMicroseconds).toList()
      ..sort();
    final rasters = timings.map((f) => f.rasterDuration.inMicroseconds).toList()
      ..sort();
    double percentile(List<int> values) =>
        values.isEmpty ? 0 : values[((values.length * .95).ceil() - 1)] / 1000;
    buildP95Ms = percentile(builds);
    rasterP95Ms = percentile(rasters);
    rasterMaxMs = rasters.isEmpty ? 0 : rasters.last / 1000;
    rasterOver16Ms = rasters.where((us) => us > 16667).length;
  }

  final int windowMs, discarded;
  late final int frames, rasterOver16Ms;
  late final double buildP95Ms, rasterP95Ms, rasterMaxMs;

  Map<String, Object> toJson() => {
    'scope': 'flutterApp',
    'windowMs': windowMs,
    'frames': frames,
    'discardedTimingSamples': discarded,
    'buildP95Ms': buildP95Ms,
    'rasterP95Ms': rasterP95Ms,
    'rasterMaxMs': rasterMaxMs,
    'rasterOver16Ms': rasterOver16Ms,
  };
}

/// Bounded timing aggregation. Multiple windows/players share Flutter's timing
/// feed, so the result deliberately does not claim per-video GPU attribution.
final class FlutterPlaybackDiagnostics {
  FlutterPlaybackDiagnostics() {
    SchedulerBinding.instance.addTimingsCallback(_record);
  }
  final _clock = Stopwatch()..start();
  final _timings = <FrameTiming>[];
  int _discarded = 0;

  void _record(List<FrameTiming> timings) {
    for (final timing in timings) {
      if (_timings.length < 240) {
        _timings.add(timing);
      } else {
        _discarded++;
      }
    }
  }

  PlayerFrameSample take() {
    final sample = PlayerFrameSample.fromTimings(
      _timings,
      windowMs: _clock.elapsedMilliseconds,
      discarded: _discarded,
    );
    _timings.clear();
    _discarded = 0;
    _clock.reset();
    return sample;
  }

  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_record);
    _timings.clear();
    _clock.stop();
  }
}
