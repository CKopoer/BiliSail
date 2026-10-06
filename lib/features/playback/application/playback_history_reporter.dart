import 'dart:async';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/playback_history_repository.dart';

/// One write in flight, latest unsent observation per part, at most eight parts.
/// A failed write is consumed, never replayed. Later observations are new writes.
final class PlaybackHistoryReporter {
  PlaybackHistoryReporter({
    required this.repository,
    required this.accountScope,
    required this.sessionEpoch,
    required this.now,
    required this.onResult,
  });
  final PlaybackHistoryRepository repository;
  final String Function() accountScope;
  final int Function() sessionEpoch;
  final Duration Function() now;
  final void Function(int generation, AppFailure? failure) onResult;
  final _pending = <String, _Report>{};
  Future<void>? _draining;
  RequestCancellation? _cancellation;
  _Report? _last;
  Duration _lastQueuedAt = Duration.zero;
  Duration _cooldownUntil = Duration.zero;
  int? _blockedEpoch;
  bool _closed = false;

  void submit(
    PlaybackHistoryRecord record, {
    required String scope,
    required int epoch,
    required int generation,
    bool force = false,
  }) {
    if (_closed || scope != accountScope() || epoch != sessionEpoch()) return;
    if (_last != null && (_last?.scope != scope || _last?.epoch != epoch)) {
      clear();
    }
    if (!scope.startsWith('user:') ||
        _blockedEpoch == epoch ||
        now() < _cooldownUntil) {
      return;
    }
    final last = _last;
    final sameTarget = last?.record.target.key == record.target.key;
    if (sameTarget &&
        (last?.record.position.inSeconds == record.position.inSeconds &&
                last?.record.completed == record.completed ||
            !force && now() - _lastQueuedAt < const Duration(seconds: 15))) {
      return;
    }
    final report = _Report(record, scope, epoch, generation);
    _last = report;
    _lastQueuedAt = now();
    _pending[record.target.key] = report;
    if (_pending.length > 8) _pending.remove(_pending.keys.first);
    _start();
  }

  void _start() {
    if (_draining != null) return;
    // Assign the future before starting: completion callbacks may enqueue.
    _draining = Future<void>.microtask(_drain).whenComplete(() {
      _draining = null;
      if (_pending.isNotEmpty && !_closed) _start();
    });
  }

  Future<void> _drain() async {
    while (_pending.isNotEmpty && !_closed) {
      final key = _pending.keys.first;
      final report = _pending.remove(key);
      if (report == null ||
          report.scope != accountScope() ||
          report.epoch != sessionEpoch()) {
        continue;
      }
      final cancellation = RequestCancellation();
      _cancellation = cancellation;
      AppFailure? failure;
      try {
        await repository.report(
          report.record,
          scope: report.scope,
          cancellation: cancellation,
        );
      } on AppFailure catch (error) {
        failure = error;
      } catch (_) {
        failure = const AppFailure(AppFailureKind.protocol, '云端进度上报失败');
      } finally {
        if (identical(_cancellation, cancellation)) _cancellation = null;
      }
      if (cancellation.isCancelled ||
          report.scope != accountScope() ||
          report.epoch != sessionEpoch() ||
          failure?.kind == AppFailureKind.cancelled) {
        continue;
      }
      if (failure?.kind == AppFailureKind.authentication ||
          failure?.kind == AppFailureKind.permission ||
          failure?.kind == AppFailureKind.protocol) {
        _blockedEpoch = report.epoch;
        _pending.clear();
      } else if (failure?.kind == AppFailureKind.rateLimited) {
        _cooldownUntil = now() + const Duration(minutes: 1);
        _pending.clear();
      }
      onResult(report.generation, failure);
    }
  }

  void clear() {
    _cancellation?.cancel();
    _pending.clear();
    _last = null;
    _blockedEpoch = null;
    _cooldownUntil = Duration.zero;
  }

  Future<void> close({Duration timeout = const Duration(seconds: 5)}) async {
    try {
      // Shutdown has one budget for the whole queue, not one per request.
      await _draining?.timeout(timeout);
    } on TimeoutException {
      // Local progress has already been saved; cancel rather than delay exit.
    } finally {
      _closed = true;
      clear();
    }
  }
}

final class _Report {
  const _Report(this.record, this.scope, this.epoch, this.generation);
  final PlaybackHistoryRecord record;
  final String scope;
  final int epoch, generation;
}
