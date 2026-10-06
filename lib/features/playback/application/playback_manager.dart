import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'playback_session.dart';

final playbackManagerProvider = Provider<PlaybackManager?>((ref) => null);

/// Owns one independent session per open playback page. Single-page navigation
/// suspends other sessions without replacing their source or user intent.
final class PlaybackManager {
  PlaybackManager({required this._createSession});

  final PlaybackSession Function() _createSession;
  final _sessions = <String, PlaybackSession>{};
  final _releases = <Future<void>>{};
  Future<void> _commands = Future.value();
  bool _allowConcurrent = true;
  bool _closed = false;
  String? _activeTabId;
  String? _selectedTabId;
  int _revision = 0;

  PlaybackSession acquire(String tabId) {
    if (_closed) throw StateError('PlaybackManager is closed');
    return _sessions.putIfAbsent(tabId, () {
      final session = _createSession();
      if (!_allowConcurrent) {
        // Block autoplay immediately, including sources still being resolved.
        unawaited(session.setPlaybackAllowed(false));
      }
      scheduleMicrotask(() {
        if (_closed || !identical(_sessions[tabId], session)) return;
        if (_activeTabId == tabId) _selectedTabId = tabId;
        unawaited(_applyPolicy());
      });
      return session;
    });
  }

  Future<void> updateWorkspace({
    required bool allowConcurrent,
    required String activeTabId,
  }) {
    if (_closed) return Future.value();
    if (_allowConcurrent == allowConcurrent && _activeTabId == activeTabId) {
      return _commands;
    }
    _allowConcurrent = allowConcurrent;
    _activeTabId = activeTabId;
    if (_sessions.containsKey(activeTabId)) _selectedTabId = activeTabId;
    return _applyPolicy();
  }

  Future<void> _applyPolicy() {
    final revision = ++_revision;
    final blocked = <Future<void>>[
      for (final entry in _sessions.entries)
        if (!_allowConcurrent && entry.key != _selectedTabId)
          entry.value.setPlaybackAllowed(false),
    ];
    final operation = _commands.then((_) async {
      // Complete outgoing pauses before permitting another native engine.
      await Future.wait(blocked);
      if (_closed || revision != _revision) return;
      await Future.wait([
        for (final entry in _sessions.entries)
          if (_allowConcurrent || entry.key == _selectedTabId)
            entry.value.setPlaybackAllowed(true),
      ]);
    });
    _commands = operation.then((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  void release(String tabId, PlaybackSession session) {
    if (!identical(_sessions[tabId], session)) return;
    _sessions.remove(tabId);
    if (_selectedTabId == tabId) _selectedTabId = null;
    final closing = session.close();
    _releases.add(closing);
    unawaited(closing.whenComplete(() => _releases.remove(closing)));
  }

  Future<void> stop() async {
    ++_revision;
    await Future.wait([for (final session in _sessions.values) session.stop()]);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    ++_revision;
    final sessions = _sessions.values.toList();
    _sessions.clear();
    await _commands;
    await Future.wait([
      ..._releases,
      for (final session in sessions) session.close(),
    ]);
  }
}
