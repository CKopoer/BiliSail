import 'dart:async';

import 'native_readiness.dart';

/// Prepare rate changes before audio decoding/output starts.
///
/// Keep pitch correction installed across 1x and limit queued output audio:
/// samples already rendered at the old speed otherwise delay video when mpv
/// switches its audio clock to the new speed. This is separate from demux/network
/// buffering and leaves pitch correction enabled.
Future<void> configureNativeRateAudio({
  required Future<void> Function(String, String) write,
  required Future<String> Function(String) read,
  required bool Function() isCurrent,
  required Duration timeout,
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

  for (final entry in const {
    // 50 ms retains several audio device periods while avoiding mpv's default
    // 200 ms output queue on interactive VOD rate changes. Devices may use more.
    'audio-buffer': '0.05',
    'af': 'scaletempo2',
  }.entries) {
    final writeTimeout = remaining();
    await write(entry.key, entry.value).timeout(writeTimeout);
    final readTimeout = remaining();
    final applied = await read(entry.key).timeout(readTimeout);
    remaining();
    // The locked media_kit drops native property-write errors. Verify both
    // settings; mpv may normalize numeric property strings on readback.
    final matches = entry.key == 'audio-buffer'
        ? double.tryParse(applied) == 0.05
        : applied == entry.value;
    if (!matches) {
      throw StateError('The native backend rejected audio rate configuration.');
    }
  }
}
