import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

final class _Transport implements ApiTransport {
  _Transport(this.reply);
  final Object? Function(Uri) reply;
  final requests = <Uri>[];

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    requests.add(uri);
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode(reply(uri)))),
      const {},
    );
  }
}

void main() {
  test(
    'PGC season keeps episode IDs, milliseconds and section title',
    () async {
      final transport = _Transport(
        (_) => {
          'code': 0,
          'result': {
            'season_id': 28747,
            'title': '测试季',
            'evaluate': '简介',
            'type': 4,
            'rating': {'score': 9.7},
            'stat': {'views': 100, 'danmakus': 20, 'favorites': 30},
            'publish': {'pub_time_show': '周日'},
            'episodes': [
              {
                'ep_id': 733316,
                'aid': 478818261,
                'bvid': 'BV1vT411d7QE',
                'cid': 1022370693,
                'title': '1',
                'long_title': '首集',
                'duration': 1203160,
                'status': 2,
                'rights': {'area_limit': 0},
              },
            ],
            'section': [
              {
                'title': '花絮',
                'episodes': [
                  {
                    'ep_id': 0,
                    'id': 42,
                    'title': '会员集',
                    'duration': 30000,
                    'status': 13,
                    'badge': '大会员',
                  },
                  {'id': 43, 'title': '待更新', 'status': 0},
                ],
              },
            ],
            'seasons': [
              {'season_id': 28747, 'season_title': '正片'},
            ],
          },
        },
      );
      final result = await PgcClient(
        BiliApiClient(transport: transport),
      ).getSeason(seasonId: '28747');
      expect(transport.requests.single.path, '/pgc/view/web/season');
      expect(transport.requests.single.queryParameters['season_id'], '28747');
      expect(result.type, 4);
      expect(result.rating, 9.7);
      expect(
        result.episodes.first.duration,
        const Duration(milliseconds: 1203160),
      );
      expect(result.episodes.first.cid, '1022370693');
      expect(result.episodes.last.sectionTitle, '花絮');
      expect(result.episodes[1].episodeId, '42');
      expect(result.episodes[1].playable, true);
      expect(result.episodes[1].permissionText, '大会员');
      expect(result.episodes.last.playable, false);
      expect(result.relatedSeasons.single.seasonId, '28747');
    },
  );

  test('PGC long-running season preserves episodes beyond 1000', () async {
    final client = PgcClient(
      BiliApiClient(
        transport: _Transport(
          (_) => {
            'code': 0,
            'result': {
              'season_id': 42,
              'title': '长篇剧集',
              'episodes': List.generate(
                1275,
                (index) => {'id': index + 1, 'title': '${index + 1}'},
              ),
            },
          },
        ),
      ),
    );
    final result = await client.getSeason(seasonId: '42');
    expect(result.episodes, hasLength(1275));
    expect(result.episodes[1000].episodeId, '1001');
    expect(result.episodes.last.episodeId, '1275');
  });

  test('PGC combined main and section episodes stop at 5000', () async {
    final client = PgcClient(
      BiliApiClient(
        transport: _Transport(
          (_) => {
            'code': 0,
            'result': {
              'season_id': 42,
              'title': '长篇剧集',
              'episodes': List.generate(
                3900,
                (index) => {'id': index + 1, 'title': '${index + 1}'},
              ),
              'section': [
                {
                  'title': '花絮',
                  'episodes': List.generate(
                    1500,
                    (index) => {'id': 10000 + index, 'title': '$index'},
                  ),
                },
                {
                  'title': '后续',
                  'episodes': [
                    {'id': 20000, 'title': '不应进入'},
                  ],
                },
              ],
            },
          },
        ),
      ),
    );
    final result = await client.getSeason(seasonId: '42');
    expect(result.episodes, hasLength(5000));
    expect(result.episodes[3899].episodeId, '3900');
    expect(result.episodes[3900].episodeId, '10000');
    expect(result.episodes.last.episodeId, '11099');
    expect(result.episodes.last.sectionTitle, '花絮');
  });

  test('PGC playurl needs both DASH tracks and classifies rights', () async {
    final transport = _Transport(
      (_) => {
        'code': 0,
        'result': {
          'code': 0,
          'dash': {
            'duration': 120.5,
            'video': [
              {
                'id': 32,
                'base_url': 'https://cdn.example/video.m4s?token=redacted',
                'codecs': 'avc1.64001F',
              },
            ],
            'audio': [
              {
                'id': 30280,
                'base_url': 'https://cdn.example/audio.m4s?token=redacted',
                'codecs': 'mp4a.40.2',
              },
            ],
          },
          'accept_quality': [32, 64],
        },
      },
    );
    final client = PgcClient(BiliApiClient(transport: transport));
    final play = await client.getPlayInfo('733316');
    expect(transport.requests.single.path, '/pgc/player/web/playurl');
    expect(play.duration, const Duration(milliseconds: 120500));
    expect(play.dashVideo.single.id, 32);
    expect(play.dashAudio.single.id, 30280);

    final denied = PgcClient(
      BiliApiClient(
        transport: _Transport(
          (_) => {
            'code': 0,
            'result': {'code': -10403, 'message': 'restricted'},
          },
        ),
      ),
    );
    await expectLater(
      denied.getPlayInfo('733316'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.permission,
        ),
      ),
    );
    final outerDenied = PgcClient(
      BiliApiClient(
        transport: _Transport((_) => {'code': -10403, 'message': 'restricted'}),
      ),
    );
    await expectLater(
      outerDenied.getPlayInfo('733316'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.permission,
        ),
      ),
    );
  });

  test('live room resolves short ID and anchor through Web reads', () async {
    final transport = _Transport(
      (uri) =>
          uri.path == '/room/v1/Room/get_info'
              ? {
                'code': 0,
                'data': {
                  'room_id': 7734200,
                  'uid': 50329118,
                  'title': '赛事',
                  'live_status': 1,
                  'online': 125,
                  'area_name': '游戏赛事',
                },
              }
              : {
                'code': 0,
                'data': {
                  'info': {'uname': '主播', 'face': '//i0.hdslb.com/face.jpg'},
                },
              },
    );
    final room = await LiveClient(
      BiliApiClient(transport: transport),
    ).getRoom('6');
    expect(room.roomId, '7734200');
    expect(room.anchorMid, '50329118');
    expect(room.anchorName, '主播');
    expect(room.anchorAvatarUrl?.scheme, 'https');
    expect(transport.requests.last.queryParameters['uid'], '50329118');
  });

  test('live playurl retains format, codec and signed backup hosts', () async {
    final transport = _Transport(
      (_) => {
        'code': 0,
        'data': {
          'room_id': 7734200,
          'live_status': 1,
          'playurl_info': {
            'playurl': {
              'g_qn_desc': [
                {'qn': 250, 'desc': '超清'},
                {'qn': 400, 'desc': '蓝光'},
              ],
              'stream': [
                {
                  'protocol_name': 'http_stream',
                  'format': [
                    {
                      'format_name': 'flv',
                      'codec': [
                        {
                          'codec_name': 'avc',
                          'current_qn': 250,
                          'accept_qn': [400, 250],
                          'base_url': '/live.flv?',
                          'url_info': [
                            {
                              'host': 'https://cdn.example',
                              'extra': 'sign=one',
                            },
                            {
                              'host': 'https://backup.example',
                              'extra': 'sign=two',
                            },
                          ],
                        },
                      ],
                    },
                  ],
                },
              ],
            },
          },
        },
      },
    );
    final play = await LiveClient(
      BiliApiClient(transport: transport),
    ).getPlayInfo('6');
    expect(play.roomId, '7734200');
    expect(play.streams.single.format, 'flv');
    expect(play.streams.single.codec, 'avc');
    expect(play.streams.single.qualityLabel, '超清');
    expect(play.streams.single.urls.length, 2);
    expect(play.qualities, [400, 250]);
    expect(play.qualityLabels[400], '蓝光');
    expect(play.streams.single.urls.last.queryParameters['sign'], 'two');
  });

  test(
    'live chat remains bounded and malformed input fails explicitly',
    () async {
      final client = LiveClient(
        BiliApiClient(
          transport: _Transport(
            (_) => {
              'code': 0,
              'data': {
                'room': [
                  {
                    'nickname': '观众',
                    'text': '你好',
                    'timeline': '2026-10-05 10:20:30',
                    'id': '9007199254740993',
                    'user': {'uid': '9007199254740995'},
                    'emots': {
                      '你好': {
                        'url': '//i0.hdslb.com/hi.png',
                        'width': 24,
                        'height': 24,
                      },
                    },
                    'emoticon': {
                      'url': '//i0.hdslb.com/sticker.png',
                      'width': 160,
                      'height': 80,
                    },
                  },
                ],
              },
            },
          ),
        ),
      );
      final chat = await client.getChatHistory('6');
      expect(chat.single.id, '9007199254740993');
      expect(chat.single.userId, '9007199254740995');
      expect(chat.single.emotes['你好']?.url.scheme, 'https');
      expect(chat.single.sticker?.width, 160);
      expect(chat.single.timestamp?.year, 2026);
      expect(() => client.getChatHistory('6&foo=bar'), throwsArgumentError);
    },
  );

  test(
    'offline live room returns no stream without claiming playback',
    () async {
      final client = LiveClient(
        BiliApiClient(
          transport: _Transport(
            (_) => {
              'code': 0,
              'data': {'room_id': 123, 'live_status': 0},
            },
          ),
        ),
      );
      final result = await client.getPlayInfo('123');
      expect(result.liveStatus, 0);
      expect(result.streams, isEmpty);
    },
  );
}
