/// Coordinates pause and target decoding after EOF or cancellation.
/// MDK can retire the source between the pause request and the seek callback.
Future<int> seekFvpTarget({
  required bool Function() isCancelled,
  required bool Function() needsPrepare,
  required Future<int> Function() prepare,
  required Future<bool> Function() pauseAndWait,
  required Future<int> Function() seek,
}) async {
  var restore = false;
  bool retryable(int code) => const {-2, -3, -8, -10}.contains(code);
  for (var attempt = 0; attempt < 2; attempt++) {
    if (isCancelled()) return -2;
    if (restore || needsPrepare()) {
      final result = await prepare();
      if (isCancelled()) return -2;
      if (result < 0) {
        if (attempt == 0 && retryable(result)) {
          restore = true;
          continue;
        }
        return result;
      }
    }
    final paused = await pauseAndWait();
    if (isCancelled()) return -2;
    if (!paused) {
      // An EOF transition can win while the asynchronous pause is pending.
      if (attempt == 1) return -3;
      restore = true;
      continue;
    }
    final result = await seek();
    if (isCancelled()) return -2;
    // -2: previous seek still pending; -3: media unloaded; -10: fvp's native
    // call was rejected before accepting a seek. -8 is also observed after an
    // interrupted HTTP restore. Retire that load once within the same deadline.
    if (attempt == 0 && retryable(result)) {
      restore = true;
      continue;
    }
    return result;
  }
  return -3;
}

/// MDK's Android audio output can retain a paused seek after it has played.
/// Drive that target silently, then acknowledge pause before restoring volume.
Future<int> seekFvpAudioTarget({
  required bool Function() isCancelled,
  required void Function(bool) setMuted,
  required Future<void> Function() playAndWait,
  required Future<int> Function() seek,
  required Future<bool> Function() pauseAndConfirm,
}) async {
  setMuted(true);
  var result = -2;
  var paused = false;
  try {
    await playAndWait();
    if (!isCancelled()) result = await seek();
  } finally {
    if (!isCancelled()) {
      paused = await pauseAndConfirm();
      if (paused && !isCancelled()) setMuted(false);
    }
  }
  return isCancelled()
      ? -2
      : paused
      ? result
      : -3;
}
