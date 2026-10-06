import 'dart:async';

import 'package:flutter/widgets.dart';

/// Headers are held only for the active source. Do not log or serialize this.
final class MediaRequestPolicy {
  MediaRequestPolicy({Map<String, String> headers = const {}})
    : headers = Map.unmodifiable(headers);

  final Map<String, String> headers;
}

final class MediaTrack {
  const MediaTrack({
    required this.uri,
    required this.requestPolicy,
    this.codec,
    this.bandwidth,
  });

  final Uri uri;
  final MediaRequestPolicy requestPolicy;
  final String? codec;
  final int? bandwidth;
}

sealed class ResolvedMediaSource {
  const ResolvedMediaSource();
}

final class ProgressiveSource extends ResolvedMediaSource {
  const ProgressiveSource(this.media);
  final MediaTrack media;
}

/// Video and audio are separate resources. Null audio is only valid when the
/// resolver has positively identified an intentionally silent source.
final class DashPairSource extends ResolvedMediaSource {
  const DashPairSource({
    required this.video,
    required this.audio,
    this.isIntentionallySilent = false,
  });

  final MediaTrack video;
  final MediaTrack? audio;
  final bool isIntentionallySilent;
}

/// A video representation with audio deliberately omitted for a muted preview.
/// This is distinct from a regular DASH pair with missing companion audio.
final class DashVideoSource extends ResolvedMediaSource {
  const DashVideoSource(this.video);
  final MediaTrack video;
}

/// An HLS or similar media manifest supplied by a resolver.
final class ManifestSource extends ResolvedMediaSource {
  const ManifestSource(this.media, {this.isLive = false});
  final MediaTrack media;
  final bool isLive;
}

/// Automatic uses the backend's platform defaults and software fallback.
enum VideoDecodingMode { automatic, software }

final class OpenOptions {
  const OpenOptions({
    this.startPosition = Duration.zero,
    this.play = false,
    this.rate = 1,
    this.volume = 100,
    this.videoDecoding = VideoDecodingMode.automatic,
    this.openTimeout = const Duration(seconds: 35),
  });
  final Duration startPosition;
  final bool play;
  final double rate;
  final double volume;
  final VideoDecodingMode videoDecoding;
  final Duration openTimeout;
}

enum PlaybackPhase {
  idle,
  opening,
  ready,
  playing,
  paused,
  buffering,
  ended,
  failed,
  disposed,
}

final class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.phase,
    required this.generation,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = Duration.zero,
    this.desiredPlaying = false,
    this.isBuffering = false,
    this.isSeeking = false,
    this.rate = 1,
    this.volume = 100,
  });

  final PlaybackPhase phase;
  final int generation;
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final bool desiredPlaying;
  final bool isBuffering;
  final bool isSeeking;
  final double rate;

  /// Native backend scale: 0 to 100.
  final double volume;

  PlaybackSnapshot copyWith({
    PlaybackPhase? phase,
    int? generation,
    Duration? position,
    Duration? duration,
    Duration? buffered,
    bool? desiredPlaying,
    bool? isBuffering,
    bool? isSeeking,
    double? rate,
    double? volume,
  }) => PlaybackSnapshot(
    phase: phase ?? this.phase,
    generation: generation ?? this.generation,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    buffered: buffered ?? this.buffered,
    desiredPlaying: desiredPlaying ?? this.desiredPlaying,
    isBuffering: isBuffering ?? this.isBuffering,
    isSeeking: isSeeking ?? this.isSeeking,
    rate: rate ?? this.rate,
    volume: volume ?? this.volume,
  );
}

enum PlayerFailureKind {
  invalidSource,
  unsupportedHeaders,
  nativePlayback,
  disposed,
}

final class PlayerFailure implements Exception {
  const PlayerFailure(this.kind, this.message, this.generation);
  final PlayerFailureKind kind;

  /// Static, safe text only; never include native errors, URLs or headers.
  final String message;
  final int generation;

  @override
  String toString() => 'PlayerFailure($kind: $message)';
}

final class PlayerCapabilities {
  const PlayerCapabilities({
    required this.externalAudio,
    required this.externalAudioHeaders,
  });
  final bool externalAudio;
  final bool externalAudioHeaders;
}

abstract interface class PlayerEngine {
  Stream<PlaybackSnapshot> get snapshots;
  Stream<PlayerFailure> get failures;
  PlaybackSnapshot get currentSnapshot;
  PlayerCapabilities get capabilities;
  Future<void> open(ResolvedMediaSource source, OpenOptions options);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration target);
  Future<void> setRate(double rate);
  Future<void> setVolume(double volume);
  Future<void> stop();
  Future<void> dispose();
}

/// Implemented by engines that can supply a Flutter video surface.
abstract interface class VideoSurfaceSource {
  Widget buildVideoSurface();
}
