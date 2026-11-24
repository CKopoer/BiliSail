import 'dart:async';

import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/pgc_repository.dart';
import 'pgc_season_mapper.dart';

final class ApiPgcRepository implements PgcRepository {
  factory ApiPgcRepository(
    PgcClient client,
    ApiRequests requests, {
    required String Function() accountScope,
    DateTime Function()? clock,
    Duration cacheTtl = const Duration(minutes: 2),
    int maxCachedSeasons = 8,
    int maxPendingSeasons = 8,
    bool course = false,
  }) => ApiPgcRepository._(
    client,
    requests,
    accountScope,
    clock ?? DateTime.now,
    cacheTtl,
    maxCachedSeasons,
    maxPendingSeasons,
    course,
  );

  ApiPgcRepository._(
    this.client,
    this.requests,
    this._accountScope,
    this._clock,
    this.cacheTtl,
    this.maxCachedSeasons,
    this.maxPendingSeasons,
    this.course,
  ) {
    if (maxCachedSeasons < 1 ||
        maxPendingSeasons < 1 ||
        cacheTtl <= Duration.zero) {
      throw ArgumentError('PGC cache and request limits must be positive');
    }
  }

  final bool course;
  final PgcClient client;
  final ApiRequests requests;
  final String Function() _accountScope;
  final DateTime Function() _clock;
  final Duration cacheTtl;
  final int maxCachedSeasons, maxPendingSeasons;
  final _cache = <PgcSeasonId, _SeasonCacheEntry>{};
  final _episodeSeasons = <PgcEpisodeId, PgcSeasonId>{};
  final _pending = <String, _SeasonFlight>{};
  final _flights = <_SeasonFlight>{};
  String? _scope;
  int? _epoch;
  int _cacheGeneration = 0;
  RequestCancellation? _lifetime;
  void Function()? _untrackLifetime;

  @override
  String get accountScope => _accountScope();
  @override
  int get sessionEpoch => requests.sessionEpoch;

  @override
  Future<PgcSeason> detail({
    PgcSeasonId? seasonId,
    PgcEpisodeId? episodeId,
    bool refresh = false,
    required RequestCancellation cancellation,
  }) async {
    if (cancellation.isCancelled) throw _cancelled;
    _syncScope();
    _pruneExpired();
    final knownSeason = seasonId ?? _episodeSeasons[episodeId];
    final cached = _cache[knownSeason];
    final matchesEpisode =
        episodeId == null || cached?.season.episode(episodeId) != null;
    if (!refresh && cached != null && matchesEpisode) {
      _cache.remove(knownSeason);
      _cache[cached.season.id] = cached;
      return cached.season;
    }
    // A refresh never joins a request begun before the user's refresh action.
    // Older callers may finish, but their results cannot repopulate this cache.
    if (refresh) {
      _cacheGeneration++;
      if (knownSeason != null) _evict(knownSeason);
    }
    final key = knownSeason != null && (episodeId == null || matchesEpisode)
        ? 'ss:${knownSeason.value}'
        : 'ss:${seasonId?.value ?? ''}/ep:${episodeId?.value ?? ''}';
    var flight = refresh ? null : _pending[key];
    if (flight == null || flight.cancellation.isCancelled) {
      if (_flights.length >= maxPendingSeasons) {
        throw AppFailure(
          AppFailureKind.rateLimited,
          course ? '课程详情请求繁忙，请稍后重试' : '影视详情请求繁忙，请稍后重试',
        );
      }
      flight = _SeasonFlight();
      _pending[key] = flight;
      _flights.add(flight);
      flight.result = _load(
        flight,
        key,
        seasonId,
        episodeId,
        accountScope,
        sessionEpoch,
        _cacheGeneration,
      );
    }
    return _join(flight, cancellation);
  }

  Future<PgcSeason> _load(
    _SeasonFlight flight,
    String key,
    PgcSeasonId? seasonId,
    PgcEpisodeId? episodeId,
    String scope,
    int epoch,
    int generation,
  ) async {
    try {
      final season = await requests.run((context) async {
        final result = await client.getSeason(
          seasonId: seasonId?.value,
          episodeId: episodeId?.value,
          course: course,
          requireEpisodes: episodeId != null,
          context: context,
        );
        if (course &&
            episodeId != null &&
            !result.episodes.any((ep) => ep.episodeId == episodeId.value)) {
          throw const AppFailure(AppFailureKind.notFound, '未找到指定的课时');
        }
        return mapApiPgcSeason(result);
      }, cancellation: flight.cancellation);
      if (flight.cancellation.isCancelled ||
          scope != accountScope ||
          epoch != sessionEpoch) {
        throw _cancelled;
      }
      // A season-only request may legitimately have no published episodes.
      // Do not cache that result, so reopening can see a newly available list.
      if (generation == _cacheGeneration && season.episodes.isNotEmpty) {
        _evict(season.id);
        _cache[season.id] = _SeasonCacheEntry(season, _clock().add(cacheTtl));
        for (final episode in season.episodes) {
          _episodeSeasons[episode.id] = season.id;
        }
        while (_cache.length > maxCachedSeasons) {
          _evict(_cache.keys.first);
        }
      }
      return season;
    } finally {
      flight.completed = true;
      _flights.remove(flight);
      if (identical(_pending[key], flight)) _pending.remove(key);
    }
  }

  Future<PgcSeason> _join(
    _SeasonFlight flight,
    RequestCancellation cancellation,
  ) async {
    flight.consumers++;
    var released = false;
    final cancelled = Completer<PgcSeason>();
    void release() {
      if (released) return;
      released = true;
      flight.consumers--;
      if (flight.consumers == 0 && !flight.completed) {
        flight.cancellation.cancel();
      }
    }

    cancellation.onCancel(() {
      if (released) return;
      release();
      cancelled.completeError(_cancelled);
    });
    try {
      return await Future.any([flight.result, cancelled.future]);
    } finally {
      release();
    }
  }

  void _syncScope() {
    if (_scope == accountScope &&
        _epoch == sessionEpoch &&
        _lifetime?.isCancelled == false) {
      return;
    }
    _untrackLifetime?.call();
    _lifetime?.cancel();
    _clear();
    _scope = accountScope;
    _epoch = sessionEpoch;
    final lifetime = RequestCancellation()..onCancel(_clear);
    _lifetime = lifetime;
    _untrackLifetime = requests.trackLifetime(lifetime);
  }

  void _clear() {
    _cacheGeneration++;
    _cache.clear();
    _episodeSeasons.clear();
    _pending.clear();
    for (final flight in _flights) {
      flight.cancellation.cancel();
    }
  }

  void _pruneExpired() {
    final now = _clock();
    for (final id in _cache.keys.toList(growable: false)) {
      if (!_cache[id]!.expires.isAfter(now)) _evict(id);
    }
  }

  void _evict(PgcSeasonId id) {
    final old = _cache.remove(id);
    if (old == null) return;
    for (final episode in old.season.episodes) {
      if (_episodeSeasons[episode.id] == id) _episodeSeasons.remove(episode.id);
    }
  }

  static const _cancelled = AppFailure(AppFailureKind.cancelled, '请求已取消');
}

final class _SeasonCacheEntry {
  const _SeasonCacheEntry(this.season, this.expires);
  final PgcSeason season;
  final DateTime expires;
}

final class _SeasonFlight {
  final cancellation = RequestCancellation();
  late final Future<PgcSeason> result;
  int consumers = 0;
  bool completed = false;
}
