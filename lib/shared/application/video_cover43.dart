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
  return ref.watch(_coverBatchesProvider)?.load(id);
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

  Future<Uri?> load(VideoId id) {
    if (_cache.containsKey(id)) {
      final value = _cache.remove(id);
      _cache[id] = value;
      return Future.value(value);
    }
    if (_pending[id] case final existing?) return existing.future;
    if (!id.isValid || _pending.length >= _maximumPending) {
      return Future.value(null);
    }
    final completer = _pending[id] = Completer<Uri?>();
    _schedule();
    return completer.future;
  }

  void _schedule() {
    if (_scheduled != null || _inFlight != null || _pending.isEmpty) return;
    // Let the current frame finish mounting its cards before taking the batch.
    _scheduled = Timer(Duration.zero, () {
      _scheduled = null;
      unawaited(_loadBatch());
    });
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
      _schedule();
    }
  }

  void dispose() {
    _scheduled?.cancel();
    _inFlight?.cancel();
    for (final completer in _pending.values) {
      completer.complete(null);
    }
    _pending.clear();
    _cache.clear();
  }
}
