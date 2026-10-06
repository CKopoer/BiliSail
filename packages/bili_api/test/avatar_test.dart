import 'dart:convert';
import 'dart:typed_data';
import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  test('nav and video detail preserve public CDN avatar URLs', () async {
    final api = BiliApiClient(transport: _Transport());
    final nav = await api.getNav();
    expect(nav.avatarUrl.toString(), 'https://i0.hdslb.com/account.jpg');
    final detail = await api.getVideoDetail('BV1234567890');
    expect(
      detail.ownerAvatarUrl.toString(),
      'https://i0.hdslb.com/creator.jpg',
    );
  });
}

final class _Transport implements ApiTransport {
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async => ApiHttpResponse(
    200,
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'code': 0,
          'data': uri.path.endsWith('/nav')
              ? {
                  'isLogin': true,
                  'mid': 1,
                  'uname': '账户',
                  'face': 'http://i0.hdslb.com/account.jpg',
                }
              : {
                  'aid': 42,
                  'bvid': 'BV1234567890',
                  'title': '视频',
                  'desc': '',
                  'owner': {
                    'name': '作者',
                    'face': 'http://i0.hdslb.com/creator.jpg',
                  },
                  'pages': [
                    {'cid': 8, 'page': 1, 'part': 'P1', 'duration': 90},
                  ],
                },
        }),
      ),
    ),
    {},
  );
}
