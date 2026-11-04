import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

const _bvid = 'BV1q6ad6NEVK';
const _cid = '42328985110';
const _dashTracks = {
  'duration': 60,
  'video': [
    {
      'id': 80,
      'base_url': 'https://cdn.example/video.m4s',
      'codecs': 'avc1.640028',
    },
  ],
  'audio': [
    {
      'id': 30280,
      'base_url': 'https://cdn.example/audio.m4s',
      'codecs': 'mp4a.40.2',
    },
  ],
};
const _dash = <String, Object?>{
  'accept_quality': [80],
  'dash': _dashTracks,
};

void main() {
  test('complete DASH does not retry or read entitlement', () async {
    final transport = _Transport((_) => _response(_dash));
    final api = _client(transport);

    final info = await api.getPlayInfo(_bvid, _cid);

    expect(info.dashVideo, hasLength(1));
    expect(info.dashAudio, hasLength(1));
    expect(transport.plays, hasLength(1));
    expect(transport.details, 0);
  });

  final missingStreams = <Map<String, Object?>>[
    {},
    {'dash': null},
    {'dash': <String, Object?>{}},
    {
      'dash': {..._dashTracks, 'video': <Object?>[]},
    },
    {
      'dash': {..._dashTracks, 'audio': <Object?>[]},
    },
    {
      'dash': {'video': _dashTracks['video']},
    },
  ];
  for (var i = 0; i < missingStreams.length; i++) {
    test('missing DASH streams recover on retry case $i', () async {
      final transport = _Transport(
        (index) => _response(index == 0 ? missingStreams[i] : _dash),
      );
      final api = _client(transport);

      final info = await api.getPlayInfo(_bvid, _cid, qn: 80);

      expect(info.dashVideo, hasLength(1));
      expect(info.dashAudio, hasLength(1));
      expect(transport.plays, hasLength(2));
      expect(transport.details, 1);
      expect(transport.plays.map((uri) => uri.queryParameters['qn']), [
        '80',
        '80',
      ]);
      expect(transport.timeouts, everyElement(const Duration(seconds: 2)));
    });
  }

  test('unknown business errors recover within three playurl reads', () async {
    final transport = _Transport(
      (index) =>
          index < 2 ? _response({}, code: -7000 - index) : _response(_dash),
    );
    final api = _client(transport);

    final info = await api.getPlayInfo(_bvid, _cid);

    expect(info.dashAudio, hasLength(1));
    expect(transport.plays, hasLength(3));
    expect(transport.details, 1);
  });

  test('exhaustion preserves the final business failure', () async {
    final transport = _Transport((index) => _response({}, code: -7000 - index));
    final api = _client(transport);

    await expectLater(
      api.getPlayInfo(_bvid, _cid),
      throwsA(
        _failure(
          ApiFailureCategory.unavailable,
        ).having((e) => e.businessCode, 'business code', -7002),
      ),
    );
    expect(transport.plays, hasLength(3));
    expect(transport.details, 1);
  });

  test('persistently missing streams stop after three reads', () async {
    final transport = _Transport((_) => _response({}));
    final api = _client(transport);

    await expectLater(
      api.getPlayInfo(_bvid, _cid),
      throwsA(_failure(ApiFailureCategory.unavailable)),
    );
    expect(transport.plays, hasLength(3));
    expect(transport.details, 1);
  });

  for (final firstFailure in [
    ApiFailureCategory.network,
    ApiFailureCategory.timeout,
  ]) {
    test('$firstFailure and content errors share the attempt budget', () async {
      final transport = _Transport((index) {
        if (index == 0) throw ApiFailure(firstFailure, 'transport');
        if (index == 1) return _response({});
        return ApiHttpResponse(503, Uint8List(0), const {});
      });
      final api = _client(transport);

      await expectLater(
        api.getPlayInfo(_bvid, _cid),
        throwsA(
          _failure(
            ApiFailureCategory.http,
          ).having((e) => e.httpStatus, 'status', 503),
        ),
      );
      expect(transport.plays, hasLength(3));
    });
  }

  test('HTTP retries cannot reset the content attempt budget', () async {
    final transport = _Transport((index) {
      if (index == 0) return _response({});
      if (index == 1) return ApiHttpResponse(502, Uint8List(0), const {});
      return _response({}, code: -7002);
    });
    final api = _client(transport);

    await expectLater(
      api.getPlayInfo(_bvid, _cid),
      throwsA(_failure(ApiFailureCategory.unavailable)),
    );
    expect(transport.plays, hasLength(3));
  });

  test('WBI refresh shares the same three playurl attempts', () async {
    final transport = _Transport((index) {
      if (index == 0) return _response({});
      if (index == 1) return _response({}, code: -403);
      return _response(_dash);
    });
    final api = _client(transport);

    final info = await api.getPlayInfo(_bvid, _cid);

    expect(info.dashVideo, hasLength(1));
    expect(transport.plays, hasLength(3));
    expect(transport.navs, 2);
  });

  test('WBI cannot issue a fourth playurl request after exhaustion', () async {
    final transport = _Transport(
      (index) => _response({}, code: index < 2 ? -7000 : -403),
    );
    final api = _client(transport);

    await expectLater(
      api.getPlayInfo(_bvid, _cid),
      throwsA(_failure(ApiFailureCategory.permission)),
    );
    expect(transport.plays, hasLength(3));
    expect(transport.navs, 1);
  });

  for (final code in [-101, -111, -400, -404, -412, -352, 62002, 62004]) {
    test('classified business error $code does not retry', () async {
      final transport = _Transport((_) => _response({}, code: code));
      final api = _client(transport);

      await expectLater(
        api.getPlayInfo(_bvid, _cid),
        throwsA(isA<ApiFailure>()),
      );

      expect(transport.plays, hasLength(1));
    });
  }

  for (final status in [401, 403, 404, 429]) {
    test('HTTP $status does not retry', () async {
      final transport = _Transport(
        (_) => ApiHttpResponse(status, Uint8List(0), const {}),
      );
      final api = _client(transport);

      await expectLater(
        api.getPlayInfo(_bvid, _cid),
        throwsA(isA<ApiFailure>()),
      );

      expect(transport.plays, hasLength(1));
    });
  }

  for (final access in <Map<String, Object?>>[
    {'is_upower_exclusive': true, 'is_upower_play': false},
    {
      'rights': {'ugc_pay': 1},
    },
  ]) {
    test('blocked entitlement does not retry: $access', () async {
      final transport = _Transport((_) => _response({}), access: access);
      final api = _client(transport);

      await expectLater(
        api.getPlayInfo(_bvid, _cid),
        throwsA(_failure(ApiFailureCategory.permission)),
      );
      expect(transport.plays, hasLength(1));
      expect(transport.details, 1);
    });
  }

  for (final trial in <Map<String, Object?>>[
    {..._dash, 'is_preview': 1},
    {'is_preview': true},
    {
      'is_preview': 1,
      'dash': {'video': [], 'audio': []},
    },
  ]) {
    test(
      'trial playback does not retry even without streams: $trial',
      () async {
        final transport = _Transport((_) => _response(trial));
        final api = _client(transport);

        await expectLater(
          api.getPlayInfo(_bvid, _cid),
          throwsA(_failure(ApiFailureCategory.permission)),
        );
        expect(transport.plays, hasLength(1));
      },
    );
  }

  test('entitlement diagnosis failure does not replay playurl', () async {
    final transport = _Transport((_) => _response({}));
    transport.detailCode = -7000;
    final api = _client(transport);

    await expectLater(
      api.getPlayInfo(_bvid, _cid),
      throwsA(
        _failure(
          ApiFailureCategory.unavailable,
        ).having((e) => e.endpointId, 'endpoint', 'video_detail'),
      ),
    );
    expect(transport.plays, hasLength(1));
    expect(transport.details, 1);
  });

  test('malformed tracks remain a protocol error without retry', () async {
    final transport = _Transport(
      (_) => _response({
        ..._dash,
        'dash': {
          ..._dashTracks,
          'video': [
            {'id': 80},
          ],
        },
      }),
    );
    final api = _client(transport);

    await expectLater(
      api.getPlayInfo(_bvid, _cid),
      throwsA(_failure(ApiFailureCategory.protocol)),
    );
    expect(transport.plays, hasLength(1));
    expect(transport.details, 0);
  });

  test(
    'hover retries missing video and still accepts video without audio',
    () async {
      final transport = _Transport(
        (index) => _response(
          index == 0
              ? {}
              : {
                  ..._dash,
                  'dash': {..._dashTracks, 'audio': <Object?>[]},
                },
        ),
      );
      final api = _client(transport);

      final info = await api.getVideoPreviewInfo(_bvid, _cid);

      expect(info.dashVideo, hasLength(1));
      expect(info.dashAudio, isEmpty);
      expect(transport.plays, hasLength(2));
    },
  );

  for (final cancel in [true, false]) {
    test(
      '${cancel ? 'cancellation' : 'account change'} during backoff stops retry',
      () async {
        final cancellation = ApiCancellation();
        final session = _Session();
        final transport = _Transport((_) => _response({}));
        final api = _client(transport, session: session);
        final result = expectLater(
          api.getPlayInfo(
            _bvid,
            _cid,
            context: ApiRequestContext(cancellation: cancellation),
          ),
          throwsA(_failure(ApiFailureCategory.cancelled)),
        );

        await transport.detailRead.future;
        await Future<void>.delayed(Duration.zero);
        if (cancel) {
          cancellation.cancel();
        } else {
          session.sessionEpoch++;
        }
        await result;
        expect(transport.plays, hasLength(1));
      },
    );
  }

  for (final explicitDeadline in [true, false]) {
    test(
      '${explicitDeadline ? 'caller' : 'default'} deadline spans content retries',
      () async {
        final start = DateTime.utc(2026, 11, 5);
        var now = start;
        final transport = _Transport((_) => _response({}));
        transport.onDetail = () => now = start.add(const Duration(seconds: 25));
        final api = _client(transport, clock: () => now);

        await expectLater(
          api.getPlayInfo(
            _bvid,
            _cid,
            context: explicitDeadline
                ? ApiRequestContext(
                    deadline: start.add(const Duration(seconds: 25)),
                  )
                : null,
          ),
          throwsA(_failure(ApiFailureCategory.timeout)),
        );
        expect(transport.plays, hasLength(1));
        expect(transport.details, 1);
      },
    );
  }
}

