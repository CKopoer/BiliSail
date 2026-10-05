import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

final class _Transport implements ApiTransport {
  _Transport(this.reply);

  final Object? Function(Uri) reply;
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
      Uint8List.fromList(utf8.encode(jsonEncode(reply(uri)))),
      const {},
    );
  }
}

void main() {
  test('guest Web GET decodes SC fields without App signing', () async {
    final transport = _Transport(
      (_) => {
        'code': 0,
        'data': {
          'list': [
            {
              'id': '9007199254740993',
              'uid': '9007199254740995',
              'message': '脱敏醒目留言',
              'price': 50,
              'start_time': 1791180000,
              'end_time': 1791180060,
              'background_color': '#336699',
              'background_bottom_color': '#AA112233',
              'font_color': '#FFFFFF',
              'user_info': {'uname': '测试观众', 'face': '//i0.hdslb.com/test.jpg'},
            },
          ],
        },
      },
    );
    final result = await LiveClient(
      BiliApiClient(transport: transport),
    ).getSuperChats('7734200');

    expect(transport.requested?.host, 'api.live.bilibili.com');
    expect(transport.requested?.path, '/av/v1/SuperChat/getMessageList');
    expect(transport.requested?.queryParameters, {'room_id': '7734200'});
    expect(result.single.id, '9007199254740993');
    expect(result.single.userId, '9007199254740995');
    expect(result.single.userName, '测试观众');
    expect(result.single.text, '脱敏醒目留言');
    expect(result.single.price, 50);
    expect(result.single.avatarUrl?.scheme, 'https');
    expect(
      result.single.startedAt,
      DateTime.fromMillisecondsSinceEpoch(1791180000 * 1000, isUtc: true),
    );
    expect(
      result.single.expiresAt,
      DateTime.fromMillisecondsSinceEpoch(1791180060 * 1000, isUtc: true),
    );
    expect(result.single.backgroundColor, 0xff336699);
    expect(result.single.backgroundBottomColor, 0xaa112233);
    expect(result.single.textColor, 0xffffffff);
  });

  test('null list is empty, list is bounded, malformed item fails', () async {
    final empty = LiveClient(
      BiliApiClient(
        transport: _Transport(
          (_) => {
            'code': 0,
            'data': {'list': null},
          },
        ),
      ),
    );
    expect(await empty.getSuperChats('6'), isEmpty);

    final bounded = LiveClient(
      BiliApiClient(
        transport: _Transport(
          (_) => {
            'code': 0,
            'data': {
              'list': List.generate(
                120,
                (index) => {
                  'id': index + 1,
                  'message': 'fixture',
                  'price': 30,
                  'user_info': {'uname': '观众'},
                },
              ),
            },
          },
        ),
      ),
    );
    expect(await bounded.getSuperChats('6'), hasLength(100));

    final malformed = LiveClient(
      BiliApiClient(
        transport: _Transport(
          (_) => {
            'code': 0,
            'data': {
              'list': [
                {
                  'id': 1,
                  'message': '缺价格',
                  'user_info': {'uname': '观众'},
                },
              ],
            },
          },
        ),
      ),
    );
    await expectLater(
      malformed.getSuperChats('6'),
      throwsA(
        isA<ApiFailure>().having(
          (error) => error.category,
          'category',
          ApiFailureCategory.protocol,
        ),
      ),
    );
    expect(() => empty.getSuperChats('6&extra=1'), throwsArgumentError);
  });
}
