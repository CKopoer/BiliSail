import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  test(
    'viewer snapshot uses exact onlineNum without display/rank/popularity',
    () async {
      final transport = _Transport({
        'onlineNum': 19357,
        'onlineNumText': '1万+',
        'count': 1,
        'online': 9999,
      });
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      expect(await LiveClient(api).getViewerCount('545068', '8739477'), 19357);
      expect(transport.requested?.host, 'api.live.bilibili.com');
      expect(
        transport.requested?.path,
        '/xlive/general-interface/v1/rank/getOnlineGoldRank',
      );
      expect(transport.requested?.queryParameters, {
        'roomId': '545068',
        'ruid': '8739477',
        'page': '1',
        'pageSize': '1',
      });
    },
  );

  test(
    'zero and decimal text are valid, malformed exact counts fail',
    () async {
      for (final (input, expected) in [(0, 0), ('19000', 19000)]) {
        final api = BiliApiClient(transport: _Transport({'onlineNum': input}));
        addTearDown(api.close);
        expect(await LiveClient(api).getViewerCount('1', '2'), expected);
      }
      for (final input in [null, -1, 1.2, '1万+', 'bad']) {
        final api = BiliApiClient(transport: _Transport({'onlineNum': input}));
        addTearDown(api.close);
        await expectLater(
          LiveClient(api).getViewerCount('1', '2'),
          throwsA(
            isA<ApiFailure>().having(
              (error) => error.category,
              'category',
              ApiFailureCategory.protocol,
            ),
          ),
        );
      }
    },
  );

  test('invalid room/anchor ID does not send a request', () async {
    final transport = _Transport({'onlineNum': 0});
    final api = BiliApiClient(transport: transport);
    addTearDown(api.close);
    for (final (room, anchor) in [('0', '2'), ('1', 'bad')]) {
      await expectLater(
        LiveClient(api).getViewerCount(room, anchor),
        throwsArgumentError,
      );
    }
    expect(transport.requested, isNull);
  });

  test(
    'WS lower-bound text preserves plus and prefers an exact large integer',
    () {
      final events = LivePacketCodec.decode(
        Uint8List.fromList([
          for (final data in [
            {'online_count': 9999, 'online_count_text': '9999+'},
            {'online_count': 19354, 'online_count_text': '1万+'},
            {'online_count': 19400, 'online_count_text': '9999'},
            {'online_count': 19000, 'online_count_text': '2万+'},
            {'online_count_text': '1万+'},
            {'online_count': 0, 'online_count_text': 'bad'},
          ])
            ...LivePacketCodec.encode(
              5,
              utf8.encode(
                jsonEncode({'cmd': 'ONLINE_RANK_COUNT', 'data': data}),
              ),
            ),
        ]),
      ).events;
      expect(
        events.whereType<ApiLiveViewerCountChanged>().map((e) => e.countText),
        ['9999+', '19354', '19400', '2万+', '1万+', '0'],
      );
    },
  );
}

final class _Transport implements ApiTransport {
  _Transport(this.data);
  final Map<String, Object?> data;
  Uri? requested;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    requested = uri;
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
      const {},
    );
  }
}
