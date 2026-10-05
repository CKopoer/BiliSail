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
    expect(transport.headers.last['User-Agent'], 'BiliLite/0.1');
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

  test('storyboard removes only the leading timestamp sentinel', () async {
    final transport = _Transport({}, shot: _shot);
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
    expect(transport.uris.single.queryParameters['index'], '1');
    expect(transport.uris.single.queryParameters['cid'], '9007199254740995');
    expect(transport.headers.single['User-Agent'], 'Mozilla/5.0');
    expect(transport.headers.single['Referer'], 'https://www.bilibili.com/');
  });

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

  for (final patch in <Map<String, Object?>>[
    {'img_x_len': 0},
    {'img_y_len': 1000},
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

final class _Transport implements ApiTransport {
  _Transport(
    this.metadata, {
    this.shot = const {'image': [], 'index': []},
    this.pending,
  });
  final Map<String, Object?> metadata, shot;
  final Completer<ApiHttpResponse>? pending;
  final uris = <Uri>[];
  final headers = <Map<String, String>>[];
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    uris.add(uri);
    this.headers.add(Map.of(headers));
    if (uri.path == '/x/web-interface/nav') {
      return _response({
        'wbi_img': {
          'img_url': 'https://i0.hdslb.com/bfs/wbi/${'a' * 32}.png',
          'sub_url': 'https://i0.hdslb.com/bfs/wbi/${'b' * 32}.png',
        },
      });
    }
    if (uri.path == '/x/player/videoshot') {
      return pending?.future ?? _response(shot);
    }
    return _response(metadata);
  }
}
