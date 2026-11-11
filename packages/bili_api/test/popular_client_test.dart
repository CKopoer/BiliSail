import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  test('weekly directory preserves order and deduplicates periods', () async {
    final api = BiliApiClient(
      transport: _Transport((uri) async {
        expect(uri.path, '/x/web-interface/popular/series/list');
        expect(uri.queryParameters['web_location'], '333.934');
        expect(uri.queryParameters['w_rid'], hasLength(32));
        return _response({
          'list': [
            {'number': 396, 'name': '第396期', 'subject': '本周主题'},
            {'number': 395, 'name': '第395期'},
            {'number': 396, 'name': '重复'},
          ],
        });
      }),
    );
    final weeks = await api.getPopularWeeks();
    expect(weeks.map((week) => week.number), [396, 395]);
    expect(weeks.first.subject, '本周主题');
    expect(weeks.last.subject, '');
    expect(() => weeks.clear(), throwsUnsupportedError);
  });

  for (final invalid in [
    {'name': '缺少期数'},
    {'number': 0, 'name': '非法期数'},
    {'number': -1, 'name': '非法期数'},
    {'number': 1},
  ]) {
    test('rejects malformed weekly entry $invalid', () async {
      final api = BiliApiClient(
        transport: _Transport(
          (_) async => _response({
            'list': [invalid],
          }),
        ),
      );
      await expectLater(
        api.getPopularWeeks(),
        throwsA(_failure(ApiFailureCategory.protocol)),
      );
    });
  }

  test(
    'weekly and precious use separate single-list endpoints and standard mapping',
    () async {
      final requests = <Uri>[];
      final api = BiliApiClient(
        transport: _Transport((uri) async {
          requests.add(uri);
          return _response({
            'list': [_video],
            'no_more': false,
          });
        }),
      );
      final week = await api.getPopularWeek(number: 396);
      final precious = await api.getPreciousVideos();
      expect(requests.first.path, '/x/web-interface/popular/series/one');
      expect(requests.first.queryParameters['number'], '396');
      expect(requests.first.queryParameters['w_rid'], hasLength(32));
      expect(requests.last.path, '/x/web-interface/popular/precious');
      expect(requests.last.queryParameters['page_size'], '100');
      expect(requests.last.queryParameters['page'], '1');
      expect(requests.last.queryParameters['w_rid'], hasLength(32));
      for (final page in [week, precious]) {
        expect(page.hasMore, isFalse);
        expect(page.items.single.bvid, 'BV1234567890');
        expect(page.items.single.ownerMid, '9007199254740993');
        expect(page.items.single.recommendationReason, '本期推荐');
        expect(page.items.single.duration, const Duration(seconds: 123));
      }
    },
  );

  test(
    '-352 remains a single business failure without fallback or replay',
    () async {
      var calls = 0;
      final api = BiliApiClient(
        transport: _Transport((uri) async {
          calls++;
          expect(uri.path, '/x/web-interface/popular/series/one');
          return _response(null, code: -352);
        }),
      );
      await expectLater(
        api.getPopularWeek(number: 396),
        throwsA(_failure(ApiFailureCategory.rateLimited)),
      );
      expect(calls, 1);
    },
  );

  test('directory and single-list payloads enforce capacity', () async {
    final api = BiliApiClient(
      transport: _Transport(
        (uri) async => _response({
          'list': List.filled(uri.path.endsWith('/list') ? 1025 : 501, _video),
        }),
      ),
    );
    await expectLater(
      api.getPopularWeeks(),
      throwsA(_failure(ApiFailureCategory.protocol)),
    );
    await expectLater(
      api.getPreciousVideos(),
      throwsA(_failure(ApiFailureCategory.protocol)),
    );
  });

  test('old account response is discarded', () async {
    final session = _Session();
    final pending = Completer<ApiHttpResponse>();
    final api = BiliApiClient(
      sessionProvider: session,
      transport: _Transport((_) => pending.future),
    );
    final assertion = expectLater(
      api.getPopularWeek(number: 396),
      throwsA(_failure(ApiFailureCategory.cancelled)),
    );
    await Future<void>.delayed(Duration.zero);
    session.sessionEpoch++;
    pending.complete(
      _response({
        'list': [_video],
      }),
    );
    await assertion;
  });
}

Matcher _failure(ApiFailureCategory category) =>
    isA<ApiFailure>().having((error) => error.category, 'category', category);

const _video = {
  'bvid': 'BV1234567890',
  'title': '虚构视频',
  'duration': 123,
  'pic': 'https://i0.hdslb.com/test.jpg',
  'owner': {'mid': '9007199254740993', 'name': '作者'},
  'stat': {'view': 15000, 'danmaku': 42},
  'rcmd_reason': '本期推荐',
};

ApiHttpResponse _response(Object? data, {int code = 0}) => ApiHttpResponse(
  200,
  Uint8List.fromList(utf8.encode(jsonEncode({'code': code, 'data': data}))),
  const {},
);

class _Session implements ApiSessionProvider {
  @override
  int sessionEpoch = 0;
}

class _Transport implements ApiTransport {
  _Transport(this.respond);
  final Future<ApiHttpResponse> Function(Uri) respond;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    if (uri.path == '/x/web-interface/nav') {
      return _response({
        'wbi_img': {
          'img_url':
              'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
          'sub_url':
              'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
        },
      });
    }
    expect(headers['User-Agent'], startsWith('Mozilla/5.0'));
    expect(headers['Origin'], 'https://www.bilibili.com');
    expect(headers['Referer'], contains('/v/popular/'));
    return respond(uri);
  }
}
