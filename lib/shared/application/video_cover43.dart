import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_requests.dart';
import '../../domain/app_failure.dart';
import '../../domain/request_cancellation.dart';
import '../../domain/video.dart';
import '../../domain/video_cover_repository.dart';

final videoCoverRepositoryProvider = Provider<VideoCoverRepository?>(
  (ref) => null,
);

final videoCoverSessionEpochProvider = Provider(
  (ref) => ref.watch(sessionEpochProvider)(),
);

final _coverBatchesProvider = Provider.autoDispose<_CoverBatches?>((ref) {
  final repository = ref.watch(videoCoverRepositoryProvider);
  if (repository == null) return null;
  ref.watch(videoCoverSessionEpochProvider);
  final batches = _CoverBatches(repository);
  ref.onDispose(batches.dispose);
  return batches;
});

final videoCover43Provider = FutureProvider.autoDispose.family<Uri?, VideoId>((
  ref,
  id,
) {
  return ref.watch(_coverBatchesProvider)?.load(id, ref);
}, retry: (_, _) => null);

final class _CoverBatches {
  _CoverBatches(this.repository);

  static const _batchSize = 30;
  static const _maximumPending = 60;
  static const _maximumCached = 256;

  final VideoCoverRepository repository;
  final _pending = <VideoId, Completer<Uri?>>{};
  final _cache = <VideoId, Uri?>{};
  Timer? _scheduled;
  RequestCancellation? _inFlight;
  final _waitingForCapacity = <Completer<void>>{};
  bool _disposed = false;

  Future<Uri?> load(VideoId id, Ref ref) async {
    if (!id.isValid) return null;
    // Capacity is temporary. Only a completed lookup can report a missing URL.
    while (_pending.length >= _maximumPending &&
        !_pending.containsKey(id) &&
        !_cache.containsKey(id)) {
      final slot = Completer<void>();
      _waitingForCapacity.add(slot);
      final unregister = ref.onDispose(() {
        if (_waitingForCapacity.remove(slot)) slot.complete();
      });
      await slot.future;
      unregister();
      if (_disposed || !ref.mounted) return null;
    }
    if (_cache.containsKey(id)) {
      final value = _cache.remove(id);
      _cache[id] = value;
      return value;
    }
    if (_pending[id] case final existing?) return existing.future;
    final completer = _pending[id] = Completer<Uri?>();
    ref.onDispose(() {
      // Rows scrolled out of the grid no longer need a place in the queue.
      if (_pending[id] != completer) return;
      _pending.remove(id);
      completer.complete(null);
      _notifyCapacity();
    });
    _schedule();
    return completer.future;
  }

  void _notifyCapacity() {
    for (final slot in _waitingForCapacity) {
      slot.complete();
    }
    _waitingForCapacity.clear();
  }

  void _schedule() {
    if (_scheduled != null || _inFlight != null || _pending.isEmpty) return;
    // Let the current frame finish mounting its cards before taking the batch.
    _scheduled = Timer(Duration.zero, _dispatch);
  }

  void _dispatch() {
    _scheduled = null;
    if (_pending.isEmpty) return;
    final cooldown = repository.cover43Cooldown;
    if (cooldown > Duration.zero) {
      _scheduled = Timer(cooldown, _dispatch);
      return;
    }
    unawaited(_loadBatch());
  }

  Future<void> _loadBatch() async {
    final ids = _pending.keys.take(_batchSize).toList(growable: false);
    final cancellation = _inFlight = RequestCancellation();
    try {
      final covers = await repository.loadCover43Urls(
        ids,
        cancellation: cancellation,
      );
      if (cancellation.isCancelled) return;
      for (final id in ids) {
        final cover = covers[id];
        _cache[id] = cover;
        if (_cache.length > _maximumCached) _cache.remove(_cache.keys.first);
        _pending.remove(id)?.complete(cover);
      }
    } on AppFailure {
      if (cancellation.isCancelled) return;
      for (final id in ids) {
        _pending.remove(id)?.complete(null);
      }
    } catch (error, stack) {
      if (cancellation.isCancelled) return;
      for (final id in ids) {
        _pending.remove(id)?.completeError(error, stack);
      }
    } finally {
      _inFlight = null;
      _notifyCapacity();
      _schedule();
    }
  }

  void dispose() {
    _disposed = true;
    _scheduled?.cancel();
    _inFlight?.cancel();
    for (final completer in _pending.values) {
      completer.complete(null);
    }
    _pending.clear();
    _cache.clear();
    _notifyCapacity();
  }
}
