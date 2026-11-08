import 'dart:async';

/// Starts a paused, confirmed A/V pair without advancing either track early.
///
/// Readiness must come from decoding at the target while paused. Changing
/// volume or playing a hidden preroll cannot substitute for synchronization.
Future<void> finishSynchronizedStartup({
  required bool Function() shouldPlay,
  required FutureOr<void> Function() play,
  required FutureOr<void> Function() pause,
  required Future<void> Function() confirmReady,
  required FutureOr<void> Function() applyVolume,
  required void Function() checkActive,
}) async {
  checkActive();
  await pause();
  checkActive();
  await confirmReady();
  checkActive();
  await applyVolume();
  checkActive();
  if (shouldPlay()) {
    await play();
  } else {
    await pause();
  }
  checkActive();
}
