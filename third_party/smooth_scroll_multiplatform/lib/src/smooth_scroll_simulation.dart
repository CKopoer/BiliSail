import 'package:flutter/animation.dart';

abstract final class SmoothScrollDefaults {
  static const duration = Duration(milliseconds: 380);
  static const scrollSpeed = 2.0;
  static const curve = Curves.easeOutQuart;
}

/// The interpolation used by DynMouseScroll's animateTo, without owning a list.
/// Retained and nested lists can keep their controllers and cancellation rules.
final class SmoothScrollSimulation extends Simulation {
  SmoothScrollSimulation({
    required this.start,
    required this.end,
    this.duration = SmoothScrollDefaults.duration,
    this.curve = SmoothScrollDefaults.curve,
  }) : assert(duration > Duration.zero);

  final double start;
  final double end;
  final Duration duration;
  final Curve curve;

  double get _seconds => duration.inMicroseconds / 1000000;

  @override
  double x(double time) {
    if (time <= 0) return start;
    if (isDone(time)) return end;
    return start + (end - start) * curve.transform(time / _seconds);
  }

  @override
  double dx(double time) {
    if (isDone(time)) return 0;
    // Match interpolation simulations: velocity is for scroll notifications;
    // position is always sampled directly from the package's configured curve.
    const interval = .0001;
    final before = (time - interval).clamp(0.0, _seconds);
    final after = (time + interval).clamp(0.0, _seconds);
    return after == before ? 0 : (x(after) - x(before)) / (after - before);
  }

  @override
  bool isDone(double time) => time >= _seconds;
}
