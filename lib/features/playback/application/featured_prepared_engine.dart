import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/foundation.dart';

import '../../../domain/request_cancellation.dart';

typedef FeaturedEnginePlan = ({
  ResolvedMediaSource source,
  OpenOptions options,
});

// Owns one speculative native player until it is cleared or claimed by the
// visible playback session. Preparing a neighbor never starts audio.
final class FeaturedPreparedEngine {
  FeaturedPreparedEngine({
    required this.createEngine,
    this.maximumAge = const Duration(minutes: 1),
    this.handoffTimeout = const Duration(milliseconds: 120),
  });

  static const _openLimit = Duration(seconds: 12);

  final PlayerEngine Function() createEngine;
  final Duration maximumAge;
  final Duration handoffTimeout;
  final previewChanges = ValueNotifier(0);

  _Preparation? _candidate;
  _Preparation? _claim;
  Future<void> _releasing = Future.value();
  bool _releaseFailed = false;
  bool _previewChangeQueued = false;

  PlayerEngine? preview(Object key, {Object? owner}) {
    for (final entry in [?_candidate, ?_claim]) {
      if (entry.key == key &&
          identical(entry.owner, owner) &&
          entry.ready.isCompleted) {
        return entry.engine;
      }
    }
    return null;
  }

  void _notifyPreviewChange() {
    if (_previewChangeQueued) return;
    _previewChangeQueued = true;
    scheduleMicrotask(() {
      _previewChangeQueued = false;
      previewChanges.value++;
    });
  }

  void prepare(
    Object key,
    Future<FeaturedEnginePlan> Function(RequestCancellation) resolve, {
    Object? owner,
  }) {
    if (_releaseFailed ||
        (_candidate?.key == key && identical(_candidate?.owner, owner)) ||
        (_claim?.key == key && identical(_claim?.owner, owner))) {
      return;
    }
    if (_candidate case final previous?) _discard(previous);
    final entry = _candidate = _Preparation(key, owner);
    entry.expiration = Timer(maximumAge, () => _discard(entry));
    unawaited(_open(entry, resolve));
  }

  Future<void> _open(
    _Preparation entry,
    Future<FeaturedEnginePlan> Function(RequestCancellation) resolve,
  ) async {
    try {
      final plan = await resolve(entry.cancellation);
      if (entry.finished) return;
      final source = plan.source;
      if (source is! DashPairSource || plan.options.retainPresentation) {
        _discard(entry);
        return;
      }
      entry.plan = plan;
      if (_claim case final previous? when !identical(previous, entry)) {
        await previous.relinquished.future;
      }
      await _releasing;
      if (entry.finished) return;
      if (_releaseFailed) {
        _discard(entry);
        return;
      }
      final engine = entry.engine = createEngine();
      entry.failures = engine.failures.listen((_) => _discard(entry));
      final options = plan.options;
      final timeout = options.openTimeout < _openLimit
          ? options.openTimeout
          : _openLimit;
      await Future.any([
        engine.open(
          source,
          OpenOptions(
            startPosition: options.startPosition,
            play: false,
            rate: options.rate,
            volume: 0,
            audioGainDb: options.audioGainDb,
            videoDecoding: options.videoDecoding,
            androidVideoOutput: options.androidVideoOutput,
            androidAudioOutput: options.androidAudioOutput,
            cacheLimits: options.cacheLimits,
            maxBufferAhead: options.requestedBufferAhead,
            openTimeout: timeout,
          ),
        ),
        entry.relinquished.future,
      ]).timeout(timeout);
      if (!entry.finished) {
        entry.ready.complete();
        _notifyPreviewChange();
      }
    } on Object {
      // Speculation can fail independently of foreground resolve and open.
      _discard(entry);
    }
  }

  Future<PlayerEngine?>? take(
    Object key,
    ResolvedMediaSource actual,
    OpenOptions actualOptions,
    RequestCancellation cancellation, {
    Object? owner,
  }) {
    final entry = _candidate;
    if (entry == null || entry.key != key || !identical(entry.owner, owner)) {
      return null;
    }
    final plan = entry.plan;
    if (plan == null ||
        !_sameSource(plan.source, actual) ||
        !_sameOptions(plan.options, actualOptions) ||
        cancellation.isCancelled) {
      _discard(entry);
      return null;
    }
    if (_claim case final previous?) _discard(previous);
    _candidate = null;
    _claim = entry;
    return _take(entry, cancellation);
  }

