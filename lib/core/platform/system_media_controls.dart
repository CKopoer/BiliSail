enum SystemMediaPhase { loading, ready, buffering, completed, failed }

enum SystemMediaAction { play, pause, stop, stopAll, seek }

final class SystemMediaCommand {
  const SystemMediaCommand(this.id, this.action, {this.position});
  final String id;
  final SystemMediaAction action;
  final Duration? position;
}

final class SystemMediaState {
  const SystemMediaState({
    required this.id,
    required this.title,
    required this.phase,
    required this.playing,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.rate,
    required this.isLive,
    this.artist,
    this.artUri,
  });

  final String id, title;
  final String? artist;
  final Uri? artUri;
  final SystemMediaPhase phase;
  final bool playing, isLive;
  final Duration position, duration, buffered;
  final double rate;
  bool get canSeek => !isLive && duration > Duration.zero;
}

/// System controls observe the existing player; they never own an engine.
abstract class SystemMediaControls {
  Future<void> Function(SystemMediaCommand command)? onCommand;
  void publish(SystemMediaState? state);
  Future<void> close();
}
