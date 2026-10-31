import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/library/data/api_library_repository.dart';
import 'package:bilisail/features/library/domain/library_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> history(String bvid, {int page = 1, int progress = 20}) =>
    {
      'kid': '9007199254740997',
      'title': '云端 $bvid',
      'cover': '',
      'author_name': '云端作者',
      'author_mid': 123,
      'view_at': 1791324000,
      'duration': 100,
      'progress': progress,
      'history': {
        'business': 'archive',
        'bvid': bvid,
        'cid': '$page',
        'page': page,
        'part': '分 P',
      },
    };
Map<String, Object?> detail(
  String bvid, {
  Object? view = 12345,
  Object? danmaku = 0,
}) => {
  'aid': 1,
  'bvid': bvid,
  'title': '视频详情',
  'pic': '',
  'pubdate': 1700000000,
  'owner': {'name': '详情作者'},
  'stat': {'view': view, 'danmaku': danmaku},
  'pages': [
    {'cid': 1, 'page': 1, 'part': 'P1', 'duration': 999},
  ],
};
Map<String, Object?> historyData(List<Object?> list) => {
  'list': list,
  'cursor': {'max': 0, 'view_at': 0, 'business': ''},
};

final class _Transport implements ApiTransport, ApiFormTransport {
  _Transport(this.handler);
  final FutureOr<Map<String, Object?>> Function(Uri) handler;
  final List<Uri> requests = [];
  final List<Uri> posts = [];
  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    posts.add(uri);
    final data = await handler(uri);
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode(data))),
      {},
    );
  }

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    requests.add(uri);
    final data = await handler(uri);
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode(data))),
      {},
    );
  }
}

