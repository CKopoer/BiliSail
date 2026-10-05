import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  test(
    'read request has cid, one encoded categories array and no credentials',
    () async {
      final transport = _Transport(200, [_row()]);
      final result = await SponsorBlockClient(
        transport,
      ).segments('BV123', '42', categories: ['sponsor']);
      expect(result.single.start, const Duration(seconds: 10));
      expect(transport.uri?.host, 'bsbsb.top');
      expect(transport.uri?.queryParameters['categories'], '["sponsor"]');
      expect(transport.uri?.queryParameters['cid'], '42');
      expect(
        transport.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('cookie')),
      );
      expect(transport.timeout, const Duration(seconds: 8));
    },
  );
  test(
    '404 is empty, and invalid cid/action/range/category are discarded',
    () async {
      expect(
        await SponsorBlockClient(
          _Transport(404, []),
        ).segments('BV123', '42', categories: ['sponsor']),
        isEmpty,
      );
      final rows = [
        _row(),
        _row()..['cid'] = '43',
        _row()..['actionType'] = 'mute',
        _row()..['segment'] = [20, 10],
        _row()..['category'] = 'intro',
        _row()..['videoDuration'] = 1e308,
      ];
      expect(
        await SponsorBlockClient(
          _Transport(200, rows),
        ).segments('BV123', '42', categories: ['sponsor']),
        hasLength(1),
      );
    },
  );
  test(
    'cancellation and bounded malformed payload remain classified failures',
    () async {
      final token = ApiCancellation()..cancel();
      await expectLater(
        SponsorBlockClient(
          _Transport(200, []),
        ).segments('BV123', '42', categories: ['sponsor'], cancellation: token),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.cancelled,
          ),
        ),
      );
      await expectLater(
        SponsorBlockClient(
          _Transport(200, List.generate(513, (_) => _row())),
        ).segments('BV123', '42', categories: ['sponsor']),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.protocol,
          ),
        ),
      );
    },
  );
}

Map<String, Object?> _row() => {
  'segment': [10, 20],
  'cid': '42',
  'UUID': 'uuid',
  'category': 'sponsor',
  'actionType': 'skip',
  'videoDuration': 120,
};

final class _Transport implements ApiTransport {
  _Transport(this.status, this.payload);
  final int status;
  final Object payload;
  Uri? uri;
  Map<String, String> headers = {};
  Duration? timeout;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    this.uri = uri;
    this.headers = headers;
    this.timeout = timeout;
    return ApiHttpResponse(
      status,
      Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      const {},
    );
  }
}
