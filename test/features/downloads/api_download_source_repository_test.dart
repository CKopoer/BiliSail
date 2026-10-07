import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/domain/video_codec.dart';
import 'package:bilisail/features/downloads/data/api_download_source_repository.dart';
import 'package:bilisail/features/downloads/domain/download_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ApiRequests requests;
  late _Transport transport;
  late BiliApiClient api;
  late ApiDownloadSourceRepository repository;
  var scope = 'account-a';

  setUp(() {
    scope = 'account-a';
    requests = ApiRequests();
    transport = _Transport();
    api = BiliApiClient(transport: transport, sessionProvider: requests);
    repository = ApiDownloadSourceRepository(
      api,
      requests,
      accountScope: () => scope,
    );
  });
  tearDown(() async => api.close());

  test(
    'queries deliverable qualities and resolves exact codec with highest AAC',
    () async {
      final qualities = await repository.qualities(
        _item(),
        cancellation: RequestCancellation(),
      );
      expect(qualities, [80]);
      expect(transport.playRequestCount, 1);
      final selection = const DownloadSelection(
        quality: 80,
        codec: VideoCodecPreference.hevc,
      );
      final first = await repository.resolve(
        _item(),
        selection,
        cancellation: RequestCancellation(),
      );
      expect(first.video.codec, 'hev1.1.6.L120');
      expect(first.video.urls, hasLength(2));
      expect(first.audio.bandwidth, 192000);
      expect(first.headers.keys, containsAll(['Referer', 'User-Agent']));
      transport.signature = 'new-signature';
      transport.cdnHost = 'backup.hdslb.com';
      final renewed = await repository.resolve(
        _item(),
        selection,
        cancellation: RequestCancellation(),
      );
      expect(renewed.video.identity, first.video.identity);
      expect(renewed.video.urls.first, isNot(first.video.urls.first));
      expect(first.video.identity, isNot(contains('signature')));
      expect(first.video.identity, isNot(contains('?')));
      await expectLater(
        repository.resolve(
          _item(),
          const DownloadSelection(quality: 80, codec: VideoCodecPreference.av1),
          cancellation: RequestCancellation(),
        ),
        throwsA(
          isA<AppFailure>().having(
            (f) => f.kind,
            'kind',
            AppFailureKind.playback,
          ),
        ),
      );
    },
  );

  test('advertised 1080p is hidden when DASH only contains 480p', () async {
    transport.forcedQuality = 32;
    final qualities = await repository.qualities(
      _item(),
      cancellation: RequestCancellation(),
    );
    expect(qualities, [32]);
    expect(transport.playRequestCount, 1);
  });

  test('PGC preview is rejected as a complete episode', () async {
    transport.preview = true;
    await expectLater(
      repository.resolve(
        _item(episodeId: '42', bvid: ''),
        const DownloadSelection(),
        cancellation: RequestCancellation(),
      ),
      throwsA(
        isA<AppFailure>().having(
          (f) => f.kind,
          'kind',
          AppFailureKind.permission,
        ),
      ),
    );
  });

  test('cancelled session cannot publish a resolved source', () async {
    transport.blockPlay = Completer<void>();
    final cancellation = RequestCancellation();
    final pending = repository.resolve(
      _item(),
      const DownloadSelection(),
      cancellation: cancellation,
    );
    await transport.playStarted.future;
    cancellation.cancel();
    transport.blockPlay!.complete();
    await expectLater(
      pending,
      throwsA(
        isA<AppFailure>().having(
          (f) => f.kind,
          'kind',
          AppFailureKind.cancelled,
        ),
      ),
    );
  });

  test(
    'optional extras enforce track and cue limits and report failures',
    () async {
      transport.subtitleTracks = 17;
      final extras = await repository.extras(
        _item(coverUrl: 'https://example.com/cover.jpg'),
        const DownloadSelection(),
        cancellation: RequestCancellation(),
      );
      expect(extras.cover, isNull);
      expect(extras.subtitles, hasLength(15));
      expect(extras.comments, isEmpty);
      expect(extras.warnings.any((w) => w.contains('封面保存失败')), isTrue);
      expect(extras.warnings.any((w) => w.contains('16 条')), isTrue);
      expect(extras.warnings.any((w) => w.contains('字幕内容超过')), isTrue);
      expect(extras.warnings.any((w) => w.contains('弹幕获取失败')), isTrue);
      expect(extras.subtitles.first.cues.single.text, '字幕');
    },
  );

  test(
    'restored task refetches cover metadata without saving its URL',
    () async {
      final extras = await repository.extras(
        _item(),
        const DownloadSelection(includeDanmaku: false, includeSubtitles: false),
        cancellation: RequestCancellation(),
      );
      expect(transport.videoDetailRequestCount, 1);
      expect(
        extras.warnings.any((message) => message.contains('封面保存失败')),
        isTrue,
      );
    },
  );
}

