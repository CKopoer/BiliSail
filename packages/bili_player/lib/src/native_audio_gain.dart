import 'dart:async';
import 'dart:math' as math;

import 'native_readiness.dart';

/// Per-native-player gain control. Never changes mpv's user volume setting.
final class NativeAudioGain {
  NativeAudioGain({
    required this.write,
    required this.read,
    required this.isCurrent,
    Future<void> Function(Duration)? delay,
  }) : delay = delay ?? Future<void>.delayed;

  final Future<void> Function(String, String) write;
  final Future<String> Function(String) read;
  final bool Function() isCurrent;
  final Future<void> Function(Duration) delay;
  double gainDb = 0;
  int _revision = 0;
  bool _configured = false;
  bool _gainApplied = false;

  static bool valid(double gain) => gain.isFinite && gain >= -60 && gain <= 30;

  void cancel() => _revision++;

  Future<void> apply(double target, {bool smooth = true}) {
    if (!valid(target)) throw ArgumentError.value(target, 'gainDb');
    final revision = ++_revision;
    return _apply(target, smooth, revision).timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        if (_revision == revision) cancel();
        throw TimeoutException('Audio gain command timed out.');
      },
    );
  }

  Future<void> _apply(double target, bool smooth, int revision) async {
    void check() {
      if (revision != _revision || !isCurrent()) throw const SourceSuperseded();
    }

    Future<void> setGain(double value) async {
      check();
      await write('replaygain-fallback', value.toString());
      check();
      final applied = double.tryParse(await read('replaygain-fallback'));
      check();
      // media_kit 1.2.6 drops native property errors; always verify readback.
      if (applied == null ||
          !applied.isFinite ||
          (applied - value).abs() > .00001) {
        throw StateError('The native backend did not apply audio gain.');
      }
      gainDb = value;
      _gainApplied = true;
    }

    check();
    if (!_configured) {
      await write('replaygain', 'no');
      check();
      final mode = await read('replaygain');
      check();
      if (mode != 'no') {
        throw StateError('The native backend did not disable track gain.');
      }
      _configured = true;
    }
    // A new source controller may inherit a nonzero gain on a reused player.
    if (_gainApplied && gainDb == target) return;
    if (smooth) {
      final from = math.pow(10, gainDb / 20).toDouble();
      final to = math.pow(10, target / 20).toDouble();
      // Approximate the Web GainNode's 15 ms time constant with a bounded ramp.
      // Source changes cancel it before a subsequent native property write.
      for (var step = 1; step <= 8; step++) {
        await delay(const Duration(milliseconds: 10));
        check();
        final amplitude = to + (from - to) * math.exp(-step * 10 / 15);
        await setGain(20 * math.log(amplitude) / math.ln10);
      }
      await delay(const Duration(milliseconds: 10));
    }
    await setGain(target);
  }
}
