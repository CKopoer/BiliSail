import 'dart:async';

import 'native_readiness.dart';
import 'player_contract.dart';
import 'player_diagnostics.dart';
import 'player_playback_information.dart';
import 'validated_source.dart';
import 'video_output.dart';

/// One monotonic deadline and cancellation identity, shared across native waits.
final class PlaybackOperation {
  PlaybackOperation(this.generation, this.budget, {this.revision = 0});
  final int generation, revision;
  final Duration budget;
  final Stopwatch _watch = Stopwatch()..start();
  final _changes = StreamController<void>.broadcast(sync: true);
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  Duration get elapsed => _watch.elapsed;
  Stream<void> get changes => _changes.stream;
  void cancel() {
    if (isCancelled) return;
    _cancelled = true;
    _changes.add(null);
    unawaited(_changes.close());
  }

  void check() {
    if (isCancelled) throw const SourceSuperseded();
    if (budget - elapsed <= Duration.zero) {
      throw TimeoutException('Playback deadline');
    }
  }

  Duration get remaining {
    check();
    return budget - elapsed;
  }

  Future<T> wait<T>(Future<T> work, {Duration? timeout}) async {
    final done = Completer<T>();
    void fail(Object error, [StackTrace? stack]) {
      if (!done.isCompleted) done.completeError(error, stack);
    }

    // A subscription can be removed when a short command completes. Future.any
    // against a never-ending source cancellation future retains every command.
    final subscription = changes.listen((_) => fail(const SourceSuperseded()));
    final duration = timeout ?? budget - elapsed;
    final timer = Timer(
      duration > Duration.zero ? duration : Duration.zero,
      () => fail(TimeoutException('Playback deadline')),
    );
    unawaited(
      work.then<void>((value) {
        if (done.isCompleted) return;
        try {
          if (isCancelled) throw const SourceSuperseded();
          if (timeout == null) check();
          done.complete(value);
        } on Object catch (error, stack) {
          fail(error, stack);
        }
      }, onError: (Object error, StackTrace stack) => fail(error, stack)),
    );
    if (isCancelled) fail(const SourceSuperseded());
    try {
      return await done.future;
    } finally {
      timer.cancel();
      unawaited(subscription.cancel());
    }
  }
}

final class PreparedTracks {
  const PreparedTracks({
    required this.hasVideo,
    required this.hasAudio,
    this.externalAudioSelected = false,
    this.duration = Duration.zero,
    this.position = Duration.zero,
    this.dimensions,
  });
  final bool hasVideo, hasAudio, externalAudioSelected;
  final Duration duration, position;
  final VideoDimensions? dimensions;
}

enum BackendEventKind { sample, buffering, playing, ended, warning, failure }

/// Evidence from the current native pipeline, never a product playback state.
final class BackendEvent {
  const BackendEvent(
    this.kind, {
    this.position,
    this.duration,
    this.buffered,
    this.dimensions,
    this.value,
    this.failureKind = PlayerFailureKind.nativePlayback,
    this.stallReason,
  });
  final BackendEventKind kind;
  final Duration? position, duration, buffered;
  final VideoDimensions? dimensions;
  final bool? value;
  final PlayerFailureKind failureKind;
  final PlaybackStallReason? stallReason;
}

/// A backend may retain its native player after a fully settled source.
/// resetForNextSource must stop/unload and drain callbacks before returning.
/// Failed, cancelled and configuration-incompatible opens use full disposal.
abstract interface class ReusablePlaybackBackend {
  bool canReuse(ValidatedSource plan);
  Future<void> resetForNextSource(PlaybackOperation operation);
}

/// Package-private SDK boundary. One source is active at a time.
abstract interface class PlaybackBackend {
  VideoOutput get videoOutput;
  Stream<BackendEvent> get events;
  Duration get seekTimeout;
  Future<PreparedTracks> preparePaused(
    ValidatedSource plan,
    PlaybackOperation operation,
  );
  Future<VideoDimensions?> confirmVideo(PlaybackOperation operation);
  Future<void> confirmAudio(PlaybackOperation operation);
  Future<void> confirmPresentation(PlaybackOperation operation);
  Future<void> play();
  // False means this native pipeline cannot acknowledge a complete pause.
  // A terminal failure then needs interruption and confirmed release.
  Future<bool> pauseAndWait();
  Future<void> setRate(double rate);
  Future<void> setVolume(double volume);
  Future<void> setGainDb(double gainDb);
  // Confirms the native target, including required audio. Only the SDK adapter
  // decides whether seeking needs a pause or EOF preparation.
  Future<Duration> seekTo(Duration target, PlaybackOperation operation);
  // Completes when the SDK can accept the replacement seek safely. Preserve
  // the source and packet cache when the SDK supports native target replacement.
  Future<void> cancelSeek();
  void interrupt();
  Duration? get buffered;
  Future<PlayerPlaybackInformation?> inspectPlaybackInformation(int generation);
  Future<void> dispose();
}
