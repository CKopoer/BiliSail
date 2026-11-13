import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/auth/domain/app_session_credentials.dart';
import 'package:bilisail/features/playback/data/api_cast_media_repository.dart';
import 'package:bilisail/features/playback/domain/casting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final episode in [false, true]) {
    test(
      'ordinary ${episode ? 'PGC' : 'UGC'} retains TV URL and identity',
      () async {
        final h = _Harness();
        addTearDown(h.api.close);
        final request = CastMediaRequest(
          aid: episode ? null : '170001',
          episodeId: episode ? '123' : null,
          cid: '99',
          quality: 80,
        );
        final media = await h.repository.resolve(
          request,
          cancellation: RequestCancellation(),
        );
        expect(
          media.uri.toString(),
          'https://cdn.example/video.mp4?sign=a%2Bb',
        );
        expect(media.request, same(request));
        final query = h.transport.calls.single.queryParameters;
        expect(query['object_id'], episode ? '123' : '170001');
        expect(query['playurl_type'], episode ? '2' : '1');
        expect(query['access_key'], 'fixture-token');
      },
    );

    test(
      'Bilibili ${episode ? 'PGC' : 'UGC'} uses receiver account and skips TV URL',
      () async {
        final h = _Harness();
        addTearDown(h.api.close);
        final media = await h.repository.resolve(
          CastMediaRequest(
            aid: episode ? null : '170001',
            episodeId: episode ? '123' : null,
            cid: '99',
            quality: 80,
          ),
          receiverResolves: true,
          cancellation: RequestCancellation(),
        );
        expect(media.uri, isNull);
        expect(media.aid, episode ? null : '170001');
        expect(h.transport.calls, isEmpty);
        expect(h.credentialReads, 0);
      },
    );
  }

  for (final (formats, extension) in [
    (['flv', 'fmp4', 'ts'], 'ts.m3u8'),
    (['flv', 'fmp4'], 'fmp4.m3u8'),
    (['flv'], 'flv.flv'),
  ]) {
    test('live DLNA chooses AVC and compatible format from $formats', () async {
      final h = _Harness();
      addTearDown(h.api.close);
      h.transport.formats = formats;
      for (var i = 0; i < 2; i++) {
        final media = await h.repository.resolve(
          const CastMediaRequest.live(roomId: '8', quality: 400),
          cancellation: RequestCancellation(),
        );
        expect(media.uri?.path, '/avc-$extension');
        expect(media.uri?.query, 'sign=a%2Bb&deadline=1');
        expect(media.roomId, '888');
      }
      final calls = h.transport.calls.where(
        (uri) => uri.path.contains('getRoomPlayInfo'),
      );
      expect(calls, hasLength(2)); // Refresh signed URLs for every handoff.
      expect(calls.first.queryParameters['room_id'], '8');
      expect(calls.first.queryParameters['qn'], '400');
      expect(h.credentialReads, 0);
    });
  }

  test(
    'live Bilibili receiver gets canonical room even without AVC streams',
    () async {
      final h = _Harness();
      addTearDown(h.api.close);
      h.transport.onlyHevc = true;
      final media = await h.repository.resolve(
        const CastMediaRequest.live(roomId: '8', quality: 0),
        receiverResolves: true,
        cancellation: RequestCancellation(),
      );
      expect(media.uri, isNull);
      expect(media.roomId, '888');
      expect(h.transport.calls.last.queryParameters['qn'], '0');
      await expectLater(
        h.repository.resolve(
          const CastMediaRequest.live(roomId: '8', quality: 400),
          cancellation: RequestCancellation(),
        ),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'message',
            contains('H.264'),
          ),
        ),
      );
    },
  );

  for (final receiverResolves in [false, true]) {
    test(
      'offline live room fails before handoff: enhanced=$receiverResolves',
      () async {
        final h = _Harness();
        addTearDown(h.api.close);
        h.transport.liveStatus = 0;
        await expectLater(
          h.repository.resolve(
            const CastMediaRequest.live(roomId: '8', quality: 400),
            receiverResolves: receiverResolves,
            cancellation: RequestCancellation(),
          ),
          throwsA(
            isA<AppFailure>().having((e) => e.message, 'message', '主播当前未开播'),
          ),
        );
      },
    );
  }

  for (final changedAccount in [false, true]) {
    test(
      'late live URL is discarded after ${changedAccount ? 'account change' : 'cancel'}',
      () async {
        final h = _Harness();
        addTearDown(h.api.close);
        h.transport.pending = Completer<ApiHttpResponse>();
        final token = RequestCancellation();
        final result = h.repository.resolve(
          const CastMediaRequest.live(roomId: '8', quality: 400),
          cancellation: token,
        );
        final check = expectLater(
          result,
          throwsA(
            isA<AppFailure>().having(
              (e) => e.kind,
              'kind',
              AppFailureKind.cancelled,
            ),
          ),
        );
        await h.transport.liveArrived.future;
        if (changedAccount) {
          h.requests.advanceSession();
        } else {
          token.cancel();
        }
        h.transport.pending!.complete(h.transport.liveResponse());
        await check;
      },
    );
  }
}

final class _Harness {
  final transport = _Transport();
  final requests = ApiRequests();
  int credentialReads = 0;
  late final api = BiliApiClient(
    transport: transport,
    sessionProvider: requests,
  );
  late final repository = ApiCastMediaRepository(
    api,
    requests,
    credentials: () {
      credentialReads++;
      return AppSessionCredentials(
        mid: '1',
        accessToken: 'fixture-token',
        buvid: 'fixture',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      );
    },
  );
}

final class _Transport implements ApiTransport {
  final calls = <Uri>[];
  List<String> formats = ['flv', 'fmp4', 'ts'];
  bool onlyHevc = false;
  int liveStatus = 1;
  Completer<ApiHttpResponse>? pending;
  final liveArrived = Completer<void>();

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    calls.add(uri);
    if (uri.path == '/x/web-interface/nav') {
      return _response({
        'wbi_img': {
          'img_url': 'https://i0.hdslb.com/bfs/wbi/${'a' * 32}.png',
          'sub_url': 'https://i0.hdslb.com/bfs/wbi/${'b' * 32}.png',
        },
      });
    }
    if (uri.path == '/x/tv/playurl') {
      return _response({
        'durl': [
          {'url': 'https://cdn.example/video.mp4?sign=a%2Bb'},
        ],
      });
    }
    if (uri.path.endsWith('getRoomPlayInfo')) {
      if (!liveArrived.isCompleted) liveArrived.complete();
      return pending?.future ?? liveResponse();
    }
    throw StateError('Unexpected endpoint: ${uri.path}');
  }

  ApiHttpResponse liveResponse() => _response({
    'room_id': 888,
    'live_status': liveStatus,
    'playurl_info': {
      'playurl': {
        'stream': [
          for (final format in formats)
            {
              'protocol_name': format == 'flv' ? 'http_stream' : 'http_hls',
              'format': [
                {
                  'format_name': format,
                  'codec': [
                    for (final codec in ['hevc', if (!onlyHevc) 'avc'])
                      {
                        'codec_name': codec,
                        'current_qn': 400,
                        'accept_qn': [400, 250],
                        'base_url':
                            '/$codec-$format.${format == 'flv' ? 'flv' : 'm3u8'}',
                        'url_info': [
                          {
                            'host': 'https://cdn.example',
                            'extra': '?sign=a%2Bb&deadline=1',
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
  });
}

ApiHttpResponse _response(Map<String, Object?> data) => ApiHttpResponse(
  200,
  Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
  const {},
);
