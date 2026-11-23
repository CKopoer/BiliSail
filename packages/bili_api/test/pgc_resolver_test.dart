import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

final class _Request {
  const _Request(this.uri, this.headers, this.timeout, this.cancellation);
  final Uri uri;
  final Map<String, String> headers;
  final Duration timeout;
  final ApiCancellation? cancellation;
}

typedef _Reply = FutureOr<ApiHttpResponse> Function(_Request request);

final class _Transport implements ApiTransport {
  _Transport(this.reply);
  final _Reply reply;
  final requests = <_Request>[];

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) {
    final request = _Request(uri, headers, timeout, cancellation);
    requests.add(request);
    return Future<ApiHttpResponse>.sync(() => reply(request));
  }
}

final class _BoundedTransport implements ApiTransport, ApiBoundedTransport {
  _BoundedTransport(this.reply);
  final _Reply reply;
  final requests = <_Request>[];
  final limits = <int>[];

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) => throw StateError('Resolver must use the bounded read');

  @override
  Future<ApiHttpResponse> getBounded(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    required int maxBytes,
    ApiCancellation? cancellation,
  }) {
    final request = _Request(uri, headers, timeout, cancellation);
    requests.add(request);
    limits.add(maxBytes);
    return Future<ApiHttpResponse>.sync(() => reply(request));
  }
}

