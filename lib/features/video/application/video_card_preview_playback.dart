import 'dart:async';

import 'package:bili_player/bili_player.dart';

import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../../playback/domain/playback_repository.dart';
import '../domain/video_card_interactions.dart';

abstract interface class VideoCardOperations implements VideoCardInteractions {
  Future<VideoCardPreviewSession?> preview(
    VideoId id,
    RequestCancellation cancellation, {
    String? cid,
  });
}

/// A transient engine, with no progress store, history reporter or playback tab.
final class VideoCardPreviewSession {
  VideoCardPreviewSession._(this.engine, this.cancellation);
  final PlayerEngine engine;
  final RequestCancellation cancellation;
  StreamSubscription<PlayerFailure>? _failures;
  bool closed = false;
}

/// Process-owned so account/controller replacement cannot overlap native engines.
final class VideoCardPreviewPlayback {
  VideoCardPreviewPlayback({
    required this.createEngine,
    this.openTimeout = const Duration(seconds: 3),
  });
  final PlayerEngine Function() createEngine;
  final Duration openTimeout;
  VideoCardPreviewSession? _current;
  Future<void> _released = Future.value();
  bool _closed = false;
  bool _releaseFailed = false;
  int _generation = 0;

  Future<VideoCardPreviewSession?> start(
    PlaybackMedia media,
    RequestCancellation cancellation,
  ) async {
    final generation = ++_generation;
    await _stopCurrent();
    if (_closed ||
        generation != _generation ||
        _releaseFailed ||
        cancellation.isCancelled) {
      return null;
    }
    if (media.kind != PlaybackMediaKind.dash || media.video.urls.isEmpty) {
      return null;
    }
    final policy = MediaRequestPolicy(headers: media.headers);
    final videos = media.video.urls.toSet().toList();
    final attempts = videos.length.clamp(1, 3);
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (_closed ||
          generation != _generation ||
          _releaseFailed ||
          cancellation.isCancelled) {
        return null;
      }
      final session = VideoCardPreviewSession._(createEngine(), cancellation);
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
              DashVideoSource(
                MediaTrack(
                  uri: videos[attempt.clamp(0, videos.length - 1)],
                  requestPolicy: policy,
                  codec: media.video.codec,
                  bandwidth: media.video.bandwidth,
                ),
              ),
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

  Future<void> _release(VideoCardPreviewSession session) {
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
