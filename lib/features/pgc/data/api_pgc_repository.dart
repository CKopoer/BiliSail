import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/pgc_repository.dart';

final class ApiPgcRepository implements PgcRepository {
  factory ApiPgcRepository(
    PgcClient client,
    ApiRequests requests, {
    required String Function() accountScope,
  }) => ApiPgcRepository._(client, requests, accountScope);

  ApiPgcRepository._(this.client, this.requests, this._accountScope);

  final PgcClient client;
  final ApiRequests requests;
  final String Function() _accountScope;

  @override
  String get accountScope => _accountScope();
  @override
  int get sessionEpoch => requests.sessionEpoch;

  @override
  Future<PgcSeason> detail({
    PgcSeasonId? seasonId,
    PgcEpisodeId? episodeId,
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    final result = await client.getSeason(
      seasonId: seasonId?.value,
      episodeId: episodeId?.value,
      context: context,
    );
    return PgcSeason(
      id: PgcSeasonId(result.seasonId),
      title: result.title,
      coverUrl: result.coverUrl,
      description: result.description,
      type: result.type,
      rating: result.rating,
      playCount: result.playCount,
      danmakuCount: result.danmakuCount,
      followCount: result.followCount,
      publishText: result.publishText,
      relatedSeasons: result.relatedSeasons
          .map(
            (related) => PgcSeasonSummary(
              id: PgcSeasonId(related.seasonId),
              title: related.title,
              coverUrl: related.coverUrl,
            ),
          )
          .toList(growable: false),
      episodes: result.episodes
          .map(
            (episode) => PgcEpisode(
              id: PgcEpisodeId(episode.episodeId),
              aid: episode.aid,
              bvid: episode.bvid,
              cid: episode.cid,
              title: episode.title,
              longTitle: episode.longTitle,
              coverUrl: episode.coverUrl,
              duration: episode.duration,
              badge: episode.badge,
              sectionTitle: episode.sectionTitle,
              available: episode.playable,
              permissionText: episode.permissionText,
            ),
          )
          .toList(growable: false),
    );
  }, cancellation: cancellation);
}
