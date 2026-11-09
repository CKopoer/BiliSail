import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bili_api/src/decoding/pgc_season_decoder.dart';
import 'package:test/test.dart';

final class _Transport implements ApiTransport {
  _Transport(this.body);
  final Uint8List body;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async => ApiHttpResponse(200, body, const {});
}

final class _Session implements ApiSessionProvider {
  @override
  int sessionEpoch = 1;
}

Uint8List _body({
  int count = 12,
  int padding = 0,
  Object? lastId,
  int code = 0,
  Object? progress,
}) => Uint8List.fromList(
  utf8.encode(
    jsonEncode({
      'code': code,
      'result': {
        'season_id': '42',
        'title': '测试季',
        'evaluate': 'x' * padding,
        'user_status': {'progress': progress},
        'episodes': [
          for (var i = 0; i < count; i++)
            {
              'id': i == count - 1 && lastId != null ? lastId : '${i + 1}',
              'bvid': 'BV1ab411c7mD',
              'cid': '${i + 1}',
              'title': '$i',
              'status': 13,
              'badge': '大会员',
            },
        ],
      },
    }),
  ),
);

Matcher _failure(ApiFailureCategory category) => isA<ApiFailure>()
    .having((e) => e.category, 'category', category)
    .having((e) => e.endpointId, 'endpoint', 'pgc_season');

Future<void> _turn() => Future<void>.delayed(Duration.zero);

