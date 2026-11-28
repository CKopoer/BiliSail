import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../../../core/platform/system_media_controls.dart';
import 'listening_sleep_timer.dart';
import 'playback_session.dart';
import 'playback_system_media_controller.dart';

final playbackManagerProvider = Provider<PlaybackManager?>((ref) => null);

/// Owns one independent session per open playback page. Single-page navigation
/// suspends other sessions without replacing their source or user intent.
final class PlaybackManager extends ChangeNotifier {
  PlaybackManager({
    required this._createSession,
    SystemMediaControls? systemMediaControls,
    DateTime Function()? sleepTimerNow,
  }) {
    sleepTimer = ListeningSleepTimer(
      now: sleepTimerNow,
      onElapsed: () {
        for (final session in _sessions.values.toList()) {
          session.pauseForSleepTimer();
        }
      },
    );
    if (systemMediaControls != null) {
      _systemMedia = PlaybackSystemMediaController(this, systemMediaControls);
    }
  }

  PlaybackSystemMediaController? _systemMedia;
  Iterable<PlaybackSession> get sessions => _sessions.values;
  PlaybackSession? get selectedSession => _sessions[_selectedTabId];
  PlaybackSession? sessionFor(String tabId) => _sessions[tabId];
  // A page can release its session while Flutter is unmounting widgets.
  // Deliver membership changes to the tab strip after that frame.
  final _sessionChanges = StreamController<void>.broadcast();
  Stream<void> get sessionChanges => _sessionChanges.stream;

  late final ListeningSleepTimer sleepTimer;
  final PlaybackSession Function(ListeningSleepTimer sleepTimer) _createSession;
  final _sessions = <String, PlaybackSession>{};
  final _foregroundOnly = <String, VoidCallback>{};
  // Playback arbitration waits for silence. Window destruction also waits for
  // the session's stream subscriptions and native player to be released.
  final _releases = <Future<void>, Future<void>>{};
  Future<void> _commands = Future.value();
  bool _allowConcurrent = true;
  bool _closed = false;
  String? _activeTabId;
  String? _fallbackTabId;
  String? _selectedTabId;
  int _revision = 0;

  PlaybackSession acquire(String tabId, {bool foregroundOnly = false}) {
    if (_closed) throw StateError('PlaybackManager is closed');
    return _sessions.putIfAbsent(tabId, () {
      final session = _createSession(sleepTimer);
      if (foregroundOnly) {
        void intentChanged() {
          if (_closed || _activeTabId != tabId || _fallbackTabId == null) {
            return;
          }
          if (_refreshSelection()) {
            notifyListeners();
            unawaited(_applyPolicy());
          }
        }

        session.addListener(intentChanged);
        _foregroundOnly[tabId] = intentChanged;
      }
      if (!_allowConcurrent || foregroundOnly) {
        // Block autoplay immediately, including sources still being resolved.
        unawaited(session.setPlaybackAllowed(false));
      }
      scheduleMicrotask(() {
        if (_closed || !identical(_sessions[tabId], session)) return;
        _refreshSelection();
        notifyListeners();
        _sessionChanges.add(null);
        unawaited(_applyPolicy());
      });
      return session;
    });
  }

  Future<void> updateWorkspace({
    required bool allowConcurrent,
    required String activeTabId,
    String? fallbackTabId,
  }) {
    if (_closed) return Future.value();
    if (_allowConcurrent == allowConcurrent &&
        _activeTabId == activeTabId &&
        _fallbackTabId == fallbackTabId) {
      return _commands;
    }
    _allowConcurrent = allowConcurrent;
    _activeTabId = activeTabId;
    _fallbackTabId = fallbackTabId;
    _refreshSelection();
    notifyListeners();
    return _applyPolicy();
  }

  bool _refreshSelection() {
    final active = _sessions[_activeTabId];
    final fallback = _fallbackTabId;
    final selected = fallback != null && active?.hasPlaybackIntent != true
        ? fallback
        : active != null
        ? _activeTabId
        : _selectedTabId;
    if (_selectedTabId == selected) return false;
    _selectedTabId = selected;
    return true;
  }

  bool _canPlay(String owner) =>
      (!_foregroundOnly.containsKey(owner) || owner == _activeTabId) &&
      (_allowConcurrent || owner == _selectedTabId);

  Future<void> _applyPolicy() {
    final revision = ++_revision;
    final blocked = <Future<void>>[
      for (final entry in _sessions.entries)
        if (!_canPlay(entry.key)) entry.value.setPlaybackAllowed(false),
      if (!_allowConcurrent) ..._releases.values,
    ];
    final operation = _commands.then((_) async {
      // Complete outgoing pauses before permitting another native engine.
      await Future.wait(blocked);
      if (_closed || revision != _revision) return;
      await Future.wait([
        for (final entry in _sessions.entries)
          if (_canPlay(entry.key)) entry.value.setPlaybackAllowed(true),
      ]);
    });
    _commands = operation.then((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  void release(String tabId, PlaybackSession session) {
    if (!identical(_sessions[tabId], session)) return;
    _sessions.remove(tabId);
    if (_foregroundOnly.remove(tabId) case final listener?) {
      session.removeListener(listener);
    }
    if (_sessions.isEmpty) sleepTimer.cancel();
    if (_selectedTabId == tabId) _selectedTabId = null;
    final stopped = Completer<void>();
    final closing = session.close(onPlaybackStopped: stopped.complete);
    _releases[closing] = Future.any([stopped.future, closing]);
    unawaited(closing.whenComplete(() => _releases.remove(closing)));
    final selectedChanged = _refreshSelection();
    notifyListeners();
    _sessionChanges.add(null);
    if (selectedChanged) unawaited(_applyPolicy());
  }

  /// Waits for unmounted pages' native engines, leaving retained sessions alone.
  Future<void> drainReleases() async {
    await Future.wait(_releases.keys.toList());
  }

  Future<void> pauseAll() async {
    await Future.wait([
      for (final session in _sessions.values.toList()) session.pause(),
    ]);
  }

  Future<void> stop() async {
    ++_revision;
    sleepTimer.cancel();
    _systemMedia?.clear();
    await Future.wait([for (final session in _sessions.values) session.stop()]);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    ++_revision;
    sleepTimer.cancel();
    final sessions = _sessions.values.toList();
    try {
      final systemMedia = _systemMedia;
      if (systemMedia != null) await systemMedia.close();
    } finally {
      for (final entry in _foregroundOnly.entries) {
        _sessions[entry.key]?.removeListener(entry.value);
      }
      _foregroundOnly.clear();
      _sessions.clear();
      try {
        await _commands;
        await Future.wait([
          ..._releases.keys,
          for (final session in sessions) session.close(),
        ]);
      } finally {
        sleepTimer.dispose();
        await _sessionChanges.close();
        super.dispose();
      }
    }
  }
}
