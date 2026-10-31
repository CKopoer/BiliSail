import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  test('one WBI metadata read supplies chapters and subtitle tracks', () async {
    final transport = _Transport({
      'view_points': [_chapter],
      'subtitle': {
        'subtitles': [_subtitle],
      },
    });
    final client = PlaybackMetadataClient(BiliApiClient(transport: transport));
    final result = await client.load('9007199254740993', '9007199254740995');
    expect(result.chapters.single.title, 'Intro');
    expect(result.chapters.single.end, const Duration(seconds: 20));
    expect(result.subtitles.single.url.scheme, 'https');
    final read = transport.uris.last;
    expect(read.path, '/x/player/wbi/v2');
    expect(read.queryParameters['aid'], '9007199254740993');
    expect(read.queryParameters['cid'], '9007199254740995');
    expect(read.queryParameters['w_rid'], isNotEmpty);
    expect(
      transport.uris.where((u) => u.path == '/x/player/wbi/v2'),
      hasLength(1),
    );
    expect(result.chapterFailure, isNull);
    expect(result.subtitleFailure, isNull);
    expect(transport.headers.last['User-Agent'], 'BiliSail/0.1');
  });

  test('absent optional metadata is a supported empty capability', () async {
    final client = PlaybackMetadataClient(
      BiliApiClient(transport: _Transport({})),
    );
    final result = await client.load('1', '2');
    expect(result.chapters, isEmpty);
    expect(result.subtitles, isEmpty);
    expect(await client.storyboard('BV1abc123456', '2'), isNull);
  });

  test(
    'malformed chapters preserve usable subtitles and classify the failure',
    () async {
      final result = await PlaybackMetadataClient(
        BiliApiClient(
          transport: _Transport({
            'view_points': [
              {..._chapter, 'to': 0},
            ],
            'subtitle': {
              'subtitles': [_subtitle],
            },
          }),
        ),
      ).load('1', '2');
      expect(result.chapters, isEmpty);
      expect(result.chapterFailure?.category, ApiFailureCategory.protocol);
      expect(result.subtitles, hasLength(1));
    },
  );

  test(
    'malformed subtitles preserve chapters; unsafe optional covers are ignored',
    () async {
      final result = await PlaybackMetadataClient(
        BiliApiClient(
          transport: _Transport({
            'view_points': [
              {..._chapter, 'imgUrl': 'https://user:pass@i0.hdslb.com/a'},
            ],
            'subtitle': {
              'subtitles': [
                {..._subtitle, 'subtitle_url': 'file:///private'},
              ],
            },
          }),
        ),
      ).load('1', '2');
      expect(result.subtitles, isEmpty);
      expect(result.subtitleFailure?.category, ApiFailureCategory.protocol);
      expect(result.chapters.single.image, isNull);
    },
  );

  test('storyboard uses pvdata even when the JSON index is empty', () async {
    final transport = _Transport(
      {},
      shot: {..._shot, 'index': <int>[]},
      indexBytes: _index([0, 0, 5, 10]),
    );
    final shot = await PlaybackMetadataClient(
      BiliApiClient(transport: transport),
    ).storyboard('BV1abc123456', '9007199254740995');
    expect(shot?.times, [
      Duration.zero,
      const Duration(seconds: 5),
      const Duration(seconds: 10),
    ]);
    expect(shot?.columns, 2);
    expect(shot?.images.single.scheme, 'https');
    expect(transport.uris.first.queryParameters.containsKey('index'), isFalse);
    expect(transport.uris.first.queryParameters['cid'], '9007199254740995');
    expect(transport.uris.last.toString(), 'https://boss.hdslb.com/2.bin');
    expect(transport.headers.first['User-Agent'], 'Mozilla/5.0');
    expect(transport.headers.last['Referer'], 'https://www.bilibili.com/');
    expect(transport.limits, [40002]);
  });

  test('pvdata requests never forward cookies or authorization', () async {
    final jar = ApiCookieJar();
    jar.receive(Uri.https('boss.hdslb.com', '/'), [
      'private=value; Path=/; Secure',
    ]);
    final transport = _Transport({}, shot: _shot);
    await PlaybackMetadataClient(
      BiliApiClient(transport: transport, cookieJar: jar),
    ).storyboard('BV1abc123456', '2');
    expect(transport.headers.last.containsKey('Cookie'), isFalse);
    expect(transport.headers.last.containsKey('Authorization'), isFalse);
  });

  test('pvdata preserves big-endian uint16 values above one byte', () async {
    final shot = await PlaybackMetadataClient(
      BiliApiClient(
        transport: _Transport(
          {},
          shot: _shot,
          indexBytes: _index([0, 300, 65535]),
        ),
      ),
    ).storyboard('BV1abc123456', '2');
    expect(shot?.times, [
      Duration.zero,
      const Duration(seconds: 300),
      const Duration(seconds: 65535),
    ]);
  });

  for (final indexPhase in [false, true]) {
    test(
      'failed storyboard request is not automatically replayed; index=$indexPhase',
      () async {
        final transport = _Transport(
          {},
          shot: _shot,
          shotStatus: indexPhase ? 200 : 503,
          indexStatus: indexPhase ? 503 : 200,
        );
        await expectLater(
          PlaybackMetadataClient(
            BiliApiClient(transport: transport),
          ).storyboard('BV1abc123456', '2'),
          throwsA(isA<ApiFailure>().having((e) => e.httpStatus, 'status', 503)),
        );
        expect(transport.uris, hasLength(indexPhase ? 2 : 1));
      },
    );
  }

  for (final bytes in [Uint8List(1), Uint8List(40003)]) {
    test(
      'rejects truncated or excessive pvdata of ${bytes.length} bytes',
      () async {
        await expectLater(
          PlaybackMetadataClient(
            BiliApiClient(
              transport: _Transport({}, shot: _shot, indexBytes: bytes),
            ),
          ).storyboard('BV1abc123456', '2'),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.category,
              'category',
              ApiFailureCategory.protocol,
            ),
          ),
        );
      },
    );
  }

  test(
    'empty pvdata remains available for a later preview interaction',
    () async {
      expect(
        await PlaybackMetadataClient(
          BiliApiClient(
            transport: _Transport({}, shot: _shot, indexBytes: Uint8List(0)),
          ),
        ).storyboard('BV1abc123456', '2'),
        isNull,
      );
    },
  );

  test(
    'descriptor and binary read cap attempts and share one deadline',
    () async {
      var now = DateTime.utc(2026);
      final transport = _Transport(
        {},
        shot: _shot,
        onGet: (uri) {
          if (uri.path == '/x/player/videoshot') {
            now = now.add(const Duration(milliseconds: 1500));
          }
        },
      );
      await PlaybackMetadataClient(
        BiliApiClient(
          transport: transport,
          clock: () => now,
          timeout: const Duration(seconds: 3),
        ),
      ).storyboard('BV1abc123456', '2');
      expect(transport.timeouts, [
        const Duration(seconds: 2),
        const Duration(milliseconds: 1500),
      ]);
    },
  );

  test(
    'exhausted descriptor budget cannot start the pvdata download',
    () async {
      var now = DateTime.utc(2026);
      final transport = _Transport(
        {},
        shot: _shot,
        onGet: (_) {
          now = now.add(const Duration(seconds: 13));
        },
      );
      await expectLater(
        PlaybackMetadataClient(
          BiliApiClient(transport: transport, clock: () => now),
        ).storyboard('BV1abc123456', '2'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.timeout,
          ),
        ),
      );
      expect(transport.uris, hasLength(1));
    },
  );

  test(
    'frame budget applies even when the supplied sheet grid has capacity',
    () async {
      final transport = _Transport(
        {},
        shot: {
          ..._shot,
          'img_x_len': 20,
          'img_y_len': 20,
          'image': List.filled(51, 'https://i0.hdslb.com/a.jpg'),
          'index': List.generate(20001, (index) => index),
        },
      );
      await expectLater(
        PlaybackMetadataClient(
          BiliApiClient(transport: transport),
        ).storyboard('BV1abc123456', '2'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.protocol,
          ),
        ),
      );
    },
  );

  for (final dimensions in [(0, 0), (160, 0), (0, 90)]) {
    test(
      'zero tile dimensions preserve the usable storyboard index $dimensions',
      () async {
        final shot = await PlaybackMetadataClient(
          BiliApiClient(
            transport: _Transport(
              {},
              shot: {
                ..._shot,
                'img_x_size': dimensions.$1,
                'img_y_size': dimensions.$2,
              },
            ),
          ),
        ).storyboard('BV1abc123456', '2');
        expect(shot?.needsImageDimensions, isTrue);
        expect(shot?.times, hasLength(3));
        expect(shot?.images, hasLength(1));
      },
    );
  }

  for (final patch in <Map<String, Object?>>[
    {'img_x_len': 0},
    {'img_y_len': 1000},
    {'img_x_size': -1},
    {'img_y_size': -1},
    {'img_x_size': 4097},
    {'img_y_size': 4097},
    {'img_x_size': null},
    {'img_y_size': 'invalid'},
    {'pvdata': null},
    {'pvdata': 'https://private.example/index.bin'},
    {'pvdata': 'https://user:pass@boss.hdslb.com/index.bin'},
    {'pvdata': 'https://boss.hdslb.com:8443/index.bin'},
    {
      'index': [0, 0, 10, 5],
    },
    {
      'index': [0, 0, 5, 5],
    },
    {
      'index': [0, 1, 2, 3, 4],
    },
    {
      'image': ['https://private.example/a'],
    },
    {
      'image': ['https://user:pass@i0.hdslb.com/a'],
    },
    {'image': List.filled(201, 'https://i0.hdslb.com/a')},
  ]) {
    test('reject malformed or unbounded storyboard ${patch.keys}', () async {
      final client = PlaybackMetadataClient(
        BiliApiClient(transport: _Transport({}, shot: {..._shot, ...patch})),
      );
      await expectLater(
        client.storyboard('BV1abc123456', '2'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.protocol,
          ),
        ),
      );
    });
  }

  test('late storyboard read cannot cross a session epoch', () async {
    final session = _Session();
    final pending = Completer<ApiHttpResponse>();
    final transport = _Transport({}, pending: pending);
    final client = PlaybackMetadataClient(
      BiliApiClient(transport: transport, sessionProvider: session),
    );
    final read = client.storyboard(
      'BV1abc123456',
      '2',
      context: ApiRequestContext(sessionEpoch: 1),
    );
    final assertion = expectLater(
      read,
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.cancelled,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    session.sessionEpoch = 2;
    pending.complete(_response(_shot));
    await assertion;
  });

  for (final changeAccount in [false, true]) {
    test(
      'late pvdata is rejected after cancellation; account=$changeAccount',
      () async {
        final session = _Session();
        final cancellation = ApiCancellation();
        final pending = Completer<ApiHttpResponse>();
        final transport = _Transport({}, shot: _shot, indexPending: pending);
        final read =
            PlaybackMetadataClient(
              BiliApiClient(transport: transport, sessionProvider: session),
            ).storyboard(
              'BV1abc123456',
              '2',
              context: ApiRequestContext(
                sessionEpoch: 1,
                cancellation: cancellation,
              ),
            );
        final assertion = expectLater(
          read,
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.category,
              'category',
              ApiFailureCategory.cancelled,
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(transport.uris, hasLength(2));
        if (changeAccount) {
          session.sessionEpoch++;
        } else {
          cancellation.cancel();
        }
        pending.complete(ApiHttpResponse(200, _index([0, 0, 5, 10]), const {}));
        await assertion;
      },
    );
  }
}

const _chapter = {
  'type': 1,
  'from': 0,
  'to': 20,
  'content': 'Intro',
  'imgUrl': '//i0.hdslb.com/c.jpg',
};
const _subtitle = {
  'lan': 'zh-CN',
  'lan_doc': '中文',
  'subtitle_url': '//i0.hdslb.com/sub.json',
};
const _shot = {
  'img_x_len': 2,
  'img_y_len': 2,
  'img_x_size': 160,
  'img_y_size': 90,
  'image': ['http://i0.hdslb.com/grid.jpg'],
  'pvdata': '//boss.hdslb.com/2.bin',
  'index': [0, 0, 5, 10],
};

ApiHttpResponse _response(Object data) => ApiHttpResponse(
  200,
  Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
  const {},
);

final class _Session implements ApiSessionProvider {
  @override
  int sessionEpoch = 1;
}

Uint8List _index(List<int> seconds) {
  final bytes = ByteData(seconds.length * 2);
  for (var i = 0; i < seconds.length; i++) {
    bytes.setUint16(i * 2, seconds[i], Endian.big);
  }
  return bytes.buffer.asUint8List();
}

final class _Transport implements ApiTransport, ApiBoundedTransport {
  _Transport(
    this.metadata, {
    this.shot = const {'image': [], 'index': []},
    this.pending,
    this.indexPending,
    this.indexBytes,
    this.shotStatus = 200,
    this.indexStatus = 200,
    this.onGet,
  });
  final Map<String, Object?> metadata, shot;
  final Completer<ApiHttpResponse>? pending;
  final Completer<ApiHttpResponse>? indexPending;
  final Uint8List? indexBytes;
  final int shotStatus, indexStatus;
  final void Function(Uri)? onGet;
  final uris = <Uri>[];
  final headers = <Map<String, String>>[];
  final timeouts = <Duration>[];
  final limits = <int>[];
  @override
  Future<ApiHttpResponse> getBounded(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    required int maxBytes,
    ApiCancellation? cancellation,
  }) {
    limits.add(maxBytes);
    return get(
      uri,
      headers: headers,
      timeout: timeout,
      cancellation: cancellation,
    );
  }

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    uris.add(uri);
    this.headers.add(Map.of(headers));
    timeouts.add(timeout);
    onGet?.call(uri);
    if (uri.host == 'boss.hdslb.com') {
      return indexPending?.future ??
          ApiHttpResponse(
            indexStatus,
            indexBytes ?? _index((shot['index'] as List).cast<int>()),
            const {},
          );
    }
    if (uri.path == '/x/web-interface/nav') {
      return _response({
        'wbi_img': {
          'img_url': 'https://i0.hdslb.com/bfs/wbi/${'a' * 32}.png',
          'sub_url': 'https://i0.hdslb.com/bfs/wbi/${'b' * 32}.png',
        },
      });
    }
    if (uri.path == '/x/player/videoshot') {
      if (shotStatus != 200) {
        return ApiHttpResponse(shotStatus, Uint8List(0), const {});
      }
      return pending?.future ?? _response(shot);
    }
    return _response(metadata);
  }
}
