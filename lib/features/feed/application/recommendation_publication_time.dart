import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../domain/feed_repository.dart';
import 'feed_controller.dart';

final _publicationTimesProvider = Provider<RecommendationPublicationTimes?>((
  ref,
) {
  final repository = ref.watch(feedRepositoryProvider);
  if (repository is! RecommendationPublicationTimeRepository) return null;
  final times = RecommendationPublicationTimes(
    repository: repository as RecommendationPublicationTimeRepository,
    sessionEpoch: ref.watch(sessionEpochProvider),
  );
  ref.onDispose(times.dispose);
  return times;
});

final recommendationPublicationTimeProvider = FutureProvider.autoDispose
    .family<DateTime?, VideoId>((ref, id) {
      final cancellation = RequestCancellation();
      ref.onDispose(cancellation.cancel);
      return ref.watch(_publicationTimesProvider)?.load(id, cancellation);
    }, retry: (_, _) => null);

/// Loads only mounted cards, without holding up the recommendation page.
final class RecommendationPublicationTimes {
  RecommendationPublicationTimes({
    required this.repository,
    required this.sessionEpoch,
  });

  static const maximumConcurrentRequests = 4;
  static const maximumQueuedRequests = 64;
  static const maximumCachedEntries = 256;
  static const _cancelled = AppFailure(AppFailureKind.cancelled, '请求已取消');

  final RecommendationPublicationTimeRepository repository;
  final int Function() sessionEpoch;
  final _cache = <VideoId, DateTime?>{};
  final _queue = Queue<_PublicationTimeRequest>();
  final _active = <_PublicationTimeRequest>{};
  int? _cacheEpoch;
  bool _disposed = false;

  Future<DateTime?> load(VideoId id, RequestCancellation cancellation) {
    if (_disposed || cancellation.isCancelled) return Future.error(_cancelled);
    if (!id.isValid) return Future.value(null);
    final epoch = sessionEpoch();
    if (_cacheEpoch != epoch) {
      _cache.clear();
      _cacheEpoch = epoch;
    }
    if (_cache.containsKey(id)) {
      final value = _cache.remove(id);
      _cache[id] = value;
      return Future.value(value);
    }
    if (_queue.length >= maximumQueuedRequests) {
      return Future.error(
        const AppFailure(AppFailureKind.rateLimited, '发布时间请求过多'),
      );
    }
    final request = _PublicationTimeRequest(id, epoch, cancellation);
    _queue.add(request);
    cancellation.onCancel(() {
      if (_queue.remove(request)) request.result.completeError(_cancelled);
    });
    _drain();
    return request.result.future;
  }

  void _drain() {
    while (!_disposed &&
        _active.length < maximumConcurrentRequests &&
        _queue.isNotEmpty) {
      final request = _queue.removeFirst();
      _active.add(request);
      unawaited(_load(request));
    }
  }

  Future<void> _load(_PublicationTimeRequest request) async {
    try {
      if (request.epoch != sessionEpoch()) throw _cancelled;
      final date = await repository.loadPublicationTime(
        request.id,
        cancellation: request.cancellation,
      );
      if (_disposed ||
          request.cancellation.isCancelled ||
          request.epoch != sessionEpoch()) {
        throw _cancelled;
      }
      _cache[request.id] = date;
      while (_cache.length > maximumCachedEntries) {
        _cache.remove(_cache.keys.first);
      }
      request.result.complete(date);
    } catch (error, stack) {
      request.result.completeError(error, stack);
    } finally {
      _active.remove(request);
      _drain();
    }
  }

  void dispose() {
    _disposed = true;
    for (final request in [..._queue, ..._active]) {
      request.cancellation.cancel();
    }
    _cache.clear();
  }
}

final class _PublicationTimeRequest {
  _PublicationTimeRequest(this.id, this.epoch, this.cancellation);
  final VideoId id;
  final int epoch;
  final RequestCancellation cancellation;
  final result = Completer<DateTime?>();
}
