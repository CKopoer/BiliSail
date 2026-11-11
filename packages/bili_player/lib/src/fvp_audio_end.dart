/// Frame timestamps include the container start time; Player.position does not.
int fvpAudioEndPosition({
  required int frameEndMilliseconds,
  required int mediaStartMilliseconds,
}) => frameEndMilliseconds < 0
    ? -1
    : frameEndMilliseconds - mediaStartMilliseconds;

/// MDK can reset the audio output position before delivering its stopped event.
/// Only decoded timestamps can prove that the advertised audio actually ended;
/// a lagging video position must not turn that normal EOF into a retry.
bool fvpAudioEndedNaturally({
  required int decodedEndMilliseconds,
  required int audioDurationMilliseconds,
  required int videoPositionMilliseconds,
  required int videoDurationMilliseconds,
}) {
  if (audioDurationMilliseconds > 0 && decodedEndMilliseconds >= 0) {
    return audioDurationMilliseconds - decodedEndMilliseconds <= 500;
  }
  // Retain the existing final-frame fallback when timestamps are unavailable.
  return videoDurationMilliseconds > 0 &&
      videoDurationMilliseconds - videoPositionMilliseconds <= 500;
}