DownloadItem _item({
  String? episodeId,
  String coverUrl = '',
  String bvid = 'BV1xx411c7mD',
}) => DownloadItem(
  video: VideoSummary(
    id: VideoId(bvid),
    title: '片名',
    coverUrl: coverUrl,
    author: '作者',
    duration: const Duration(minutes: 3),
  ),
  part: const VideoPart(
    cid: '123',
    page: 1,
    title: '第一集',
    duration: Duration(minutes: 3),
  ),
  aid: '11',
  episodeId: episodeId,
);

final class _Transport implements ApiTransport {
  String signature = 'old-signature';
  String cdnHost = 'i0.hdslb.com';
  bool preview = false;
  int? forcedQuality;
  int playRequestCount = 0;
  int videoDetailRequestCount = 0;
  int subtitleTracks = 0;
  Completer<void>? blockPlay;
  final playStarted = Completer<void>();

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    if (uri.path == '/x/v2/dm/web/seg.so') {
      return ApiHttpResponse(200, Uint8List.fromList([255]), const {});
    }
    if (uri.path.contains('/playurl')) {
      playRequestCount++;
      if (!playStarted.isCompleted) playStarted.complete();
      await blockPlay?.future;
      final quality =
          forcedQuality ?? (uri.queryParameters['qn'] == '64' ? 64 : 80);
      final trackUrl = 'https://$cdnHost/media/stream.m4s?token=$signature';
      return _json({
        'code': 0,
        uri.path.startsWith('/pgc/') ? 'result' : 'data': {
          'code': 0,
          'is_preview': preview ? 1 : 0,
          'accept_quality': [80, 64],
          'dash': {
            'duration': 180,
            'video': [
              {
                'id': quality,
                'base_url': trackUrl,
                'backup_url': [
                  'https://backup.hdslb.com/media/stream.m4s?token=$signature',
                ],
                'codecs': 'avc1.640028',
                'bandwidth': 800000,
              },
              if (quality == 80)
                {
                  'id': 80,
                  'base_url': trackUrl,
                  'backup_url': [
                    'https://backup.hdslb.com/media/stream.m4s?token=$signature',
                  ],
                  'codecs': 'hev1.1.6.L120',
                  'bandwidth': 1000000,
                },
            ],
            'audio': [
              {
                'id': 30280,
                'base_url': trackUrl,
                'codecs': 'mp4a.40.2',
                'bandwidth': 128000,
              },
              {
                'id': 30280,
                'base_url': trackUrl,
                'codecs': 'mp4a.40.2',
                'bandwidth': 192000,
              },
            ],
          },
        },
      });
    }
    if (uri.path == '/x/web-interface/nav') {
      return _json({
        'code': -101,
        'data': {
          'wbi_img': {
            'img_url': 'https://i0.hdslb.com/bfs/wbi/${'a' * 32}.png',
            'sub_url': 'https://i0.hdslb.com/bfs/wbi/${'b' * 32}.png',
          },
        },
      });
    }
    if (uri.path == '/x/web-interface/view') {
      videoDetailRequestCount++;
      return _json({
        'code': 0,
        'data': {
          'aid': 11,
          'bvid': 'BV1xx411c7mD',
          'title': '片名',
          'pic': 'https://example.com/cover.jpg',
          'pages': [
            {'cid': 123, 'page': 1, 'part': '第一集', 'duration': 180},
          ],
        },
      });
    }
    if (uri.path == '/x/player/wbi/v2') {
      return _json({
        'code': 0,
        'data': {
          'subtitle': {
            'subtitles': [
              for (var i = 0; i < subtitleTracks; i++)
                {
                  'lan': 'zh-CN',
                  'lan_doc': '轨道 $i',
                  'subtitle_url': 'https://i0.hdslb.com/bfs/subtitle/$i.json',
                },
            ],
          },
        },
      });
    }
    if (uri.path.startsWith('/bfs/subtitle/')) {
      final number = int.parse(uri.pathSegments.last.split('.').first);
      return _json({
        'body': [
          {'from': 0, 'to': 2, 'content': number == 1 ? '超长' * 2500 : '字幕'},
        ],
      });
    }
    throw StateError('Unexpected request: $uri');
  }

  ApiHttpResponse _json(Map<String, Object?> body) => ApiHttpResponse(
    200,
    Uint8List.fromList(utf8.encode(jsonEncode(body))),
    const {},
  );
}
