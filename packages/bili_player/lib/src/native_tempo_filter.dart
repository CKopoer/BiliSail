import 'dart:async';

import 'native_readiness.dart';

/// Keep pitch correction in the audio chain before decoding starts. Otherwise
/// mpv inserts/removes and drains its automatic tempo filter when crossing 1x.
/// Rate commands can then change only speed, without replacing audio filters.
Future<void> configureNativeTempoFilter({
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
      throw TimeoutException('Audio tempo configuration timed out.');
    }
    return value;
  }

  final writeTimeout = remaining();
  await write('af', 'scaletempo2').timeout(writeTimeout);
  final readTimeout = remaining();
  final applied = await read('af').timeout(readTimeout);
  remaining();
  // The locked media_kit drops native property-write errors. Do not silently
  // proceed with the automatic filter insertion path if configuration failed.
  if (applied != 'scaletempo2') {
    throw StateError('The native backend rejected the audio tempo filter.');
  }
}
