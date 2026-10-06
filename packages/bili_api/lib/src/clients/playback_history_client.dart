import '../api_client.dart';
import '../models.dart';

/// Web Cookie history. Reads return milliseconds; heartbeat writes use seconds.
final class PlaybackHistoryClient {
  const PlaybackHistoryClient(this.api);
  final BiliApiClient api;

  Future<Duration?> read(
    String bvid,
    String cid, {
    String? episodeId,
    String? seasonId,
    ApiRequestContext? context,
  }) async {
    _identity(bvid, cid, episodeId, seasonId);
    const endpoint = 'playback_history_read';
    final data = await api.requestWbiJson(
      '/x/player/wbi/v2',
      {'bvid': bvid, 'cid': cid, 'ep_id': ?episodeId, 'season_id': ?seasonId},
      endpoint,
      context: context,
    );
    final time = data['last_play_time'];
    final lastCid = data['last_play_cid'];
    if (time == null && lastCid == null) return null;
    if (time is! int || time < -1 || time > 7 * 24 * 60 * 60 * 1000) {
      throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    final id = switch (lastCid) {
      int value when value >= 0 => '$value',
      String value when RegExp(r'^[0-9]+$').hasMatch(value) => value,
      _ => throw const ApiFailure(ApiFailureCategory.protocol, endpoint),
    };
    // The endpoint returns the latest part. Never jump another part's timeline.
    if (id != cid || id == '0') return null;
    return time <= 0 ? Duration.zero : Duration(milliseconds: time);
  }

  Future<void> report(
    String bvid,
    String cid, {
    required Duration position,
    required Duration duration,
    required bool completed,
    String? episodeId,
    String? seasonId,
    ApiRequestContext? context,
  }) async {
    _identity(bvid, cid, episodeId, seasonId);
    if (duration <= Duration.zero || position < Duration.zero) {
      throw ArgumentError('Invalid playback time');
    }
    await api.submitForm(
      '/x/click-interface/web/heartbeat',
      'playback_history_report',
      {
        'bvid': bvid,
        'cid': cid,
        'played_time': completed
            ? '-1'
            : '${position.inSeconds.clamp(0, duration.inSeconds)}',
        'video_duration': '${duration.inSeconds}',
        'type': episodeId == null ? '3' : '4',
        'epid': ?episodeId,
        'sid': ?seasonId,
      },
      context: context,
    );
  }

  static void _identity(
    String bvid,
    String cid,
    String? episode,
    String? season,
  ) {
    if (!RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(bvid) ||
        [
          cid,
          ?episode,
          ?season,
        ].any((id) => !RegExp(r'^[1-9][0-9]*$').hasMatch(id))) {
      throw ArgumentError('Invalid playback identity');
    }
  }
}
