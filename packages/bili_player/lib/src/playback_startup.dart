import 'dart:async';

/// Completes a muted native load without exposing a partially ready A/V pair.
///
/// Backends load with zero volume and supply their own decoded-track and output
/// confirmations. Some need to advance silently to produce those signals. Keep
/// cancellation checks between every step, and never restore volume on failure.
Future<void> finishSynchronizedStartup({
  required bool Function() shouldPlay,
  required FutureOr<void> Function() play,
  required FutureOr<void> Function() pause,
  required Future<void> Function() confirmReady,
  required FutureOr<void> Function() restoreVolume,
  required void Function() checkActive,
}) async {
  checkActive();
  if (shouldPlay()) {
    await play();
  } else {
    await pause();
  }
  checkActive();
  await confirmReady();
  checkActive();
  // A user pause can arrive while the native tracks or Flutter output wait.
  if (!shouldPlay()) {
    await pause();
    checkActive();
  }
  await restoreVolume();
  checkActive();
}
