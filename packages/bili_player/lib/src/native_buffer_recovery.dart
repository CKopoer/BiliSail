import 'dart:async';
import 'dart:io';

import 'player_contract.dart';
import 'player_diagnostics.dart';

enum NativeBufferRecoveryReason { readError, stalledRead }

/// A bounded recovery episode for failed prefetch while cached playback runs.
/// Position advancing is not evidence that the network reader has recovered.
final class NativeBufferRecovery {
  NativeBufferRecovery({
    required this.snapshot,
    required this.probe,
    required this.cancelProbe,
    required this.onRecoveryRequired,
  });

  static const retryInterval = Duration(seconds: 5);
  static const deadline = Duration(minutes: 2);
  static const maximumAttempts = 24;
  final PlaybackSnapshot Function() snapshot;
  final Future<bool> Function() probe;
  final void Function() cancelProbe;
  final void Function(NativeBufferRecoveryReason) onRecoveryRequired;
  Timer? _retry, _deadline, _readDeadline;
  Object? _episode;
  Duration _buffered = Duration.zero;
  int _attempts = 0;
  bool _exhausted = false, _disposed = false, _reading = false;
  bool _recoveryRequested = false;

  void readingChanged(bool reading, {bool endOfInput = false}) {
    _reading = reading && !endOfInput;
    // Input EOF also means normal prefetch completion. DASH tracks can end at
    // different timestamps; the estimated cache endpoint cannot prove a read
    // failure. Let native playback consume the cache and report real errors or
    // premature playback completion through the existing engine event route.
    // Once the reader becomes idle, a pending silent-read probe is stale too.
    // A reachable origin cannot turn normal cache backpressure into a failure.
    if (!_reading) cancel();
    update();
  }

  bool get _active {
    final value = snapshot();
    return !_disposed &&
        !_recoveryRequested &&
        value.desiredPlaying &&
        !value.isSeeking &&
        const {
          PlaybackPhase.playing,
          PlaybackPhase.buffering,
        }.contains(value.phase) &&
        (value.duration == Duration.zero ||
            value.duration - value.buffered >
                const Duration(milliseconds: 500));
  }

  bool get _eligible =>
      _active &&
      // A blocked native read can delay its cache-time notification even
      // while queued packets keep playing. Do not require that notification
      // to detect the read stall. Empty, already-buffering playback keeps its
      // existing normal underrun recovery path.
      (snapshot().phase == PlaybackPhase.playing ||
          snapshot().buffered - snapshot().position >
              const Duration(seconds: 1));

  void reportError(NativeErrorSummary error) {
    // Both SDK log/error streams use this policy. A new cause must explicitly
    // choose whether it proves a media read failure, even while cache plays.
    final readFailure = switch (error.cause) {
      NativeErrorCause.http ||
      NativeErrorCause.timeout ||
      NativeErrorCause.connection ||
      NativeErrorCause.tls ||
      NativeErrorCause.inputOutput => true,
      NativeErrorCause.hardwareDecoder ||
      NativeErrorCause.videoOutput ||
      NativeErrorCause.decoder ||
      NativeErrorCause.missingFile ||
      NativeErrorCause.openFailed ||
      NativeErrorCause.unsupportedProperty ||
      NativeErrorCause.unknown => false,
    };
    if (readFailure) reportNetworkError(immediate: true);
  }

  void reportNetworkError({bool immediate = false}) {
    if (immediate) {
      // A confirmed read failure needs no reachability probe or cache drain.
      // The session owns retry/backoff and pauses both tracks before reopening.
      if (_active) _requestRecovery(NativeBufferRecoveryReason.readError);
      return;
    }
    if (!_eligible || _episode != null || _exhausted) return;
    _readDeadline?.cancel();
    _readDeadline = null;
    final episode = _episode = Object();
    _buffered = snapshot().buffered;
    _attempts = 0;
    _deadline = Timer(deadline, () {
      if (!identical(_episode, episode)) return;
      _exhausted = true;
      cancel();
    });
    _schedule(episode);
  }

  void update() {
    if (_disposed) return;
    final buffered = snapshot().buffered;
    // Only new cached media rearms the budget, never repeated error logs or
    // consuming already-buffered packets. A backward seek cancels the episode.
    if (buffered > _buffered + const Duration(milliseconds: 50)) {
      _exhausted = false;
      _buffered = buffered;
      cancel();
    } else if (buffered < _buffered - const Duration(milliseconds: 50)) {
      // Seeking or native cache eviction can move the endpoint backwards.
      // Later growth must be compared to this range, not a retired high-water
      // mark. A regression alone does not rearm an exhausted retry budget.
      _buffered = buffered;
      cancel();
    } else if (!_eligible) {
      cancel();
    }
    // Native idle distinguishes a full packet cache from a blocked read. This
    // arrives through SDK property events, not periodic native clock polling.
    if (!_reading || !_eligible || _episode != null || _exhausted) {
      _readDeadline?.cancel();
      _readDeadline = null;
    } else {
      _readDeadline ??= Timer(retryInterval, () {
        _readDeadline = null;
        reportNetworkError();
      });
    }
  }

  void _schedule(Object episode) {
    _retry = Timer(retryInterval, () => unawaited(_check(episode)));
  }

  Future<void> _check(Object episode) async {
    if (!identical(_episode, episode)) return;
    update();
    if (!identical(_episode, episode)) return;
    final reachable = await probe();
    update();
    if (!identical(_episode, episode)) return;
    if (reachable) {
      _requestRecovery(NativeBufferRecoveryReason.stalledRead);
    } else if (++_attempts >= maximumAttempts) {
      _exhausted = true;
      cancel();
    } else {
      _schedule(episode);
    }
  }

  void _requestRecovery(NativeBufferRecoveryReason reason) {
    _recoveryRequested = true;
    cancel();
    onRecoveryRequired(reason);
  }

  void cancel() {
    _episode = null;
    _retry?.cancel();
    _deadline?.cancel();
    _readDeadline?.cancel();
    _readDeadline = null;
    cancelProbe();
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}

/// Checks the actual media origins, with the active source's allowed headers.
/// No cookies, redirects, media cache, account state or raw errors are retained.
final class NativeMediaProbe {
  NativeMediaProbe(this.tracks);
  static const timeout = Duration(seconds: 3);
  final List<MediaTrack> tracks;
  HttpClient? _client;

  Future<bool> check() async {
    final client = _client = HttpClient()..connectionTimeout = timeout;
    try {
      return await _check(client).timeout(timeout);
    } on IOException {
      return false;
    } on TimeoutException {
      return false;
    } on StateError {
      if (identical(client, _client)) rethrow;
      return false;
    } finally {
      client.close(force: true);
      if (identical(client, _client)) _client = null;
    }
  }

  Future<bool> _check(HttpClient client) async {
    for (final track in tracks) {
      final request = await client.getUrl(track.uri);
      request.followRedirects = false;
      track.requestPolicy.headers.forEach(request.headers.set);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      final response = await request.close();
      // Redirects and expired signed URLs also prove the origin is reachable;
      // normal session recovery resolves fresh URLs and native follows redirects.
      final code = response.statusCode;
      final reachable =
          code == 200 ||
          code == 206 ||
          (code >= 300 && code < 400) ||
          code == 401 ||
          code == 403 ||
          code == 404 ||
          code == 410;
      await response.listen((_) {}).cancel();
      if (!reachable) return false;
    }
    return true;
  }

  void cancel() {
    _client?.close(force: true);
    _client = null;
  }
}