Uint8List _bytes(Object? value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

ApiHttpResponse _json(Object? value, {int status = 200}) =>
    ApiHttpResponse(status, _bytes(value), const {});

ApiHttpResponse _refusal([int code = -404]) =>
    _json({'code': code, 'message': 'refused'});

Map<String, Object?> _seasonResult({
  String title = 'Resolved season',
  List<Object?>? episodes,
}) => {
  'season_id': 42,
  'title': title,
  'cover': 'https://i0.hdslb.com/season.jpg',
  'evaluate': 'resolver detail',
  'episodes':
      episodes ??
      [
        {
          'id': 9,
          'aid': 99,
          'cid': 999,
          'bvid': 'BV1ab411c7mD',
          'title': '1',
          'long_title': 'Resolved episode',
          'status': 2,
          'duration': 123456,
        },
      ],
  'section': const [],
  'seasons': const [],
};

Map<String, Object?> _playResult() => {
  'quality': 80,
  'format': 'flv',
  'timelength': 123456,
  'accept_quality': [80, '64'],
  'is_preview': 0,
  'clip_info_list': [
    {'clipType': 'CLIP_TYPE_OP', 'start': 1, 'end': 2},
  ],
  'dash': {
    'duration': 123.456,
    'video': [
      {
        'id': 80,
        'base_url': 'https://upos-sz-mirror.bilivideo.com/video.m4s',
        'backup_url': [
          'https://upos-hz-mirror.bilivideo.com/video.m4s',
          'invalid',
        ],
        'bandwidth': 2_000_000,
        'mime_type': 'video/mp4',
        'codecs': 'avc1.640028',
      },
    ],
    'audio': [
      {
        'id': 30232,
        'baseUrl': 'https://upos-sz-mirror.bilivideo.com/audio.m4s',
        'backupUrl': ['https://upos-hz-mirror.bilivideo.com/audio.m4s'],
        'bandwidth': 128000,
        'mimeType': 'audio/mp4',
        'codecs': 'mp4a.40.2',
      },
    ],
    'flac': {
      'audio': {
        'id': 30251,
        'base_url': 'https://upos-sz-mirror.bilivideo.com/flac.m4s',
        'bandwidth': 900000,
        'mime_type': 'audio/mp4',
        'codecs': 'fLaC',
      },
    },
    'dolby': {
      'audio': [
        {
          'id': 30216,
          'base_url': 'https://upos-sz-mirror.bilivideo.com/dolby.m4s',
          'bandwidth': 256000,
          'mime_type': 'audio/mp4',
          'codecs': 'ec-3',
        },
      ],
    },
  },
};

ApiHttpResponse _seasonReply({String title = 'Resolved season'}) =>
    _json({'code': 0, 'result': _seasonResult(title: title)});

ApiHttpResponse _playReply({bool wrapped = false}) => _json({
  'code': 0,
  'data': wrapped ? {'video_info': _playResult()} : _playResult(),
});

Matcher _failure(
  ApiFailureCategory category, {
  String? endpoint,
  int? businessCode,
}) {
  var matcher = isA<ApiFailure>().having(
    (error) => error.category,
    'category',
    category,
  );
  if (endpoint != null) {
    matcher = matcher.having((error) => error.endpointId, 'endpoint', endpoint);
  }
  if (businessCode != null) {
    matcher = matcher.having(
      (error) => error.businessCode,
      'businessCode',
      businessCode,
    );
  }
  return matcher;
}

PgcResolver _resolver(
  ApiTransport transport, {
  Map<PgcResolverRegion, Uri>? servers,
  PgcResolverRegion? defaultRegion,
  Duration timeout = const Duration(seconds: 1),
}) => PgcResolver(
  servers:
      servers ??
      {PgcResolverRegion.hk: Uri.parse('https://resolver.test/base')},
  defaultRegion: defaultRegion,
  transport: transport,
  timeout: timeout,
);

void main() {
  group('PgcResolver configuration', () {
    test('parses supported region aliases', () {
      expect(PgcResolverRegion.tryParse(' hk '), PgcResolverRegion.hk);
      expect(PgcResolverRegion.tryParse('MO'), PgcResolverRegion.hk);
      expect(PgcResolverRegion.tryParse('th'), PgcResolverRegion.sea);
      expect(PgcResolverRegion.tryParse('intl'), PgcResolverRegion.sea);
      expect(PgcResolverRegion.tryParse('TW'), PgcResolverRegion.tw);
      expect(PgcResolverRegion.tryParse('cn'), PgcResolverRegion.cn);
      expect(PgcResolverRegion.tryParse('other'), isNull);
    });

    test('rejects credential-bearing or non-HTTP base URLs', () {
      for (final value in [
        'file:///tmp/resolver',
        'https://user:secret@resolver.test/',
        'https://resolver.test/?access_key=secret',
        'https://resolver.test/#fragment',
      ]) {
        expect(
          () => PgcResolver(
            servers: {PgcResolverRegion.hk: Uri.parse(value)},
            transport: _Transport((_) => _refusal()),
          ),
          throwsArgumentError,
        );
      }
    });
  });

  group('PgcResolver requests', () {
    test('detail prefers SEA and tries app web intl anonymously', () async {
      final transport = _Transport((request) {
        if (request.uri.path == '/proxy/intl/gateway/v2/ogv/view/app/season') {
          final result = _seasonResult(title: 'Modules', episodes: []);
          result['modules'] = {
            'section': [
              {
                'title': 'Extra',
                'episodes': (_seasonResult()['episodes']! as List<Object?>),
              },
            ],
          };
          return _json({'code': 0, 'result': result});
        }
        return _refusal();
      });
      final resolver = _resolver(
        transport,
        servers: {
          PgcResolverRegion.hk: Uri.parse('https://hk.test/'),
          PgcResolverRegion.sea: Uri.parse('http://sea.test/proxy'),
        },
        defaultRegion: PgcResolverRegion.sea,
      );

      final season = await resolver.resolveSeason(
        seasonId: '42',
        episodeId: '9',
        requireEpisodes: true,
      );

      expect(season, isNotNull);
      expect(season!.title, 'Modules');
      expect(season.episodes.single.sectionTitle, 'Extra');
      expect(transport.requests.map((request) => request.uri.path), [
        '/proxy/pgc/view/v2/app/season',
        '/proxy/pgc/view/web/season',
        '/proxy/intl/gateway/v2/ogv/view/app/season',
      ]);
      for (final request in transport.requests) {
        expect(request.uri.queryParameters, {
          'season_id': '42',
          'ep_id': '9',
          'area': 'th',
        });
        expect(request.uri.queryParameters, isNot(contains('access_key')));
        expect(
          request.headers.keys.map((key) => key.toLowerCase()),
          isNot(contains('cookie')),
        );
        expect(
          request.headers.keys.map((key) => key.toLowerCase()),
          isNot(contains('authorization')),
        );
      }
    });

    test('play uses default region first then hk sea cn path order', () async {
      final transport = _Transport((request) {
        if (request.uri.queryParameters['area'] == 'cn' &&
            request.uri.path == '/pgc/player/web/playurl') {
          return _playReply();
        }
        return _refusal();
      });
      final resolver = _resolver(
        transport,
        servers: {
          PgcResolverRegion.cn: Uri.parse('https://cn.test/'),
          PgcResolverRegion.sea: Uri.parse('https://sea.test/'),
          PgcResolverRegion.hk: Uri.parse('https://hk.test/'),
          PgcResolverRegion.tw: Uri.parse('https://tw.test/'),
        },
        defaultRegion: PgcResolverRegion.tw,
      );

      final info = await resolver.resolvePlayInfo('9', qn: 64);

      expect(info, isNotNull);
      expect(transport.requests.map((request) => request.uri.path), [
        '/pgc/player/api/playurl',
        '/pgc/player/web/playurl',
        '/pgc/player/api/playurl',
        '/pgc/player/web/playurl',
        '/pgc/player/web/playurl',
        '/intl/gateway/v2/ogv/playurl',
        '/pgc/player/api/playurl',
        '/pgc/player/api/playurl',
        '/pgc/player/web/playurl',
      ]);
      expect(
        transport.requests.map(
          (request) => request.uri.queryParameters['area'],
        ),
        ['tw', 'tw', 'hk', 'hk', 'th', 'th', 'th', 'cn', 'cn'],
      );
      for (final request in transport.requests) {
        expect(request.uri.queryParameters, {
          'ep_id': '9',
          'qn': '64',
          'fnval': '4048',
          'fnver': '0',
          'fourk': '1',
          'force_host': '2',
          'module': 'bangumi',
          'platform': 'android',
          'mobi_app': 'android',
          'device': 'android',
          'area': request.uri.queryParameters['area'],
        });
        expect(request.uri.queryParameters, isNot(contains('access_key')));
        expect(
          request.headers.keys.map((key) => key.toLowerCase()),
          isNot(contains('cookie')),
        );
      }
    });

    test('without a default region detail keeps hk tw sea cn order', () async {
      final transport = _Transport((_) => _refusal());
      final resolver = _resolver(
        transport,
        servers: {
          PgcResolverRegion.cn: Uri.parse('https://cn.test/'),
          PgcResolverRegion.sea: Uri.parse('https://sea.test/'),
          PgcResolverRegion.tw: Uri.parse('https://tw.test/'),
          PgcResolverRegion.hk: Uri.parse('https://hk.test/'),
        },
      );

      expect(await resolver.resolveSeason(seasonId: '42'), isNull);
      expect(
        transport.requests.map(
          (request) => request.uri.queryParameters['area'],
        ),
        ['hk', 'hk', 'tw', 'tw', 'th', 'th', 'th', 'cn', 'cn'],
      );
    });

    test('data video_info envelope maps all DASH track variants', () async {
      final transport = _Transport((_) => _playReply(wrapped: true));
      final info = await _resolver(transport).resolvePlayInfo('9');

      expect(info, isNotNull);
      expect(info!.duration, const Duration(milliseconds: 123456));
      expect(info.acceptQuality, [80, 64]);
      expect(info.pgcSkipSegments.single.type, ApiPgcSkipType.intro);
      expect(info.dashVideo.single.id, 80);
      expect(info.dashVideo.single.bandwidth, 2_000_000);
      expect(info.dashVideo.single.mimeType, 'video/mp4');
      expect(info.dashVideo.single.codecs, 'avc1.640028');
      expect(info.dashVideo.single.backupUrls, [
        Uri.parse('https://upos-hz-mirror.bilivideo.com/video.m4s'),
      ]);
      expect(info.dashAudio.map((track) => track.id), [30232, 30251, 30216]);
      expect(
        info.dashAudio.first.backupUrls.single.host,
        'upos-hz-mirror.bilivideo.com',
      );
      expect(info.dashAudio.last.codecs, 'ec-3');
    });

    test(
      'bounded transport receives 2 MiB play and 4 MiB detail caps',
      () async {
        final transport = _BoundedTransport(
          (request) => request.uri.path.contains('/player/')
              ? _playReply()
              : _seasonReply(),
        );
        final resolver = _resolver(transport);

        expect(await resolver.resolvePlayInfo('9'), isNotNull);
        expect(await resolver.resolveSeason(seasonId: '42'), isNotNull);
        expect(transport.limits, [2 * 1024 * 1024, 4 * 1024 * 1024]);
      },
    );

    test('plain transport responses are capped after receipt too', () async {
      var body = Uint8List(2 * 1024 * 1024 + 1);
      final transport = _Transport((_) => ApiHttpResponse(200, body, const {}));
      final resolver = _resolver(transport);
      expect(await resolver.resolvePlayInfo('9'), isNull);
      expect(transport.requests, hasLength(2));

      body = Uint8List(4 * 1024 * 1024 + 1);
      expect(await resolver.resolveSeason(seasonId: '42'), isNull);
      expect(transport.requests, hasLength(4));
    });

    test('a pending request times out and cancels its attempt', () async {
      ApiCancellation? attempt;
      final transport = _Transport((request) {
        attempt = request.cancellation;
        return Completer<ApiHttpResponse>().future;
      });
      final resolver = _resolver(
        transport,
        timeout: const Duration(milliseconds: 20),
      );

      await expectLater(
        resolver.resolvePlayInfo('9'),
        throwsA(
          _failure(
            ApiFailureCategory.timeout,
            endpoint: 'pgc_resolver_playurl',
          ),
        ),
      );
      expect(attempt?.isCancelled, isTrue);
    });

    test('pre-cancelled context performs no resolver request', () async {
      final transport = _Transport((_) => _seasonReply());
      final cancellation = ApiCancellation()..cancel();
      await expectLater(
        _resolver(transport).resolveSeason(
          seasonId: '42',
          context: ApiRequestContext(cancellation: cancellation),
        ),
        throwsA(_failure(ApiFailureCategory.cancelled)),
      );
      expect(transport.requests, isEmpty);
    });
  });

  group('PgcClient fallback', () {
    test(
      'one client resolves both detail and play after official refusals',
      () async {
        final official = _Transport((request) {
          if (request.uri.path == '/pgc/view/web/season') {
            return _refusal(-404);
          }
          return _refusal(-10403);
        });
        final resolving = _Transport(
          (request) => request.uri.path.contains('/view/')
              ? _seasonReply(title: 'Fallback detail')
              : _playReply(wrapped: true),
        );
        final client = PgcClient(
          BiliApiClient(transport: official),
          resolver: _resolver(
            resolving,
            servers: {PgcResolverRegion.sea: Uri.parse('https://sea.test/')},
          ),
        );

        final season = await client.getSeason(
          episodeId: '9',
          requireEpisodes: true,
        );
        final info = await client.getPlayInfo('9', qn: 80);

        expect(season.title, 'Fallback detail');
        expect(season.episodes.single.episodeId, '9');
        expect(info.dashVideo.single.id, 80);
        expect(info.dashAudio, isNotEmpty);
        expect(official.requests, hasLength(2));
        expect(resolving.requests.map((request) => request.uri.path), [
          '/pgc/view/v2/app/season',
          '/pgc/player/web/playurl',
        ]);
      },
    );

    test(
      'official success and non-region failures never invoke resolver',
      () async {
        final resolving = _Transport((_) => _seasonReply());
        final resolver = _resolver(resolving);
        final successful = PgcClient(
          BiliApiClient(
            transport: _Transport((_) => _seasonReply(title: 'Official')),
          ),
          resolver: resolver,
        );
        expect((await successful.getSeason(seasonId: '42')).title, 'Official');
        expect(resolving.requests, isEmpty);

        final limited = PgcClient(
          BiliApiClient(transport: _Transport((_) => _refusal(-412))),
          resolver: resolver,
        );
        await expectLater(
          limited.getPlayInfo('9'),
          throwsA(
            _failure(
              ApiFailureCategory.rateLimited,
              endpoint: 'pgc_playurl',
              businessCode: -412,
            ),
          ),
        );
        expect(resolving.requests, isEmpty);
      },
    );

    test(
      'empty resolver detail cannot replace the original not-found error',
      () async {
        final resolving = _Transport(
          (_) => _json({'code': 0, 'result': _seasonResult(episodes: [])}),
        );
        final client = PgcClient(
          BiliApiClient(transport: _Transport((_) => _refusal(62002))),
          resolver: _resolver(resolving),
        );

        await expectLater(
          client.getSeason(seasonId: '42', requireEpisodes: true),
          throwsA(
            _failure(
              ApiFailureCategory.notFound,
              endpoint: 'pgc_season',
              businessCode: 62002,
            ),
          ),
        );
        expect(resolving.requests, hasLength(2));
      },
    );

    test(
      'invalid resolver play preserves the original inner refusal',
      () async {
        final resolving = _Transport(
          (_) => _json({
            'code': 0,
            'result': {'dash': {}},
          }),
        );
        final client = PgcClient(
          BiliApiClient(
            transport: _Transport(
              (_) => _json({
                'code': 0,
                'result': {'code': -10403},
              }),
            ),
          ),
          resolver: _resolver(resolving),
        );

        await expectLater(
          client.getPlayInfo('9'),
          throwsA(
            _failure(
              ApiFailureCategory.permission,
              endpoint: 'pgc_playurl',
              businessCode: -10403,
            ),
          ),
        );
        expect(resolving.requests, hasLength(2));
      },
    );

    test('cancelling an in-flight fallback returns cancellation', () async {
      final started = Completer<void>();
      final resolving = _Transport((_) {
        started.complete();
        return Completer<ApiHttpResponse>().future;
      });
      final cancellation = ApiCancellation();
      final client = PgcClient(
        BiliApiClient(transport: _Transport((_) => _refusal(-404))),
        resolver: _resolver(resolving),
      );

      final result = client.getSeason(
        seasonId: '42',
        context: ApiRequestContext(cancellation: cancellation),
      );
      await started.future;
      cancellation.cancel();

      await expectLater(
        result,
        throwsA(
          _failure(
            ApiFailureCategory.cancelled,
            endpoint: 'pgc_resolver_season',
          ),
        ),
      );
    });

    test(
      'resolver provider reads live configuration for each request',
      () async {
        final resolving = _Transport(
          (_) => _json({'code': 0, 'result': _seasonResult()}),
        );
        var reads = 0;
        final client = PgcClient(
          BiliApiClient(transport: _Transport((_) => _refusal(-404))),
          resolverProvider: () async =>
              ++reads == 1 ? null : _resolver(resolving),
        );

        await expectLater(
          client.getSeason(seasonId: '42'),
          throwsA(
            _failure(
              ApiFailureCategory.permission,
              endpoint: 'pgc_season',
              businessCode: -404,
            ),
          ),
        );
        final season = await client.getSeason(seasonId: '42');
        expect(season.title, 'Resolved season');
        expect(reads, 2);
      },
    );
  });
}
