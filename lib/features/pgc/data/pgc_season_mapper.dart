import 'package:bili_api/bili_api.dart';

import '../domain/pgc_repository.dart';

PgcSeason mapApiPgcSeason(ApiPgcSeason result) => PgcSeason(
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
  lastEpisodeId: switch (result.lastEpisodeId) {
    final id? => PgcEpisodeId(id),
    null => null,
  },
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
