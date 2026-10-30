import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/feed/data/api_home_repository.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const _query = (
  channel: HomeChannel.favorites,
  section: '我的收藏与订阅',
  scope: 'user:7',
  folderId: 'ugc:42',
);

void main() {
  late _Transport transport;
  late ApiRequests requests;
  late BiliApiClient api;
  late ApiHomeRepository repository;
  var scope = 'user:7';
  setUp(() {
    scope = 'user:7';
    transport = _Transport();
    requests = ApiRequests();
    api = BiliApiClient(transport: transport, sessionProvider: requests);
    repository = ApiHomeRepository(
      HomeClient(api),
      requests,
      accountScope: () => scope,
    );
  });
  tearDown(() => api.close());
  Future<HomePage> load(int page, {String? cursor, HomeQuery query = _query}) =>
      repository.load(
        query,
        page: page,
        cursor: cursor,
        cancellation: RequestCancellation(),
      );

  test('an endpoint returning the whole collection exposes stable local pages of 99', () async {
    final first = await load(1);
    expect(first.items, hasLength(99));
    expect(first.hasMore, true);
    expect(first.nextCursor, startsWith('local-favorite-'));
    final second = await load(2, cursor: first.nextCursor);
    final third = await load(3, cursor: first.nextCursor);
    final previous = await load(1, cursor: first.nextCursor);
    expect(second.items, hasLength(99));
    expect(second.items.first.title, '视频 99');
    expect(third.items, hasLength(52));
    expect(third.hasMore, false);
    expect(previous.items.first.title, '视频 0');
    expect(transport.uris, hasLength(1));
  });

  test(
    'refreshing the browser cannot replace a captured collection snapshot',
    () async {
      final original = await load(1);
      transport.offset = 1000;
      final fresh = await load(1);
      expect(fresh.items.first.title, '视频 1000');
      final later = await load(2, cursor: original.nextCursor);
      expect(later.items.first.title, '视频 99');
      expect(transport.uris, hasLength(2));
    },
  );

  test(
    'session transitions clear old snapshots before they can be reused',
    () async {
      final page = await load(1);
      requests.advanceSession();
      await expectLater(
        load(2, cursor: page.nextCursor),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.kind,
            'kind',
            AppFailureKind.notFound,
          ),
        ),
      );
      scope = 'user:8';
      await expectLater(
        load(2, cursor: page.nextCursor),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.kind,
            'kind',
            AppFailureKind.cancelled,
          ),
        ),
      );
      expect(transport.uris, hasLength(1));
    },
  );

  test(
    'a cursor cannot read another folder or evict its valid snapshot',
    () async {
      final page = await load(1);
      const other = (
        channel: HomeChannel.favorites,
        section: '我的收藏与订阅',
        scope: 'user:7',
        folderId: 'ugc:43',
      );
      await expectLater(
        load(2, query: other, cursor: page.nextCursor),
        throwsA(isA<AppFailure>()),
      );
      expect(
        (await load(2, cursor: page.nextCursor)).items.first.title,
        '视频 99',
      );
    },
  );

  test(
    'snapshot storage has a bounded LRU and bounds oversized payloads',
    () async {
      transport.count = 6000;
      final original = await load(1);
      final last = await load(51, cursor: original.nextCursor);
      expect(last.items, hasLength(50));
      expect(last.hasMore, false);
      transport.count = 250;
      for (var n = 0; n < 16; n++) {
        await load(1);
      }
      await expectLater(
        load(2, cursor: original.nextCursor),
        throwsA(isA<AppFailure>()),
      );
    },
  );

  test(
    'watch-later still exposes the complete list without local paging',
    () async {
      const watchLater = (
        channel: HomeChannel.watchLater,
        section: '全部',
        scope: 'user:7',
        folderId: null,
      );
      final page = await load(1, query: watchLater);
      expect(page.items, hasLength(250));
      expect(page.hasMore, false);
      expect(page.nextCursor, isNull);
      expect(transport.uris.single.path, '/x/v2/history/toview');
    },
  );
}

final class _Transport implements ApiTransport {
  final uris = <Uri>[];
  int count = 250, offset = 0;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    uris.add(uri);
    final items = [
      for (var n = offset; n < offset + count; n++)
        {
          'id': n + 1,
          'aid': n + 1,
          'bvid': 'BV${n.toString().padLeft(10, '0')}',
          'title': '视频 $n',
          'owner': {'mid': 7, 'name': 'UP'},
        },
    ];
    final data = uri.path == '/x/v2/history/toview'
        ? {'list': items}
        : {
            'medias': items,
            'info': {'media_count': count},
            'has_more': false,
          };
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
      const {},
    );
  }
}