void main() {
  for (final padding in [0, 512 * 1024]) {
    test(
      'season preserves account episode and seconds progress ($padding)',
      () async {
        final result = await PgcClient(
          BiliApiClient(
            transport: _Transport(
              _body(
                padding: padding,
                progress: {'last_ep_id': '9007199254740993', 'last_time': 426},
              ),
            ),
          ),
        ).getSeason(seasonId: '42');
        expect(result.lastEpisodeId, '9007199254740993');
        expect(result.lastPosition, const Duration(seconds: 426));
      },
    );
  }
  for (final progress in [
    null,
    'invalid',
    {'last_ep_id': 0, 'last_time': -2},
    {'last_ep_id': 1.2, 'last_time': 1.2},
  ]) {
    test(
      'optional malformed season progress does not hide metadata: $progress',
      () {
        final result = decodePgcSeasonBytes(_body(progress: progress));
        expect(result.lastEpisodeId, isNull);
        expect(result.lastPosition, isNull);
        expect(result.episodes, isNotEmpty);
      },
    );
  }
  test('small season stays local and preserves entitlement metadata', () async {
    var workers = 0;
    final client = PgcClient(
      BiliApiClient(
        transport: _Transport(_body()),
        pgcSeasonDecoder: (bytes) async {
          workers++;
          return decodePgcSeasonBytes(bytes);
        },
      ),
    );
    final result = await client.getSeason(seasonId: '42');
    expect(workers, 0);
    expect(result.episodes.length, 12);
    expect(result.episodes.first.playable, isTrue);
    expect(result.episodes.first.permissionText, '大会员');
  });

  test('512 KiB threshold sends one whole response to worker', () async {
    final body = _body(padding: 512 * 1024);
    var workers = 0;
    final client = PgcClient(
      BiliApiClient(
        transport: _Transport(body),
        pgcSeasonDecoder: (bytes) async {
          workers++;
          expect(identical(bytes, body), isTrue);
          return decodePgcSeasonBytes(bytes);
        },
      ),
    );
    expect((await client.getSeason(seasonId: '42')).episodes.length, 12);
    expect(workers, 1);
  });

  test(
    'real worker returns 5000 immutable episodes and rejects invalid IDs',
    () async {
      final body = _body(count: 5000, padding: 512 * 1024);
      final season = await PgcClient(
        BiliApiClient(transport: _Transport(body)),
      ).getSeason(seasonId: '42');
      expect(season.episodes.length, 5000);
      expect(season.episodes.last.episodeId, '5000');
      expect(() => season.episodes.clear(), throwsUnsupportedError);
      await expectLater(
        PgcClient(
          BiliApiClient(
            transport: _Transport(
              _body(count: 5000, padding: 512 * 1024, lastId: 1.2),
            ),
          ),
        ).getSeason(seasonId: '42'),
        throwsA(_failure(ApiFailureCategory.protocol)),
      );
    },
  );

  test('business error classification survives worker boundary', () async {
    await expectLater(
      PgcClient(
        BiliApiClient(
          transport: _Transport(_body(padding: 512 * 1024, code: -101)),
        ),
      ).getSeason(seasonId: '42'),
      throwsA(_failure(ApiFailureCategory.authentication)),
    );
  });

  test('4 MiB budget rejects injected transport before worker', () async {
    var workers = 0;
    final client = PgcClient(
      BiliApiClient(
        transport: _Transport(Uint8List(4 * 1024 * 1024 + 1)),
        pgcSeasonDecoder: (bytes) async {
          workers++;
          return decodePgcSeasonBytes(bytes);
        },
      ),
    );
    await expectLater(
      client.getSeason(seasonId: '42'),
      throwsA(_failure(ApiFailureCategory.protocol)),
    );
    expect(workers, 0);
  });

  for (final invalidation in ['cancel', 'epoch', 'deadline']) {
    test('running worker discards output after $invalidation', () async {
      final session = _Session();
      final signal = ApiCancellation();
      final pending = Completer<ApiPgcSeason>();
      var now = DateTime.utc(2026);
      var started = false;
      final client = PgcClient(
        BiliApiClient(
          transport: _Transport(_body(padding: 512 * 1024)),
          sessionProvider: session,
          clock: () => now,
          pgcSeasonDecoder: (_) {
            started = true;
            return pending.future;
          },
        ),
      );
      final request = client.getSeason(
        seasonId: '42',
        context: ApiRequestContext(
          cancellation: signal,
          sessionEpoch: session.sessionEpoch,
          deadline: now.add(const Duration(seconds: 1)),
        ),
      );
      await _turn();
      expect(started, isTrue);
      if (invalidation == 'cancel') signal.cancel();
      if (invalidation == 'epoch') session.sessionEpoch++;
      if (invalidation == 'deadline') now = now.add(const Duration(seconds: 2));
      final expectation = expectLater(
        request,
        throwsA(
          _failure(
            invalidation == 'deadline'
                ? ApiFailureCategory.timeout
                : ApiFailureCategory.cancelled,
          ),
        ),
      );
      pending.complete(decodePgcSeasonBytes(_body()));
      await expectation;
    });
  }

  test(
    'two running and four queued decodes are bounded; cancellation holds running slot',
    () async {
      final pending = <Completer<ApiPgcSeason>>[];
      final body = _body(padding: 512 * 1024);
      final client = PgcClient(
        BiliApiClient(
          transport: _Transport(body),
          pgcSeasonDecoder: (_) {
            final complete = Completer<ApiPgcSeason>();
            pending.add(complete);
            return complete.future;
          },
        ),
      );
      final firstCancel = ApiCancellation();
      final queueCancel = ApiCancellation();
      final requests = [
        for (var i = 0; i < 6; i++)
          client.getSeason(
            seasonId: '42',
            context: ApiRequestContext(
              cancellation: i == 0
                  ? firstCancel
                  : i == 2
                  ? queueCancel
                  : null,
            ),
          ),
      ];
      await _turn();
      expect(pending.length, 2);
      await expectLater(
        client.getSeason(seasonId: '42'),
        throwsA(_failure(ApiFailureCategory.unavailable)),
      );
      final firstExpected = expectLater(
        requests[0],
        throwsA(_failure(ApiFailureCategory.cancelled)),
      );
      final queuedExpected = expectLater(
        requests[2],
        throwsA(_failure(ApiFailureCategory.cancelled)),
      );
      firstCancel.cancel();
      queueCancel.cancel();
      await queuedExpected;
      await _turn();
      expect(pending.length, 2);
      final result = decodePgcSeasonBytes(_body());
      pending[0].complete(result);
      await firstExpected;
      await _turn();
      expect(pending.length, 3);
      for (var i = 1; i < 5; i++) {
        pending[i].complete(result);
        await _turn();
      }
      await Future.wait([requests[1], requests[3], requests[4], requests[5]]);
    },
  );
}
