import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/feed/data/api_feed_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'current ranking regions reach the API independently of newlist IDs',
    () async {
      final transport = _Transport();
      final requests = ApiRequests();
      final api = BiliApiClient(
        transport: transport,
        sessionProvider: requests,
      );
      addTearDown(api.close);
      final repository = ApiFeedRepository(api, requests);
      final rankingRegions = await repository.loadRankingCategories(
        cancellation: RequestCancellation(),
      );
      expect(transport.requests.single.path, '/x/kv-frontend/namespace/data');
      expect(rankingRegions.map((region) => (region.name, region.id)), const [
        ('游戏', '1008'),
        ('新动画名称', '1005'),
        ('新增分区', '9999'),
      ]);
      for (final id in ['0', ...rankingRegions.map((region) => region.id)]) {
        final page = await repository.loadRanking(
          categoryId: id,
          cancellation: RequestCancellation(),
        );
        final uri = transport.requests.last;
        expect(uri.host, 'api.bilibili.com');
        expect(uri.path, '/x/web-interface/ranking/v2');
        expect(uri.queryParameters['rid'], id);
        expect(uri.queryParameters['type'], 'all');
        expect(uri.queryParameters['w_rid'], isNotEmpty);
        expect(uri.queryParameters['wts'], isNotEmpty);
        expect(uri.queryParameters.containsKey('pn'), isFalse);
        expect(page.hasMore, isFalse);
        expect(page.items.single.title, '榜单$id');
        expect(page.items.single.playCount, 42);
      }
      final categories = await repository.loadCategories(
        cancellation: RequestCancellation(),
      );
      for (final (name, id) in [('动画', '1'), ('音乐', '3'), ('游戏', '4')]) {
        expect(categories.singleWhere((region) => region.name == name).id, id);
        await repository.loadFeed(
          page: 2,
          categoryId: id,
          cancellation: RequestCancellation(),
        );
        final uri = transport.requests.last;
        expect(uri.path, '/x/web-interface/newlist');
        expect(uri.queryParameters['rid'], id);
        expect(uri.queryParameters['pn'], '2');
      }
      expect(
        transport.requests
            .where((uri) => uri.path.endsWith('/ranking/v2'))
            .length,
        4,
      );
      expect(
        transport.requests.any((uri) => uri.path.endsWith('/popular')),
        isFalse,
      );
    },
  );
}

final class _Transport implements ApiTransport {
  final List<Uri> requests = [];

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    requests.add(uri);
    final Object data;
    if (uri.path.endsWith('/nav')) {
      data = {
        'wbi_img': {
          'img_url': 'https://i0.hdslb.com/bfs/wbi/${'a' * 32}.png',
          'sub_url': 'https://i0.hdslb.com/bfs/wbi/${'b' * 32}.png',
        },
      };
    } else if (uri.path == '/x/kv-frontend/namespace/data') {
      expect(uri.queryParameters, {'appKey': '333.1339', 'nscode': '10'});
      data = {
        'data': {
          'channel_list.popular_page_sort': jsonEncode([
            'game',
            'douga',
            'future',
            'anime',
            'all',
          ]),
          'channel_list.game': jsonEncode({'tid': 1008, 'name': '游戏'}),
          'channel_list.douga': jsonEncode({'tid': 1005, 'name': '新动画名称'}),
          'channel_list.future': jsonEncode({'tid': 9999, 'name': '新增分区'}),
          'channel_list.anime': jsonEncode({'seasonType': 1, 'name': '番剧'}),
          'channel_list.all': jsonEncode({'tid': 0, 'name': '全部'}),
        },
      };
    } else {
      final entry = {
        'bvid': 'BV1234567890',
        'title': '榜单${uri.queryParameters['rid']}',
        'duration': 60,
        'owner': {'name': 'UP'},
        'stat': {'view': 42, 'danmaku': 2},
      };
      data = switch (uri.path) {
        '/x/web-interface/ranking/v2' => {
          'list': [entry],
        },
        '/x/web-interface/newlist' => {
          'archives': [entry],
          'page': {'count': 41},
        },
        _ => throw StateError('Unexpected endpoint: ${uri.path}'),
      };
    }
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
      const {},
    );
  }
}
