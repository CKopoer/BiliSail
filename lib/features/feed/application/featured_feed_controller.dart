import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/recommendation_settings.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../domain/feed_repository.dart';

/// One bounded feed per viewing session. Positions stay stable when old cards expire.
class FeaturedFeedController extends ChangeNotifier {
  FeaturedFeedController(
    this.repository,
    this.source,
    this.filter, {
    this.seed,
  }) {
    if (seed case final first?) {
      _items.add(
        VideoSummary(
          id: first.video,
          previewCid: first.cid,
          title: '',
          coverUrl: '',
          author: '',
          duration: Duration.zero,
        ),
      );
      _remember((first.video, first.cid));
    }
  }
  final FeaturedFeedRepository repository;
  final FeaturedSource source;
  final RecommendationFilter filter;
  final FeaturedSeed? seed;
  final _items = <VideoSummary>[];
  final _seen = <(VideoId, String?)>{};
  RequestCancellation? _request;
  Future<void>? _loading;
  int refreshRevision = 0;
  int first = 0, selected = 0, _batch = 1;
  bool active = false, hasMore = true, _refreshPending = false;
  String? error;
  bool get busy => _request != null;
  int get end => first + _items.length;
  VideoSummary? at(int position) =>
      position >= first && position < end ? _items[position - first] : null;

  void setActive(bool value, {bool reload = false}) {
    final changed = active != value;
    active = value;
    if (active && reload) {
      unawaited(refresh());
    } else if (!changed) {
      return;
    } else if (!active) {
      _request?.cancel();
      _request = null;
      _loading = null;
    } else if (error == null) {
      unawaited(prefetch());
    }
  }

  void select(int position) {
    if (!active || position == selected || at(position) == null) return;
    selected = position;
    notifyListeners();
    unawaited(prefetch());
  }

  void _remember((VideoId, String?) key) {
    _seen.add(key);
    if (_seen.length > 128) _seen.remove(_seen.first);
  }

  Future<void> refresh() {
    _request?.cancel();
    _request = null;
    _loading = null;
    _refreshPending = true;
    _batch = 1;
    return load();
  }

  Future<void> prefetch() async {
    if (end - selected <= 3 && error == null && hasMore) await load();
  }

  Future<void> load() {
    if (!active || (!hasMore && !_refreshPending)) return Future.value();
    if (busy) return _loading ?? Future.value();
    return _loading = _load();
  }

  Future<void> _load() async {
    final request = _request = RequestCancellation();
    error = null;
    notifyListeners();
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final replacing = _refreshPending;
        final batch = _batch;
        final page = await repository.loadFeatured(
          source: source,
          batch: batch,
          refresh: replacing && batch == 1,
          seed: seed,
          cancellation: request,
        );
        if (request.isCancelled) return;
        final next = <VideoSummary>[];
        final keys = <(VideoId, String?)>{};
        for (final video in page.items) {
          final key = (video.id, video.previewCid);
          final repeatsSeed =
              !replacing &&
              seed?.cid == null &&
              seed?.video == video.id &&
              _items.any((item) => item.id == video.id);
          if (filter.allows(video, RecommendationSurface.recommended) &&
              (replacing || !_seen.contains(key)) &&
              !repeatsSeed &&
              keys.add(key)) {
            next.add(video);
          }
        }
        _batch = batch + 1;
        if (next.isEmpty) {
          if (!replacing) hasMore = page.hasMore;
          if (!page.hasMore || attempt == 1) {
            if (replacing || page.hasMore) error = '本批没有符合条件的视频';
            if (replacing && !page.hasMore) _batch = 1;
            break;
          }
          continue;
        }
        if (replacing) {
          _items.clear();
          _seen.clear();
          first = 0;
          selected = 0;
          _refreshPending = false;
          refreshRevision++;
        }
        hasMore = page.hasMore;
        keys.forEach(_remember);
        _items.addAll(next);
        final excess = _items.length - 60;
        if (excess > 0) {
          final evict = excess.clamp(0, selected - first);
          _items.removeRange(0, evict);
          first += evict;
          if (_items.length > 60) _items.removeRange(60, _items.length);
        }
        break;
      }
    } on AppFailure catch (failure) {
      if (!request.isCancelled) error = failure.message;
    } catch (_) {
      if (!request.isCancelled) error = '精选加载失败，请重试';
    } finally {
      if (identical(_request, request)) {
        _request = null;
        _loading = null;
        notifyListeners();
        // A sparse first batch must still give a touch user a next page.
        if (active && hasMore && error == null && end - selected <= 3) {
          scheduleMicrotask(prefetch);
        }
      }
    }
  }

  @override
  void dispose() {
    active = false;
    _request?.cancel();
    _request = null;
    super.dispose();
  }
}
