import 'dart:async';

import 'native_readiness.dart';

/// PiliPlus's native playback defaults, independent of source and playback rate.
/// Pitch correction, audio buffering and decoder queues remain owned by mpv.
Future<void> configureNativePlaybackPolicy({
  required bool isAndroid,
  required Future<void> Function(String, String) write,
  required Future<String> Function(String) read,
  required bool Function() isCurrent,
  required Duration timeout,
  int? experimentalAutosync,
}) async {
  final watch = Stopwatch()..start();
  Duration remaining() {
    if (!isCurrent()) throw const SourceSuperseded();
    final value = timeout - watch.elapsed;
    if (value <= Duration.zero) {
      throw TimeoutException('Native playback configuration timed out.');
    }
    return value;
  }

  // Older SDKs, including PiliPlus's Windows build, use lavf already. Newer
  // libmpv builds enable curl, whose retry budget spans an unbounded response.
  // Use the same lavf reconnect path on builds that expose this capability.
  final capabilityTimeout = remaining();
  final transport = await read('curl-enabled').timeout(capabilityTimeout);
  remaining();
  final properties = {
    if (transport == 'yes' || transport == 'no') 'curl-enabled': 'no',
    // network-timeout bounds TCP waits, but not lavf's outer TLS EAGAIN loop.
    // SChannel can keep returning EAGAIN for an incomplete record after TCP
    // EOF. Bound that loop too, so lavf can reconnect from the received offset
    // instead of leaving an empty demuxer cache paused indefinitely.
    'stream-lavf-o': 'rw_timeout=5000000',
    'video-sync': 'display-resample',
    'autosync': '${experimentalAutosync ?? (isAndroid ? 30 : 0)}',
    if (isAndroid) 'ao': 'opensles,aaudio,audiotrack',
    // The official SDK overrides these; PiliPlus leaves mpv's defaults intact.
    'hr-seek': 'default',
    'hr-seek-framedrop': 'yes',
    'cache-on-disk': 'no',
  };
  for (final entry in properties.entries) {
    final writeTimeout = remaining();
    await write(entry.key, entry.value).timeout(writeTimeout);
    final readTimeout = remaining();
    final applied = await read(entry.key).timeout(readTimeout);
    remaining();
    if (applied != entry.value) {
      throw StateError('The native backend rejected playback configuration.');
    }
  }
}
