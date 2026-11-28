import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/video.dart';
import '../domain/featured_playback_limits.dart';

typedef FeaturedQualityRequest = ({
  int quality,
  Future<ApiPlayInfo> Function(ApiPlayInfo, RequestCancellation) load,
});

/// Holds only speculative original-language playurl responses. Track selection
/// and the normal playurl fallback still run with the foreground preferences.
final class FeaturedPlayInfoCache {
  FeaturedPlayInfoCache(this.requests, this.load, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final ApiRequests requests;
  final Future<ApiPlayInfo> Function(VideoId, String, RequestCancellation) load;
  final DateTime Function() _now;
  final _entries = <(VideoId, String), _PreparedInfo>{};

  /// The returned lease belongs to the visible feed while the card is in its three-card window.
  void Function() prepare(
    VideoId video,
    String cid, {
    bool neighbor = false,
    bool forStandby = false,
  }) {
    final key = (video, cid);
    var entry = _entries[key];
    if (entry != null && _stale(entry)) {
      entry.token.cancel();
      entry = null;
    }
    if (entry == null) {
      // Two visible windows may each hold the current and both neighbors.
      if (_entries.length >= 6) _entries.values.first.token.cancel();
      final created = _PreparedInfo(_now());
      _entries[key] = created;
      final untrack = requests.trackLifetime(created.token);
      created.token.onCancel(() {
        if (identical(_entries[key], created)) _entries.remove(key);
        untrack();
      });
      created.info = _load(video, cid, created.token);
      // The prefetch may leave the visible window before selection.
      created.info.ignore();
      entry = created;
    }
    // Moving away makes the same result available for a quick reverse swipe.
    // Within one visit a retry or quality change must resolve a fresh playurl.
    if (neighbor) entry.claimed = false;
    final leased = entry;
    leased.leases++;
    if (forStandby) leased.standbyLeases++;
    return () {
      if (forStandby) leased.standbyLeases--;
      if (--leased.leases == 0) {
        leased.token.cancel();
      }
    };
  }

  Future<ApiPlayInfo?> _load(
    VideoId video,
    String cid,
    RequestCancellation token,
  ) async {
    try {
      return await load(video, cid, token);
    } on AppFailure {
      // A speculative read has no error UI. Selection uses the foreground
      // request and its normal authentication, risk-control and retry policy.
      return null;
    }
  }

  bool _stale(_PreparedInfo entry) =>
      _now().difference(entry.started) >=
      (entry.standbyLeases > 0
          ? featuredStandbyMaximumAge
          : const Duration(minutes: 1));

  Future<ApiPlayInfo?>? take(
    VideoId video,
    String cid,
    ApiCancellation? cancellation, {
    bool speculative = false,
    FeaturedQualityRequest? supplement,
  }) {
    final entry = _entries[(video, cid)];
    if (entry == null || (!speculative && entry.claimed)) return null;
    // A silent native warm-up reads the same DASH response without consuming
    // the foreground's claim or cancelling another reader when superseded.
    if (!speculative) entry.claimed = true;
    entry.leases++;
    return _consume(entry, speculative ? null : cancellation, supplement);
  }

  Future<ApiPlayInfo?> _consume(
    _PreparedInfo entry,
    ApiCancellation? cancellation,
    FeaturedQualityRequest? supplement,
  ) async {
    final detach = cancellation?.onCancel(entry.token.cancel);
    try {
      if (_stale(entry)) return null;
      final discovery = await entry.info;
      if (discovery == null || entry.token.isCancelled || _stale(entry)) {
        return null;
      }
      ApiPlayInfo info = discovery;
      if (supplement != null &&
          needsPlayInfoSupplement(info, supplement.quality)) {
        // Keep one quality per discovery response. A concurrent foreground
        // claim receives the signed URLs that the standby decoder opened.
        var pending = entry.supplement;
        if (pending == null || pending.quality != supplement.quality) {
          pending = entry.supplement = (
            quality: supplement.quality,
            result: supplement.load(info, entry.token),
          );
        }
        try {
          info = await pending.result;
        } finally {
          // A failed or incomplete optional read can be retried on selection.
          if (entry.supplement == pending &&
              needsPlayInfoSupplement(info, pending.quality)) {
            entry.supplement = null;
          }
        }
        if (entry.token.isCancelled || _stale(entry)) return null;
      }
      final minimumDeadline =
          _now().add(const Duration(seconds: 15)).millisecondsSinceEpoch ~/
          1000;
      for (final track in [
        ...info.dashVideo,
        ...info.dashAudio,
        ?info.progressive,
      ]) {
        for (final url in [track.url, ...track.backupUrls]) {
          final deadline = int.tryParse(url.queryParameters['deadline'] ?? '');
          if (deadline != null && deadline <= minimumDeadline) return null;
        }
      }
      return info;
    } finally {
      detach?.call();
      if (--entry.leases == 0) entry.token.cancel();
    }
  }
}

final class _PreparedInfo {
  _PreparedInfo(this.started);
  final DateTime started;
  final token = RequestCancellation();
  late final Future<ApiPlayInfo?> info;
  ({int quality, Future<ApiPlayInfo> result})? supplement;
  int leases = 0;
  int standbyLeases = 0;
  bool claimed = false;
}

bool needsPlayInfoSupplement(ApiPlayInfo info, int quality) =>
    info.dashVideo.any((track) => track.id > quality) &&
    info.acceptQuality.contains(quality) &&
    !info.dashVideo.any((track) => track.id == quality);
