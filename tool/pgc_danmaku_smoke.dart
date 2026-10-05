import 'dart:convert';
import 'dart:io';

import 'package:bili_api/bili_api.dart';

/// Explicit guest-only read probe. Prints counts and public IDs, never text,
/// credentials or signed media URLs; does not send any account mutations.
Future<void> main(List<String> args) async {
  final api = BiliApiClient();
  try {
    final season = await PgcClient(api)
        .getSeason(seasonId: args.isEmpty ? '28747' : args.first);
    final episode = season.episodes.where((e) => e.cid != null).first;
    final cid = episode.cid;
    if (cid == null) throw StateError('No episode content ID');
    final comments = await api.getDanmakuSegment(cid, 1);
    final counts = <String, int>{};
    for (final comment in comments) {
      final mode = '${comment.mode}';
      counts[mode] = (counts[mode] ?? 0) + 1;
    }
    stdout.writeln(
      jsonEncode({
        'seasonId': season.seasonId,
        'episodeId': episode.episodeId,
        'cid': episode.cid,
        'durationMs': episode.duration?.inMilliseconds,
        'count': comments.length,
        'modes': counts,
        'firstMinuteCount': comments
            .where((e) => e.progress < const Duration(minutes: 1))
            .length,
      }),
    );
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
