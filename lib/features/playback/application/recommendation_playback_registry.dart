import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/recommendation_playback_context.dart';
import '../../../domain/video.dart';

final recommendationPlaybackRegistryProvider = Provider(
  (ref) => RecommendationPlaybackRegistry(),
);

/// Route IDs refer to bounded process-local data, never to raw server track IDs.
final class RecommendationPlaybackRegistry {
  static const maximumEntries = 64;
  final _entries = <String, RecommendationPlaybackContext>{};
  final _nonce = Random.secure().nextInt(1 << 32).toRadixString(16);
  int _next = 0;

  String capture(RecommendationPlaybackContext context) {
    _entries.removeWhere((_, old) => old.sessionEpoch != context.sessionEpoch);
    final id = 'rcmd-$_nonce-${++_next}';
    _entries[id] = context;
    while (_entries.length > maximumEntries) {
      _entries.remove(_entries.keys.first);
    }
    return id;
  }

  RecommendationPlaybackContext? resolve(
    String? id,
    VideoId video,
    int epoch, {
    String? episodeId,
  }) {
    _entries.removeWhere((_, context) => context.sessionEpoch != epoch);
    final value = _entries[id];
    return value?.matches(video.value, epoch, episode: episodeId) == true
        ? value
        : null;
  }
}
