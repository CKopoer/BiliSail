import 'package:bili_player/bili_player.dart';
import 'package:flutter/foundation.dart';

import '../../../core/platform/system_media_controls.dart';
import 'playback_manager.dart';
import 'playback_session.dart';

/// Chooses one system control target from the existing page-owned sessions.
final class PlaybackSystemMediaController {
  PlaybackSystemMediaController(this.manager, this.controls) {
    controls.onCommand = _command;
    manager.addListener(_sessionsChanged);
    _sessionsChanged();
  }

  final PlaybackManager manager;
  final SystemMediaControls controls;
  final _listeners = <PlaybackSession, VoidCallback>{};
  PlaybackSession? _target;
  final _suppressed = <PlaybackSession, int>{};
  Object? _lastUpdate;
  String? _publishedId;
  bool _closed = false;

  void _sessionsChanged() {
    final sessions = manager.sessions.toSet();
    for (final session in _listeners.keys.toList()) {
      if (sessions.contains(session)) continue;
      final listener = _listeners.remove(session)!;
      session.removeListener(listener);
      session.snapshots.removeListener(listener);
      _suppressed.remove(session);
    }
    for (final session in sessions) {
      if (_listeners.containsKey(session)) continue;
      void listener() => _sync();
      _listeners[session] = listener;
      session.addListener(listener);
      session.snapshots.addListener(listener);
    }
    _sync();
  }

  bool _eligible(PlaybackSession? session) =>
      session != null &&
      _listeners.containsKey(session) &&
      session.sourceMatchesAccount &&
      _suppressed[session] != session.sourceGeneration &&
      (session.isResolving || session.media != null);

  void _sync({bool force = false}) {
    if (_closed) return;
    final selected = manager.selectedSession;
    final target = _eligible(selected)
        ? selected
        : _eligible(_target)
        ? _target
        : manager.sessions.where(_eligible).lastOrNull;
    _target = target;
    if (target == null) {
      if (_publishedId != null) controls.publish(null);
      _publishedId = null;
      _lastUpdate = null;
      return;
    }
    final snapshot = target.snapshots.value;
    final id = '${identityHashCode(target)}:${target.sourceGeneration}';
    final phase = target.isResolving
        ? SystemMediaPhase.loading
        : target.error != null || snapshot.phase == PlaybackPhase.failed
        ? SystemMediaPhase.failed
        : snapshot.phase == PlaybackPhase.ended
        ? SystemMediaPhase.completed
        : snapshot.isBuffering ||
              snapshot.isSeeking ||
              snapshot.phase == PlaybackPhase.buffering
        ? SystemMediaPhase.buffering
        : SystemMediaPhase.ready;
    final playing =
        phase != SystemMediaPhase.completed &&
        phase != SystemMediaPhase.failed &&
        snapshot.desiredPlaying;
    final duration = target.isLive
        ? Duration.zero
        : snapshot.duration > Duration.zero
        ? snapshot.duration
        : target.media?.duration ?? Duration.zero;
    final summary = target.detail?.summary;
    final cover = Uri.tryParse(summary?.coverUrl ?? '');
    // Only public, unsigned artwork is handed to OS services. Never publish
    // resolved media URLs, local paths, headers or account identifiers.
    final art =
        cover != null &&
            (cover.scheme == 'http' || cover.scheme == 'https') &&
            cover.userInfo.isEmpty &&
            (cover.host == 'hdslb.com' || cover.host.endsWith('.hdslb.com'))
        ? Uri(scheme: 'https', host: cover.host, path: cover.path)
        : null;
    final update = (
      id,
      target.title,
      summary?.author,
      art,
      phase,
      playing,
      duration,
      snapshot.rate,
      snapshot.position.inSeconds,
      snapshot.buffered.inSeconds,
    );
    if (!force && update == _lastUpdate) return;
    _lastUpdate = update;
    _publishedId = id;
    controls.publish(
      SystemMediaState(
        id: id,
        title: target.title,
        artist: summary?.author,
        artUri: art,
        phase: phase,
        playing: playing,
        position: snapshot.position,
        duration: duration,
        buffered: snapshot.buffered,
        rate: snapshot.rate,
        isLive: target.isLive,
      ),
    );
  }

  Future<void> _command(SystemMediaCommand command) async {
    final target = _target;
    if (_closed || command.id != _publishedId || !_eligible(target)) return;
    final session = target!;
    if (command.id !=
        '${identityHashCode(session)}:${session.sourceGeneration}') {
      return;
    }
    switch (command.action) {
      case SystemMediaAction.play:
        await session.play();
      case SystemMediaAction.pause:
        await session.pause();
      case SystemMediaAction.stop:
        _suppressed[session] = session.sourceGeneration;
        _sync();
        await session.stop();
      case SystemMediaAction.stopAll:
        await manager.stop();
      case SystemMediaAction.seek:
        final position = command.position;
        final duration = session.snapshots.value.duration;
        if (session.isLive || position == null || duration <= Duration.zero) {
          return;
        }
        await session.seek(
          position < Duration.zero
              ? Duration.zero
              : position > duration
              ? duration
              : position,
        );
    }
    _sync(force: true);
  }

  void clear() {
    for (final session in _listeners.keys) {
      _suppressed[session] = session.sourceGeneration;
    }
    _sync();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    manager.removeListener(_sessionsChanged);
    for (final entry in _listeners.entries) {
      entry.key.removeListener(entry.value);
      entry.key.snapshots.removeListener(entry.value);
    }
    _listeners.clear();
    _suppressed.clear();
    await controls.close();
  }
}
