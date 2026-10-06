import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  test(
    'website sort controls names, IDs and order without a region allowlist',
    () async {
      final transport = _Transport(
        (_) async => _response({
          'data': {
            'channel_list.popular_page_sort': jsonEncode([
              'all',
              'anime',
              'movie',
              'missing',
              'future',
              'game',
              'duplicate',
            ]),
            'channel_list.all': jsonEncode({'tid': 0, 'name': '全部'}),
            'channel_list.anime': jsonEncode({'seasonType': 1, 'name': '番剧'}),
            'channel_list.movie': jsonEncode({
              'seasonType': 2,
              'tid': 23,
              'name': '电影',
            }),
            'channel_list.future': jsonEncode({'tid': '9999', 'name': '新分区'}),
            'channel_list.game': jsonEncode({'tid': 1008, 'name': '新游戏名称'}),
            'channel_list.duplicate': jsonEncode({'tid': 1008, 'name': '重复'}),
            'channel_list.unlisted': jsonEncode({'tid': 8888, 'name': '未开放排行'}),
          },
        }),
      );
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      final regions = await RankingClient(api).getRegions();
      expect(regions.map((region) => (region.id, region.name)), [
        ('9999', '新分区'),
        ('1008', '新游戏名称'),
      ]);
      expect(() => regions.clear(), throwsUnsupportedError);
      final uri = transport.requests.single;
      expect(uri.scheme, 'https');
      expect(uri.host, 'api.bilibili.com');
      expect(uri.path, '/x/kv-frontend/namespace/data');
      expect(uri.queryParameters, {'appKey': '333.1339', 'nscode': '10'});
    },
  );

  final invalidConfigs = <String, Map<String, Object?>>{
    'malformed sort JSON': {'channel_list.popular_page_sort': '['},
    'sort is not a list': {'channel_list.popular_page_sort': '{}'},
    'too many entries': {
      'channel_list.popular_page_sort': jsonEncode(List.filled(129, 'game')),
    },
    'malformed referenced region': {
      'channel_list.popular_page_sort': '["game"]',
      'channel_list.game': '{',
    },
    'fractional ID': _config({'tid': 1008.5, 'name': '游戏'}),
    'negative ID': _config({'tid': -1008, 'name': '游戏'}),
    'invalid ID string': _config({'tid': '1008&type=origin', 'name': '游戏'}),
    'missing name': _config({'tid': 1008}),
    'oversized value': {
      'channel_list.popular_page_sort': '["game"]',
      'channel_list.game': ' ' * 65537,
    },
    'no available UGC region': _config({'tid': 0, 'name': '全部'}),
  };
  for (final entry in invalidConfigs.entries) {
    test('${entry.key} is a protocol error without a fixed fallback', () async {
      final transport = _Transport(
        (_) async => _response({'data': entry.value}),
      );
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      await expectLater(RankingClient(api).getRegions(), throwsA(_protocol));
      expect(transport.requests, hasLength(1));
    });
  }

  test('directory rate limiting stops after one request', () async {
    final transport = _Transport((_) async => _response(null, code: -352));
    final api = BiliApiClient(transport: transport);
    addTearDown(api.close);
    await expectLater(
      RankingClient(api).getRegions(),
      throwsA(
        isA<ApiFailure>().having(
          (failure) => failure.category,
          'category',
          ApiFailureCategory.rateLimited,
        ),
      ),
    );
    expect(transport.requests, hasLength(1));
  });

  test('account change discards a late directory response', () async {
    final session = _Session();
    final response = Completer<ApiHttpResponse>();
    final transport = _Transport((_) => response.future);
    final api = BiliApiClient(transport: transport, sessionProvider: session);
    addTearDown(api.close);
    final pending = RankingClient(
      api,
    ).getRegions(context: ApiRequestContext(sessionEpoch: 0));
    final assertion = expectLater(
      pending,
      throwsA(
        isA<ApiFailure>().having(
          (failure) => failure.category,
          'category',
          ApiFailureCategory.cancelled,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    session.sessionEpoch++;
    response.complete(
      _response({
        'data': _config({'tid': 1008, 'name': '旧目录'}),
      }),
    );
    await assertion;
    expect(transport.requests, hasLength(1));
  });
}

final _protocol = isA<ApiFailure>()
    .having(
      (failure) => failure.category,
      'category',
      ApiFailureCategory.protocol,
    )
    .having((failure) => failure.endpointId, 'endpointId', 'ranking_regions');

Map<String, Object?> _config(Map<String, Object?> region) => {
  'channel_list.popular_page_sort': '["game"]',
  'channel_list.game': jsonEncode(region),
};

ApiHttpResponse _response(Object? data, {int code = 0}) => ApiHttpResponse(
  200,
  Uint8List.fromList(utf8.encode(jsonEncode({'code': code, 'data': data}))),
  const {},
);

final class _Session implements ApiSessionProvider {
  @override
  int sessionEpoch = 0;
}

final class _Transport implements ApiTransport {
  _Transport(this.respond);
  final Future<ApiHttpResponse> Function(Uri) respond;
  final List<Uri> requests = [];

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) {
    requests.add(uri);
    return respond(uri);
  }
}
