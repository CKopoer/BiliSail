import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/messages/data/api_message_repository.dart';
import 'package:bilisail/features/messages/domain/message_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'rich message data crosses the repository boundary without losing actions',
    () async {
      final transport = _Transport({
        'messages': [
          _message('1', 10, {
            'title': '创作通知',
            'text': '审核完成',
            'modules': [
              {'title': '作品', 'detail': '旅行记录'},
            ],
            'jump_text': '查看作品',
            'jump_uri': 'https://www.bilibili.com/video/BV17x411w7KC',
          }),
          _message('2', 16, {
            'main_title': '精选推荐',
            'sub_cards': [
              {
                'field1': '秋日漫步',
                'field2': '风景影像',
                'cover_url': 'https://i0.hdslb.com/bfs/archive/fixture.jpg',
                'jump_url': 'https://www.bilibili.com/video/BV17x411w7KC',
              },
            ],
          }),
        ],
        'has_more': 0,
      });
      final requests = ApiRequests();
      final repository = ApiMessageRepository(
        MessageClient(
          BiliApiClient(transport: transport, sessionProvider: requests),
        ),
        requests,
        accountScope: () => 'user:1',
      );
      final page = await repository.thread(
        const InboxEntry(
          id: '1:2',
          title: '会话',
          text: '',
          userId: UserId('2'),
          sessionType: 1,
        ),
        cancellation: RequestCancellation(),
      );
      expect(page.items.first.kind, MessageContentKind.notification);
      expect(page.items.first.title, '创作通知');
      expect(page.items.first.details.single.label, '作品');
      expect(page.items.first.details.single.value, '旅行记录');
      expect(page.items.first.links.single.label, '查看作品');
      expect(page.items.first.links.single.url.path, '/video/BV17x411w7KC');
      expect(page.items.last.kind, MessageContentKind.autoReply);
      expect(page.items.last.cards.single.title, '秋日漫步');
      expect(page.items.last.cards.single.imageUrl?.host, 'i0.hdslb.com');
      expect(
        page.items.last.cards.single.targetUrl?.path,
        '/video/BV17x411w7KC',
      );
      expect(() => page.items.clear(), throwsUnsupportedError);
      expect(() => page.items.last.cards.clear(), throwsUnsupportedError);
    },
  );
}

Map<String, Object?> _message(String sequence, int type, Object content) => {
  'sender_uid': '2',
  'msg_seqno': sequence,
  'msg_key': sequence,
  'msg_type': type,
  'msg_status': 0,
  'content': jsonEncode(content),
};

final class _Transport implements ApiTransport {
  _Transport(this.data);
  final Object data;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async => ApiHttpResponse(
    200,
    Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
    const {},
  );
}
