import 'dart:async';

import 'native_readiness.dart';

/// Constructor overrides take priority over the build flag and platform default.
/// An absent or invalid build flag keeps mpv's decoder queue defaults.
bool resolveVideoFrameQueueEnabled({
  required bool isAndroid,
  bool? enabledOverride,
  String buildOverride = const String.fromEnvironment(
    'BILISAIL_VIDEO_FRAME_QUEUE',
  ),
}) =>
    enabledOverride ??
    switch (buildOverride) {
      'true' => true,
      'false' => false,
      _ => false,
    };

/// Configured before loadfile creates the video decoder.
/// These are queue limits, not a prefill threshold or total GPU memory limit.
const nativeVideoFrameQueueProperties = <String, String>{
  'vd-queue-max-samples': '8',
  'vd-queue-max-secs': '0.1',
  'vd-queue-max-bytes': '67108864',
  // Apply limits first so the decoder never starts with mpv's larger defaults.
  'vd-queue-enable': 'yes',
};

Future<void> configureNativeVideoFrameQueue({
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
      throw TimeoutException('Video frame queue configuration timed out.');
    }
    return value;
  }

  for (final entry in nativeVideoFrameQueueProperties.entries) {
    final writeTimeout = remaining();
    await write(entry.key, entry.value).timeout(writeTimeout);
    final readTimeout = remaining();
    final applied = await read(entry.key).timeout(readTimeout);
    remaining();
    // media_kit 1.2.6 does not propagate native property-write errors.
    final matches = entry.key == 'vd-queue-enable'
        ? applied == entry.value
        : double.tryParse(applied) == double.parse(entry.value);
    if (!matches) {
      throw StateError('The native backend rejected video frame buffering.');
    }
  }
}
