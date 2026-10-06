import 'dart:convert';
import 'dart:io';

import 'package:bili_api/bili_api.dart';

/// Explicit guest-only read probe. Prints counts and public IDs, never text,
/// credentials or signed media URLs; does not send any account mutations.
Future<void> main(List<String> args) async {
  final api = BiliApiClient();
  try {
    final locator =
        args.where((arg) => !arg.startsWith('--')).firstOrNull ?? '28747';
    final episodeId = locator.startsWith('ep') ? locator.substring(2) : null;
    final season = await PgcClient(api).getSeason(
      seasonId: episodeId == null ? locator : null,
      episodeId: episodeId,
    );
    final episode = season.episodes.firstWhere(
      (episode) =>
          episode.cid != null &&
          (episodeId == null || episode.episodeId == episodeId),
    );
    final cid = episode.cid;
    if (cid == null) throw StateError('No episode content ID');
    final segmentCount = args.contains('--all-segments')
        ? ((episode.duration?.inSeconds ?? 0) / 360).ceil().clamp(1, 240)
        : 1;
    for (var segment = 1; segment <= segmentCount; segment++) {
      final comments = await api.getDanmakuSegment(cid, segment);
      final counts = <String, int>{};
      final weights = <String, int>{};
      for (final comment in comments) {
        final mode = '${comment.mode}';
        counts[mode] = (counts[mode] ?? 0) + 1;
        final weight = '${comment.weight}';
        weights[weight] = (weights[weight] ?? 0) + 1;
      }
      stdout.writeln(
        jsonEncode({
          'seasonId': season.seasonId,
          'episodeId': episode.episodeId,
          'cid': episode.cid,
          'segment': segment,
          'durationMs': episode.duration?.inMilliseconds,
          'count': comments.length,
          'modes': counts,
          'weights': weights,
          'maxLines': comments.fold<int>(
            0,
            (maximum, item) => item.content.split('\n').length > maximum
                ? item.content.split('\n').length
                : maximum,
          ),
          'firstMinuteCount': comments
              .where((e) => e.progress < const Duration(minutes: 1))
              .length,
        }),
      );
    }
  } on ApiFailure catch (error) {
    stdout.writeln(
      jsonEncode({
        'endpoint': error.endpointId,
        'category': error.category.name,
        'businessCode': error.businessCode,
      }),
    );
    exitCode = 1;
  } finally {
    api.close();
  }
}
