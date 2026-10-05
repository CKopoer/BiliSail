import 'dart:convert';
import 'dart:io';

import 'package:bili_api/bili_api.dart';

/// Low-frequency, guest-only PGC/live read probe. Never prints signed URLs.
Future<void> main(List<String> args) async {
  final seasonId = args.isNotEmpty ? args[0] : '28747';
  final roomId = args.length > 1 ? args[1] : '6';
  final api = BiliApiClient();
  final pgc = PgcClient(api);
  final live = LiveClient(api);
  try {
    final season = await pgc.getSeason(seasonId: seasonId);
    stdout.writeln(
      jsonEncode({
        'endpoint': 'pgc_season',
        'seasonId': season.seasonId,
        'episodes': season.episodes.length,
        'related': season.relatedSeasons.length,
      }),
    );
    if (season.episodes.isNotEmpty) {
      try {
        final play = await pgc.getPlayInfo(season.episodes.first.episodeId);
        stdout.writeln(
          jsonEncode({
            'endpoint': 'pgc_playurl',
            'videoTracks': play.dashVideo.length,
            'audioTracks': play.dashAudio.length,
          }),
        );
      } on ApiFailure catch (error) {
        _failure(error);
      }
    }
    final room = await live.getRoom(roomId);
    stdout.writeln(
      jsonEncode({
        'endpoint': 'live_room',
        'roomId': room.roomId,
        'liveStatus': room.liveStatus,
        'anchorPresent': room.anchorName.isNotEmpty,
      }),
    );
    final play = await live.getPlayInfo(room.roomId);
    stdout.writeln(
      jsonEncode({
        'endpoint': 'live_playurl',
        'liveStatus': play.liveStatus,
        'streams': play.streams.length,
        'qualities': play.qualities,
      }),
    );
    final chat = await live.getChatHistory(room.roomId);
    stdout.writeln(
      jsonEncode({'endpoint': 'live_chat_history', 'messages': chat.length}),
    );
  } on ApiFailure catch (error) {
    _failure(error);
    exitCode = 1;
  } finally {
    api.close();
  }
}

void _failure(ApiFailure error) => stdout.writeln(
  jsonEncode({
    'endpoint': error.endpointId,
    'category': error.category.name,
    'businessCode': error.businessCode,
  }),
);