  Future<PlayerEngine?> _take(
    _Preparation entry,
    RequestCancellation cancellation,
  ) async {
    cancellation.onCancel(() => _discard(entry));
    await entry.ready.future.timeout(
      handoffTimeout,
      onTimeout: () => _discard(entry),
    );
    final engine = entry.engine;
    if (entry.finished || engine == null) return null;
    final snapshot = engine.currentSnapshot;
    if (snapshot.desiredPlaying ||
        snapshot.volume != 0 ||
        (snapshot.phase != PlaybackPhase.paused &&
            snapshot.phase != PlaybackPhase.ready)) {
      _discard(entry);
      return null;
    }
    // Transfer the original open engine. Reopening would discard its buffers.
    entry.engine = null;
    _discard(entry);
    return engine;
  }

  Future<void> clear({Object? owner}) {
    for (final entry in [?_candidate, ?_claim]) {
      if (owner == null || identical(entry.owner, owner)) _discard(entry);
    }
    return _releasing;
  }

  void _discard(_Preparation entry) {
    if (entry.finished) return;
    entry.finished = true;
    if (identical(_candidate, entry)) _candidate = null;
    if (identical(_claim, entry)) _claim = null;
    entry.expiration.cancel();
    entry.plan = null;
    final failureSubscription = entry.failures;
    entry.failures = null;
    unawaited(failureSubscription?.cancel());
    if (entry.engine case final engine?) {
      entry.engine = null;
      _releasing = Future.wait([_releasing, _release(engine)]).then((_) {});
    }
    entry.cancellation.cancel();
    if (!entry.ready.isCompleted) entry.ready.complete();
    entry.relinquished.complete();
    _notifyPreviewChange();
  }

  Future<void> _release(PlayerEngine engine) async {
    try {
      // Stop invalidates any in-flight open before native disposal.
      await engine.stop();
    } on Object {
      // Disposal still runs when stop fails.
    }
    try {
      await engine.dispose();
    } on Object {
      _releaseFailed = true;
    }
  }
}

final class _Preparation {
  _Preparation(this.key, this.owner);

  final Object key;
  final Object? owner;
  final cancellation = RequestCancellation();
  final ready = Completer<void>();
  final relinquished = Completer<void>();
  late final Timer expiration;
  FeaturedEnginePlan? plan;
  PlayerEngine? engine;
  StreamSubscription<PlayerFailure>? failures;
  bool finished = false;
}

bool _sameTrack(MediaTrack? prepared, MediaTrack? actual) {
  if (prepared == null || actual == null) return prepared == actual;
  return prepared.uri == actual.uri &&
      prepared.codec == actual.codec &&
      prepared.embeddedAudioCodec == actual.embeddedAudioCodec &&
      prepared.bandwidth == actual.bandwidth &&
      prepared.isHdr == actual.isHdr &&
      mapEquals(prepared.requestPolicy.headers, actual.requestPolicy.headers);
}

bool _sameSource(ResolvedMediaSource prepared, ResolvedMediaSource actual) =>
    prepared is DashPairSource &&
    actual is DashPairSource &&
    prepared.duration == actual.duration &&
    prepared.isIntentionallySilent == actual.isIntentionallySilent &&
    _sameTrack(prepared.video, actual.video) &&
    _sameTrack(prepared.audio, actual.audio);

bool _sameOptions(OpenOptions prepared, OpenOptions actual) =>
    !actual.retainPresentation &&
    prepared.startPosition == actual.startPosition &&
    prepared.rate == actual.rate &&
    prepared.videoDecoding == actual.videoDecoding &&
    prepared.androidVideoOutput == actual.androidVideoOutput &&
    prepared.androidAudioOutput == actual.androidAudioOutput &&
    prepared.cacheLimits == actual.cacheLimits &&
    prepared.requestedBufferAhead == actual.requestedBufferAhead;
