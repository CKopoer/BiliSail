import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/watch_later_queue.dart';

final watchLaterQueueRegistryProvider = Provider<WatchLaterQueueRegistry>(
  (ref) => WatchLaterQueueRegistry(),
);

/// Opaque route IDs refer only to bounded, process-local read snapshots.
final class WatchLaterQueueRegistry {
  static const maximumQueues = 16;
  static const maximumItems = 1000;
  final Map<String, WatchLaterQueue> _queues = {};
  final Map<String, int> _active = {};
  final String _nonce = _newNonce();
  int _nextId = 0;

  static String _newNonce() {
    final random = Random.secure();
    return List.generate(
      12,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  WatchLaterQueue? capture({
    required String scope,
    required int sessionEpoch,
    required List<WatchLaterQueueItem> items,
  }) {
    if (!scope.startsWith('user:') || items.isEmpty) return null;
    _purgeOtherSessions(scope, sessionEpoch);
    final id = 'watch-later-$_nonce-${++_nextId}';
    final queue = WatchLaterQueue(
      id: id,
      scope: scope,
      sessionEpoch: sessionEpoch,
      items: items.take(maximumItems).toList(),
    );
    _queues[id] = queue;
    _trim();
    return queue;
  }

  /// Cached playback tabs hold their snapshot even if newer queues are opened.
  void retain(String id) {
    if (_queues.containsKey(id)) _active[id] = (_active[id] ?? 0) + 1;
  }

  void release(String id) {
    final count = _active[id];
    if (count == null) return;
    if (count <= 1) {
      _active.remove(id);
    } else {
      _active[id] = count - 1;
    }
    _trim();
  }

  void _trim() {
    while (_queues.length > maximumQueues) {
      final evict = _queues.keys
          .where((id) => !_active.containsKey(id))
          .firstOrNull;
      if (evict == null) break;
      _queues.remove(evict);
    }
  }

  WatchLaterQueue? resolve(
    String? id, {
    required String scope,
    required int sessionEpoch,
  }) {
    if (id == null) return null;
    _purgeOtherSessions(scope, sessionEpoch);
    final queue = _queues[id];
    return queue?.scope == scope && queue?.sessionEpoch == sessionEpoch
        ? queue
        : null;
  }

  void _purgeOtherSessions(String scope, int epoch) {
    for (final id in _queues.keys.toList()) {
      final queue = _queues[id]!;
      if (queue.scope != scope || queue.sessionEpoch != epoch) {
        _queues.remove(id);
        _active.remove(id);
      }
    }
  }
}
