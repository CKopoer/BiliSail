import 'dart:async';

import 'native_readiness.dart';

/// Per-player audio policy for responsive VOD rate changes in both directions.
///
/// Keep pitch correction installed across 1x, limit old-rate output audio and
/// smooth its clock correction when restoring speed. Network caching is separate.
/// A reused player restores its original policy for live/silent sources.
final class NativeRateAudio {
  NativeRateAudio({required this.write, required this.read});

  final Future<void> Function(String, String) write;
  final Future<String> Function(String) read;
  Map<String, String>? _defaults;

  Future<void> configure({
    required bool enabled,
    required bool Function() isCurrent,
    required Duration timeout,
    int? experimentalAutosync,
  }) async {
    final watch = Stopwatch()..start();
    Duration remaining() {
      if (!isCurrent()) throw const SourceSuperseded();
      final value = timeout - watch.elapsed;
      if (value <= Duration.zero) {
        throw TimeoutException('Audio rate configuration timed out.');
      }
      return value;
    }

    final responsive = {
      // A minimum request, not the measured device latency. Retains several
      // device periods without mpv's default 200 ms of old-rate output audio.
      'audio-buffer': '0.05',
      'af': 'scaletempo2',
      // Average AO clock error to reduce video catch-up on speed restoration.
      // This is an averaging factor, not a delay or frame-rate limit.
      'autosync': '${experimentalAutosync ?? 30}',
      'video-sync': 'audio',
    };
    remaining();
    if (!enabled && _defaults == null) return;
    var defaults = _defaults;
    if (defaults == null) {
      defaults = <String, String>{};
      for (final key in responsive.keys) {
        final readTimeout = remaining();
        defaults[key] = await read(key).timeout(readTimeout);
        remaining();
      }
      _defaults = defaults;
    }
    for (final entry in (enabled ? responsive : defaults).entries) {
      final writeTimeout = remaining();
      await write(entry.key, entry.value).timeout(writeTimeout);
      final readTimeout = remaining();
      final applied = await read(entry.key).timeout(readTimeout);
      remaining();
      // The locked SDK drops native write errors; verify normalized readback.
      final expectedNumber = double.tryParse(entry.value);
      final matches = expectedNumber == null
          ? applied == entry.value
          : double.tryParse(applied) == expectedNumber;
      if (!matches) {
        throw StateError(
          'The native backend rejected audio rate configuration.',
        );
      }
    }
  }
}