BiliApiClient _client(
  _Transport transport, {
  ApiSessionProvider? session,
  DateTime Function()? clock,
}) {
  final api = BiliApiClient(
    transport: transport,
    sessionProvider: session,
    clock: clock,
  );
  addTearDown(api.close);
  return api;
}

TypeMatcher<ApiFailure> _failure(ApiFailureCategory category) =>
    isA<ApiFailure>().having((e) => e.category, 'category', category);

ApiHttpResponse _response(Map<String, Object?> data, {int code = 0}) =>
    ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': code, 'data': data}))),
      const {},
    );

final class _Session implements ApiSessionProvider {
  @override
  int sessionEpoch = 0;
}

final class _Transport implements ApiTransport {
  _Transport(this.play, {this.access = const {}});
  final ApiHttpResponse Function(int) play;
  final Map<String, Object?> access;
  final plays = <Uri>[];
  final timeouts = <Duration>[];
  final detailRead = Completer<void>();
  void Function()? onDetail;
  int detailCode = 0;
  int details = 0, navs = 0;

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    switch (uri.path) {
      case '/x/web-interface/nav':
        navs++;
        return _response({
          'wbi_img': {
            'img_url': 'https://i0.hdslb.com/bfs/wbi/${'a' * 32}.png',
            'sub_url': 'https://i0.hdslb.com/bfs/wbi/${'b' * 32}.png',
          },
        });
      case '/x/web-interface/view':
        details++;
        onDetail?.call();
        if (!detailRead.isCompleted) detailRead.complete();
        return _response({
          'aid': '117358337201563',
          'bvid': _bvid,
          'title': '测试视频',
          'pages': [
            {'cid': _cid, 'page': 1, 'part': 'P1'},
          ],
          ...access,
        }, code: detailCode);
      case '/x/player/wbi/playurl':
        plays.add(uri);
        timeouts.add(timeout);
        return play(plays.length - 1);
      default:
        throw StateError('Unexpected endpoint ${uri.path}');
    }
  }
}