void main() {
  test(
    'search forwards keyword and page while keeping enriched history metadata',
    () async {
      final transport = _Transport(
        (uri) => {
          'code': 0,
          'data': uri.path.endsWith('/search')
              ? {
                  'list': [history('BV1234567890')],
                }
              : detail('BV1234567890'),
        },
      );
      final requests = ApiRequests();
      final api = BiliApiClient(
        transport: transport,
        sessionProvider: requests,
      );
      addTearDown(api.close);
      final repository = ApiLibraryRepository(
        WatchHistoryClient(api),
        requests,
        accountScope: () => 'user:1',
      );
      final page = await repository.loadHistory(
        keyword: '关键词',
        cursor: '2',
        cancellation: RequestCancellation(),
      );
      expect(transport.requests.first.path, '/x/web-interface/history/search');
      expect(transport.requests.first.queryParameters, {
        'keyword': '关键词',
        'pn': '2',
        'business': 'all',
      });
      expect(page.nextCursor, '3');
      expect(page.items.single.video.playCount, 12345);
      expect(
        page.items.single.location.toString(),
        '/video/BV1234567890?cid=1',
      );
      expect(page.items.single.deletionKey, 'archive_9007199254740997');
    },
  );
  for (final clear in [false, true]) {
    for (final change in [
      'none',
      'scope',
      'epoch',
      'cancel',
      'guest',
      'uncertain',
      'denied',
    ]) {
      test('${clear ? 'clear' : 'delete'} write handles $change', () async {
        final gate = Completer<Map<String, Object?>>();
        final requests = ApiRequests();
        var scope = change == 'guest' ? 'guest' : 'user:1';
        final token = RequestCancellation();
        final transport = _Transport((_) => gate.future);
        final api = BiliApiClient(
          transport: transport,
          sessionProvider: requests,
          cookieJar: ApiCookieJar()
            ..receive(Uri.https('api.bilibili.com', '/'), [
              'SESSDATA=fixture; Path=/; Secure',
              'bili_jct=fixture-csrf; Path=/; Secure',
            ]),
        );
        addTearDown(api.close);
        final repository = ApiLibraryRepository(
          WatchHistoryClient(api),
          requests,
          accountScope: () => scope,
        );
        final pending = clear
            ? repository.clearHistory(cancellation: token)
            : repository.deleteHistory(
                'archive_9007199254740997',
                cancellation: token,
              );
        final assertion = change == 'none'
            ? expectLater(pending, completes)
            : expectLater(
                pending,
                throwsA(
                  change == 'uncertain'
                      ? isA<HistoryWriteUncertain>()
                      : isA<AppFailure>().having(
                          (e) => e.kind,
                          'kind',
                          switch (change) {
                            'guest' => AppFailureKind.authentication,
                            'denied' => AppFailureKind.permission,
                            _ => AppFailureKind.cancelled,
                          },
                        ),
                ),
              );
        if (change == 'scope') scope = 'user:2';
        if (change == 'epoch') requests.advanceSession();
        if (change == 'cancel') token.cancel();
        if (change == 'uncertain') {
          gate.completeError(
            const ApiFailure(ApiFailureCategory.network, 'fixture'),
          );
        } else {
          gate.complete({'code': change == 'denied' ? -403 : 0, 'data': null});
        }
        await assertion;
        expect(transport.posts, hasLength(change == 'guest' ? 0 : 1));
      });
    }
  }
  test('reads cloud data, enriches real counts once per BVID, retains watch snapshot', () async {
    final transport = _Transport(
      (uri) => {
        'code': 0,
        'data': uri.path.endsWith('/cursor')
            ? historyData([
                history('BV1234567890'),
                history('BV1234567890', page: 2, progress: -1),
              ])
            : detail(uri.queryParameters['bvid'] ?? ''),
      },
    );
    final requests = ApiRequests();
    final repository = ApiLibraryRepository(
      WatchHistoryClient(
        BiliApiClient(transport: transport, sessionProvider: requests),
      ),
      requests,
      accountScope: () => 'user:1',
    );
    final page = await repository.loadHistory(
      cancellation: RequestCancellation(),
    );
    expect(
      transport.requests.where((uri) => uri.path.endsWith('/view')),
      hasLength(1),
    );
    final entry = page.items.first;
    expect(entry.video.title, '云端 BV1234567890');
    expect(entry.deletionKey, 'archive_9007199254740997');
    expect(entry.video.playCount, 12345);
    expect(entry.video.danmakuCount, 0);
    expect(entry.video.authorId?.value, '123');
    expect(entry.video.publishedAt, isNull);
    expect(entry.video.duration.inSeconds, 100);
    expect(entry.location.toString(), '/video/BV1234567890?cid=1');
    expect(page.items.last.location.queryParameters['cid'], '2');
    expect(page.items.last.position.inSeconds, 100);
  });

  test(
    'missing details retain history, and missing counts stay null',
    () async {
      final transport = _Transport(
        (uri) => uri.path.endsWith('/cursor')
            ? {
                'code': 0,
                'data': historyData([
                  history('BV1234567890'),
                  history('BV1234567891'),
                ]),
              }
            : uri.queryParameters['bvid'] == 'BV1234567890'
            ? {'code': -404}
            : {
                'code': 0,
                'data': detail('BV1234567891', view: null, danmaku: null),
              },
      );
      final requests = ApiRequests();
      final repository = ApiLibraryRepository(
        WatchHistoryClient(
          BiliApiClient(transport: transport, sessionProvider: requests),
        ),
        requests,
        accountScope: () => 'user:1',
      );
      final page = await repository.loadHistory(
        cancellation: RequestCancellation(),
      );
      expect(page.items, hasLength(2));
      expect(
        page.items.every(
          (entry) =>
              entry.video.playCount == null && entry.video.danmakuCount == null,
        ),
        true,
      );
    },
  );

  test(
    'guest requests explain login without a network read or local fallback',
    () async {
      final transport = _Transport((_) => {'code': 0});
      final requests = ApiRequests();
      final repository = ApiLibraryRepository(
        WatchHistoryClient(
          BiliApiClient(transport: transport, sessionProvider: requests),
        ),
        requests,
        accountScope: () => 'guest',
      );
      await expectLater(
        repository.loadHistory(cancellation: RequestCancellation()),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.kind,
            'kind',
            AppFailureKind.authentication,
          ),
        ),
      );
      expect(transport.requests, isEmpty);
    },
  );

  test('detail reads are limited to three concurrently', () async {
    final gate = Completer<void>();
    var active = 0;
    var maximum = 0;
    final transport = _Transport((uri) async {
      if (uri.path.endsWith('/cursor')) {
        return {
          'code': 0,
          'data': historyData([
            for (var i = 0; i < 8; i++) history('BV123456789$i'),
          ]),
        };
      }
      active++;
      maximum = maximum < active ? active : maximum;
      await gate.future;
      active--;
      return {'code': 0, 'data': detail(uri.queryParameters['bvid'] ?? '')};
    });
    final requests = ApiRequests();
    final repository = ApiLibraryRepository(
      WatchHistoryClient(
        BiliApiClient(transport: transport, sessionProvider: requests),
      ),
      requests,
      accountScope: () => 'user:1',
    );
    final pending = repository.loadHistory(cancellation: RequestCancellation());
    while (active < 3) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(active, 3);
    gate.complete();
    expect((await pending).items, hasLength(8));
    expect(maximum, 3);
  });

  for (final changeEpoch in [false, true]) {
    test(
      '${changeEpoch ? 'same-account epoch' : 'account scope'} change rejects late metadata',
      () async {
        final gate = Completer<void>();
        final started = Completer<void>();
        final requests = ApiRequests();
        var scope = 'user:1';
        final transport = _Transport((uri) async {
          if (uri.path.endsWith('/cursor')) {
            return {
              'code': 0,
              'data': historyData([history('BV1234567890')]),
            };
          }
          started.complete();
          await gate.future;
          return {'code': 0, 'data': detail('BV1234567890')};
        });
        final repository = ApiLibraryRepository(
          WatchHistoryClient(
            BiliApiClient(transport: transport, sessionProvider: requests),
          ),
          requests,
          accountScope: () => scope,
        );
        final pending = repository.loadHistory(
          cancellation: RequestCancellation(),
        );
        final assertion = expectLater(
          pending,
          throwsA(
            isA<AppFailure>().having(
              (e) => e.kind,
              'kind',
              AppFailureKind.cancelled,
            ),
          ),
        );
        await started.future;
        if (changeEpoch) {
          requests.advanceSession();
        } else {
          scope = 'user:2';
        }
        gate.complete();
        await assertion;
      },
    );
  }
}
