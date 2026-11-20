import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/pgc/data/api_pgc_repository.dart';
import 'package:bilisail/features/pgc/domain/pgc_repository.dart';
import 'package:flutter_test/flutter_test.dart';

ApiHttpResponse _response(
  String id, {
  String title = '本篇',
  bool empty = false,
}) => ApiHttpResponse(
  200,
  Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'code': 0,
        'result': {
          'season_id': id,
          'title': title,
          'episodes': [
            for (var i = 1; !empty && i <= 12; i++)
              {
                'id': '${id}00$i',
                'title': '$i',
                'bvid': 'BV1ab411c7mD',
                'cid': '$i',
                'status': 2,
              },
          ],
        },
      }),
    ),
  ),
  const {},
);

final class _Read {
  _Read(this.uri, this.cancellation);
  final Uri uri;
  final ApiCancellation? cancellation;
  final result = Completer<ApiHttpResponse>();
  void complete({String? seasonId, String title = '本篇', bool empty = false}) =>
      result.complete(
        _response(
          seasonId ?? uri.queryParameters['season_id'] ?? '42',
          title: title,
          empty: empty,
        ),
      );
}

final class _Transport implements ApiTransport {
  final reads = <_Read>[];
  void Function(_Read)? onRead;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) {
    final read = _Read(uri, cancellation);
    reads.add(read);
    onRead?.call(read);
    return read.result.future;
  }
}

Future<void> _turn() => Future<void>.delayed(Duration.zero);
Matcher get _cancelled =>
    isA<AppFailure>().having((f) => f.kind, 'kind', AppFailureKind.cancelled);

