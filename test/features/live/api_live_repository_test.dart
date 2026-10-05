import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/live/data/api_live_repository.dart';
import 'package:bilisail/features/live/domain/live_room.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'repository maps profile identity and rich chat without leaking API types',
    () async {
      final requests = ApiRequests();
      final api = BiliApiClient(
        transport: _Transport(),
        sessionProvider: requests,
      );
      addTearDown(api.close);
      final repository = ApiLiveRepository(
        LiveClient(api),
        requests,
        accountScope: () => 'guest',
      );
      final chat = await repository.loadChatHistory(
        const RoomId('12'),
        cancellation: RequestCancellation(),
      );
      expect(chat.first.userId, const UserId('9007199254740993'));
      expect(chat.first.emotes['[笑]']?.url.scheme, 'https');
      expect(chat.first.sticker?.width, 160);
      expect(chat.last.userId, isNull);
      expect(() => chat.first.emotes.clear(), throwsUnsupportedError);
      final sc = await repository.loadSuperChats(
        const RoomId('12'),
        cancellation: RequestCancellation(),
      );
      expect(sc.single.userId, const UserId('9007199254740995'));
    },
  );
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
          'data': uri.path.endsWith('gethistory')
              ? {
                  'room': [
                    {
                      'nickname': '观众甲',
                      'text': '[笑]',
                      'user': {'uid': '9007199254740993'},
                      'emots': {
                        '[笑]': {'url': '//i0.hdslb.com/smile.png'},
                      },
                      'emoticon': {
                        'url': '//i0.hdslb.com/sticker.png',
                        'width': 160,
                        'height': 80,
                      },
                    },
                    {'nickname': '观众乙', 'text': '无UID', 'uid': 0},
                  ],
                }
              : {
                  'list': [
                    {
                      'id': '1',
                      'uid': '9007199254740995',
                      'price': 50,
                      'message': 'SC内容',
                      'user_info': {'uname': '观众丙'},
                    },
                  ],
                },
        }),
      ),
    ),
    const {},
  );
}
