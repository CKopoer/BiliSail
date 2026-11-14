import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/request_cancellation.dart';
import '../domain/playback_repository.dart';

final cardPreviewPlaybackProvider = Provider<CardPreviewPlayback>(
  (ref) => throw UnimplementedError('Card preview playback'),
);

/// A transient engine, with no progress store, history reporter or playback tab.
final class CardPreviewSession {
  CardPreviewSession._(this.engine, this.cancellation);
  final PlayerEngine engine;
  final RequestCancellation cancellation;
  StreamSubscription<PlayerFailure>? _failures;
  bool closed = false;
}

/// Process-owned so account/controller replacement cannot overlap native engines.
final class CardPreviewPlayback {
  CardPreviewPlayback({
    required this.createEngine,
    this.openTimeout = const Duration(seconds: 3),
  });
  final PlayerEngine Function() createEngine;
  final Duration openTimeout;
  CardPreviewSession? _current;
  Future<void> _released = Future.value();
  bool _closed = false;
  bool _releaseFailed = false;
  int _generation = 0;

  Future<CardPreviewSession?> start(
    PlaybackMedia media,
    RequestCancellation cancellation,
  ) => startSources(
    media.kind == PlaybackMediaKind.dash
        ? media.video.urls
              .toSet()
              .map(
                (uri) => DashVideoSource(
                  MediaTrack(
                    uri: uri,
                    requestPolicy: MediaRequestPolicy(headers: media.headers),
                    codec: media.video.codec,
                    bandwidth: media.video.bandwidth,
                  ),
                ),
              )
              .toList()
        : const [],
    cancellation,
  );

  /// Sources are ordered by the resolver; at most three addresses are opened.
  Future<CardPreviewSession?> startSources(
    List<ResolvedMediaSource> sources,
    RequestCancellation cancellation,
  ) async {
    final generation = ++_generation;
    await _stopCurrent();
    if (_closed ||
        generation != _generation ||
        _releaseFailed ||
        cancellation.isCancelled ||
        sources.isEmpty) {
      return null;
    }
    final attempts = sources.length.clamp(1, 3);
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (_closed ||
          generation != _generation ||
          _releaseFailed ||
          cancellation.isCancelled) {
        return null;
      }
      final session = CardPreviewSession._(createEngine(), cancellation);
      _current = session;
      cancellation.onCancel(() => unawaited(_release(session)));
      var opening = true;
      PlayerFailure? openingFailure;
      session._failures = session.engine.failures.listen((failure) {
        if (opening) {
          // Native open emits failure before its Future throws. Allow the
          // bounded backup attempt instead of cancelling the whole hover.
          openingFailure = failure;
        } else {
          cancellation.cancel();
        }
      });
      try {
        await session.engine
            .open(
              sources[attempt],
              OpenOptions(
                play: true,
                volume: 0,
                openTimeout: openTimeout,
                maxBufferAhead: const Duration(seconds: 5),
              ),
            )
            .timeout(openTimeout);
        opening = false;
        if (openingFailure case final failure?) throw failure;
        if (_closed ||
            generation != _generation ||
            cancellation.isCancelled ||
            session.closed) {
          await _release(session);
          return null;
        }
        return session;
      } on PlayerFailure {
        await _release(session);
      } on TimeoutException {
        // stop invalidates the still-running open before trying another CDN.
        await _release(session);
      }
    }
    cancellation.cancel();
    return null;
  }

  Future<void> _release(CardPreviewSession session) {
    if (session.closed) return _released;
    session.closed = true;
    if (identical(_current, session)) _current = null;
    // stop invalidates an in-flight native open synchronously before awaiting it.
    final release = () async {
      try {
        await session.engine.stop();
      } on Object {
        // A failed engine can reject stop; confirmed dispose still releases it.
      }
      try {
        await session._failures?.cancel();
      } on Object {
        // Dispose must run even if stream cleanup fails.
      }
      await session.engine.dispose();
    }();
    _released = Future.wait([_released, release]).then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        // An uncertain native release must not be followed by another engine.
        _releaseFailed = true;
      },
    );
    return _released;
  }

  Future<void> stop() {
    ++_generation;
    return _stopCurrent();
  }

  Future<void> _stopCurrent() {
    final current = _current;
    current?.cancellation.cancel();
    return _released;
  }

  Future<void> close() {
    _closed = true;
    return stop();
  }
}