void main() {
  late _Transport transport;
  late ApiRequests requests;
  late ApiPgcRepository repository;
  late DateTime now;
  late String scope;
  setUp(() {
    transport = _Transport();
    requests = ApiRequests();
    now = DateTime.utc(2026);
    scope = 'guest';
    repository = ApiPgcRepository(
      PgcClient(BiliApiClient(transport: transport, sessionProvider: requests)),
      requests,
      accountScope: () => scope,
      clock: () => now,
      maxCachedSeasons: 2,
      maxPendingSeasons: 3,
    );
  });

  Future<PgcSeason> read(
    String id, {
    RequestCancellation? cancellation,
    bool refresh = false,
  }) => repository.detail(
    seasonId: PgcSeasonId(id),
    refresh: refresh,
    cancellation: cancellation ?? RequestCancellation(),
  );

  test(
    'episode detail recovers from an empty list and caches the result',
    () async {
      const episodeId = PgcEpisodeId('42002');
      transport.onRead = (request) {
        request.complete(empty: transport.reads.length == 1);
      };

      final season = await repository.detail(
        episodeId: episodeId,
        cancellation: RequestCancellation(),
      );
      expect(season.episode(episodeId)?.playable, isTrue);
      expect(transport.reads.map((r) => r.uri.queryParameters), [
        {'ep_id': episodeId.value},
        {'ep_id': episodeId.value},
      ]);
      expect(await read('42'), same(season));
      expect(transport.reads, hasLength(2));
    },
  );

  test('season-only empty detail does not mask episodes on reopen', () async {
    transport.onRead = (request) {
      request.complete(empty: transport.reads.length == 1);
    };

    expect((await read('42')).episodes, isEmpty);
    expect(transport.reads, hasLength(1));
    expect((await read('42')).episodes, isNotEmpty);
    expect(transport.reads, hasLength(2));
  });

  test(
    'concurrent season reads share one request and episode links reuse result',
    () async {
      final first = read('42');
      final second = read('42');
      await _turn();
      expect(transport.reads.length, 1);
      transport.reads.single.complete();
      final season = await first;
      expect(identical(await second, season), isTrue);
      expect(identical(await read('42'), season), isTrue);
      final episodeLink = await repository.detail(
        episodeId: season.episodes.last.id,
        cancellation: RequestCancellation(),
      );
      expect(identical(episodeLink, season), isTrue);
      expect(transport.reads.length, 1);
    },
  );

  test('one cancelled consumer leaves shared request alive', () async {
    final signal = RequestCancellation();
    final first = read('42', cancellation: signal);
    final second = read('42');
    final expected = expectLater(first, throwsA(_cancelled));
    signal.cancel();
    await expected;
    expect(transport.reads.single.cancellation?.isCancelled, isFalse);
    transport.reads.single.complete();
    expect((await second).seasonId, '42');
    expect(transport.reads.length, 1);
  });

  test(
    'last cancelled consumer cancels transport and late data is not cached',
    () async {
      final signal = RequestCancellation();
      final first = read('42', cancellation: signal);
      final expected = expectLater(first, throwsA(_cancelled));
      signal.cancel();
      await expected;
      expect(transport.reads.single.cancellation?.isCancelled, isTrue);
      transport.reads.single.complete(title: '旧数据');
      await _turn();
      final second = read('42');
      expect(transport.reads.length, 2);
      transport.reads.last.complete(title: '新数据');
      expect((await second).title, '新数据');
    },
  );

  test('refresh bypasses old flight and late old response cannot replace fresh data', () async {
    final first = read('42');
    final fresh = read('42', refresh: true);
    expect(transport.reads.length, 2);
    transport.reads.last.complete(title: '刷新后');
    final current = await fresh;
    transport.reads.first.complete(title: '刷新前');
    expect((await first).title, '刷新前');
    expect(identical(await read('42'), current), isTrue);
    expect(transport.reads.length, 2);
  });

  test('TTL expires details and episode aliases; LRU evicts both', () async {
    for (final id in ['41', '42']) {
      final future = read(id);
      transport.reads.last.complete();
      await future;
    }
    await read('41'); // Make 42 least recently used.
    final third = read('43');
    transport.reads.last.complete();
    await third;
    final evicted = repository.detail(
      episodeId: const PgcEpisodeId('42001'),
      cancellation: RequestCancellation(),
    );
    expect(transport.reads.length, 4);
    expect(transport.reads.last.uri.queryParameters['ep_id'], '42001');
    transport.reads.last.complete();
    await evicted;
    now = now.add(const Duration(minutes: 2));
    final expired = read('42');
    expect(transport.reads.length, 5);
    transport.reads.last.complete();
    await expired;
  });

  test(
    'account transition cancels immediately and cannot reuse old rights',
    () async {
      final first = read('42');
      transport.reads.last.complete();
      await first;
      final old = read('43');
      final expected = expectLater(old, throwsA(_cancelled));
      scope = 'user:7';
      requests.advanceSession();
      expect(transport.reads.last.cancellation?.isCancelled, isTrue);
      transport.reads.last.complete(title: '旧账号');
      await expected;
      final next = read('42');
      expect(transport.reads.length, 3);
      transport.reads.last.complete(title: '新账号');
      expect((await next).title, '新账号');
    },
  );

  test(
    'cache does not satisfy an unknown episode using only its season ID',
    () async {
      final first = read('42');
      transport.reads.last.complete();
      await first;
      final unknown = repository.detail(
        seasonId: const PgcSeasonId('42'),
        episodeId: const PgcEpisodeId('999'),
        cancellation: RequestCancellation(),
      );
      expect(transport.reads.length, 2);
      transport.reads.last.complete();
      await unknown;
    },
  );

  test('pending requests have a hard capacity and cancelled caller does not start work', () async {
    final signal = RequestCancellation()..cancel();
    await expectLater(read('40', cancellation: signal), throwsA(_cancelled));
    expect(transport.reads, isEmpty);
    final pending = [read('41'), read('42'), read('43')];
    await expectLater(
      read('44'),
      throwsA(
        isA<AppFailure>().having(
          (e) => e.kind,
          'kind',
          AppFailureKind.rateLimited,
        ),
      ),
    );
    expect(transport.reads.length, 3);
    for (final item in transport.reads) {
      item.complete();
    }
    await Future.wait(pending);
  });
}
