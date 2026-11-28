import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/foundation.dart';

import '../../../domain/request_cancellation.dart';
import '../domain/featured_playback_limits.dart';

typedef FeaturedEnginePlan = ({
  ResolvedMediaSource source,
  OpenOptions options,
});

// Owns one speculative native player until it is cleared or claimed by the
// visible playback session. A visible preview can play at zero volume.
final class FeaturedPreparedEngine {
  FeaturedPreparedEngine({
    required this.createEngine,
    this.maximumAge = featuredStandbyMaximumAge,
    this.handoffTimeout = const Duration(seconds: 2),
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
          _freshSource(entry.plan?.source)) {
        return entry.engine;
      }
    }
    return null;
  }

  void setVisiblePreview(Object? key, {Object? owner}) {
    for (final entry in [?_candidate, ?_claim]) {
      if (!identical(entry.owner, owner)) continue;
      entry.visible = entry.key == key;
      entry.preview?.show(entry.visible && _freshSource(entry.plan?.source));
    }
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
      if (!_freshSource(source) || plan.options.retainPresentation) {
        _discard(entry);
        return;
      }
      if (entry.acceptPlan?.call(plan) == false) {
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
      // Android can only acknowledge the first presented frame once the
      // adjacent slot has attached the texture. The surface masks early frames.
      _notifyPreviewChange();
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
            preload: true,
          ),
        ),
        entry.relinquished.future,
      ]).timeout(timeout);
      if (!entry.finished) {
        entry.preview = FeaturedMutedPreview(
          engine,
          startPosition: options.startPosition,
          onFailure: () => _discard(entry),
        );
        entry.ready.complete();
        _notifyPreviewChange();
        entry.preview?.show(entry.visible && _freshSource(source));
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
    bool keepPreviewPlaying = false,
  }) {
    final entry = _candidate;
    if (entry == null || entry.key != key || !identical(entry.owner, owner)) {
      return null;
    }
    final plan = entry.plan;
    if ((plan != null && !_matches(plan, actual, actualOptions)) ||
        cancellation.isCancelled) {
      _discard(entry);
      return null;
    }
    if (_claim case final previous?) _discard(previous);
    _candidate = null;
    _claim = entry;
    entry.acceptPlan = (plan) => _matches(plan, actual, actualOptions);
    final timeout = handoffTimeout < actualOptions.openTimeout
        ? handoffTimeout
        : actualOptions.openTimeout;
    cancellation.onCancel(() => _discard(entry));
    return _take(entry, actual, actualOptions, keepPreviewPlaying).timeout(
      timeout,
      onTimeout: () {
        _discard(entry);
        return null;
      },
    );
  }

  Future<PlayerEngine?> _take(
    _Preparation entry,
    ResolvedMediaSource source,
    OpenOptions options,
    bool keepPreviewPlaying,
  ) async {
    await entry.ready.future;
    final engine = entry.engine;
    final plan = entry.plan;
    if (entry.finished || engine == null || plan == null) return null;
    if (!_matches(plan, source, options) ||
        !await entry.preview!.handoff(keepPlaying: keepPreviewPlaying)) {
      _discard(entry);
      return null;
    }
    if (entry.finished) return null;
    final snapshot = engine.currentSnapshot;
    if (snapshot.volume != 0 ||
        (!keepPreviewPlaying && snapshot.desiredPlaying) ||
        !_readyPhase(snapshot.phase)) {
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
    entry.preview?.release();
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
  bool Function(FeaturedEnginePlan)? acceptPlan;
  FeaturedMutedPreview? preview;
  PlayerEngine? engine;
  StreamSubscription<PlayerFailure>? failures;
  bool visible = false;
  bool finished = false;
}

/// Controls motion on a muted, unattached engine. Cancellation restores the
/// start position so browsing a frame does not consume a saved checkpoint.
final class FeaturedMutedPreview {
  FeaturedMutedPreview(
    this.engine, {
    required this.startPosition,
    required this.onFailure,
  });

  final PlayerEngine engine;
  final Duration startPosition;
  final void Function() onFailure;
  bool _visible = false;
  bool _started = false;
  bool _released = false;
  int _revision = 0;
  Future<void>? _rewinding;

  void show(bool visible) {
    if (_released || visible == _visible) return;
    _visible = visible;
    final revision = ++_revision;
    if (visible) {
      unawaited(_play(revision));
    } else if (_started) {
      _started = false;
      _rewinding = _rewind();
    }
  }

  Future<void> _play(int revision) async {
    try {
      if (_rewinding case final pending?) await pending;
      if (_released || revision != _revision) return;
      final snapshot = engine.currentSnapshot;
      if (snapshot.volume != 0 || !_readyPhase(snapshot.phase)) return;
      _started = true;
      await engine.play();
    } on Object {
      if (!_released && revision == _revision) onFailure();
    }
  }

  Future<void> _rewind() async {
    try {
      // Pause cancels a pending native play confirmation immediately.
      await engine.pause();
      if (!_released && engine.currentSnapshot.position != startPosition) {
        await engine.seek(startPosition);
      }
    } on Object {
      if (!_released) onFailure();
    }
  }

  Future<bool> handoff({required bool keepPlaying}) async {
    if (!keepPlaying) show(false);
    if (_rewinding case final pending?) await pending;
    if (_released) return false;
    release();
    return true;
  }

  void release() => _released = true;
}

bool _readyPhase(PlaybackPhase phase) => switch (phase) {
  PlaybackPhase.paused ||
  PlaybackPhase.ready ||
  PlaybackPhase.playing ||
  PlaybackPhase.buffering => true,
  _ => false,
};

bool _freshSource(ResolvedMediaSource? source) {
  final tracks = switch (source) {
    DashPairSource(:final video, :final audio) => [video, ?audio],
    ProgressiveSource(:final media, isLive: false, isAudioOnly: false) => [
      media,
    ],
    _ => const <MediaTrack>[],
  };
  final threshold =
      DateTime.now().add(const Duration(seconds: 15)).millisecondsSinceEpoch ~/
      1000;
  return tracks.isNotEmpty &&
      tracks.every((track) {
        final deadline = int.tryParse(
          track.uri.queryParameters['deadline'] ?? '',
        );
        return deadline == null || deadline > threshold;
      });
}

bool _matches(
  FeaturedEnginePlan plan,
  ResolvedMediaSource source,
  OpenOptions options,
) =>
    _freshSource(plan.source) &&
    _sameSource(plan.source, source) &&
    _sameOptions(plan.options, options);

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
    switch ((prepared, actual)) {
      (DashPairSource a, DashPairSource b) =>
        a.duration == b.duration &&
            a.isIntentionallySilent == b.isIntentionallySilent &&
            _sameTrack(a.video, b.video) &&
            _sameTrack(a.audio, b.audio),
      (ProgressiveSource a, ProgressiveSource b) =>
        !b.isLive && !b.isAudioOnly && _sameTrack(a.media, b.media),
      _ => false,
    };

bool _sameOptions(OpenOptions prepared, OpenOptions actual) =>
    !actual.retainPresentation &&
    prepared.startPosition == actual.startPosition &&
    prepared.rate == actual.rate &&
    prepared.audioGainDb == actual.audioGainDb &&
    prepared.videoDecoding == actual.videoDecoding &&
    prepared.androidVideoOutput == actual.androidVideoOutput &&
    prepared.androidAudioOutput == actual.androidAudioOutput &&
    prepared.cacheLimits == actual.cacheLimits &&
    prepared.requestedBufferAhead == actual.requestedBufferAhead;
