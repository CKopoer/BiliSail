import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Web detail preserves staff order, exact IDs and role presentation',
    () async {
      final detail = await _client([
        {
          'mid': 42,
          'name': 'Owner',
          'title': 'UP主',
          'face': 'http://i0.hdslb.com/owner.jpg',
          'vip': {'nickname_color': '#FB7299'},
        },
        {
          'mid': '9007199254740993',
          'name': 'Sponsor',
          'title': '赞助商',
          'label_style': 1,
        },
        {'mid': 43, 'name': 'Performer', 'title': '参演'},
      ]).getVideoDetail('BV1234567890');
      expect(detail.staff.map((m) => m.name), [
        'Owner',
        'Sponsor',
        'Performer',
      ]);
      expect(detail.staff.map((m) => m.mid), ['42', '9007199254740993', '43']);
      expect(detail.staff.map((m) => m.title), ['UP主', '赞助商', '参演']);
      expect(detail.staff.first.avatarUrl?.scheme, 'https');
      expect(detail.staff.first.nicknameColor, '#FB7299');
      expect(detail.staff[1].highlightedRole, true);
      expect(detail.staff.last.highlightedRole, false);
      expect(() => detail.staff.clear(), throwsUnsupportedError);
    },
  );

  test('missing or null staff keeps ordinary videos unchanged', () async {
    for (final omitted in [true, false]) {
      expect(
        (await _client(
          null,
          omit: omitted,
        ).getVideoDetail('BV1234567890')).staff,
        isEmpty,
      );
    }
  });

  test('invalid user IDs cannot become another creator identity', () async {
    final detail = await _client([
      for (final mid in <Object?>[null, 42.5, '0', '-1', '42.0', '42&fid=43'])
        {'mid': mid, 'name': 'Credit', 'title': '协作'},
      {'mid': 43},
    ]).getVideoDetail('BV1234567890');
    expect(detail.staff.take(6).map((m) => m.mid), everyElement(isNull));
    expect(detail.staff.last.mid, '43');
    expect(detail.staff.last.name, '');
    expect(detail.staff.last.title, '');
  });

  test('staff has a bounded capacity', () async {
    final detail = await _client([
      for (var i = 1; i <= 120; i++) {'mid': i, 'name': 'Creator $i'},
    ]).getVideoDetail('BV1234567890');
    expect(detail.staff, hasLength(100));
    expect(detail.staff.last.mid, '100');
  });

  test('malformed staff structure is a protocol failure', () async {
    for (final staff in <Object>[
      {},
      [null],
    ]) {
      await expectLater(
        _client(staff).getVideoDetail('BV1234567890'),
        throwsA(isA<ApiFailure>()),
      );
    }
  });
}

BiliApiClient _client(Object? staff, {bool omit = false}) => BiliApiClient(
  transport: _Transport({
    'code': 0,
    'data': {
      'aid': 1,
      'bvid': 'BV1234567890',
      'title': 'Collaboration',
      'owner': {'mid': 42, 'name': 'Owner'},
      'pages': [
        {'cid': 1, 'page': 1, 'part': 'P1'},
      ],
      if (!omit) 'staff': staff,
    },
  }),
);

final class _Transport implements ApiTransport {
  _Transport(this.response);
  final Object response;

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    expect(uri.path, '/x/web-interface/view');
    expect(uri.queryParameters, {'bvid': 'BV1234567890'});
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode(response))),
      const {},
    );
  }
}
