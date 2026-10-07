import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/comments/data/api_comments_repository.dart';
import 'package:bilisail/features/video/domain/video_comments_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'repository retains IP locations in comments and nested replies',
    () async {
      final requests = ApiRequests();
      final api = BiliApiClient(
        transport: _Transport(),
        sessionProvider: requests,
      );
      addTearDown(api.close);
      final repository = ApiCommentsRepository(
        api,
        requests,
        accountScope: () => 'guest',
      );
      for (final page in [
        await repository.load('42', 1, CommentSort.hot, RequestCancellation()),
        await repository.replies('42', '10', 1, RequestCancellation()),
      ]) {
        final root = page.items.single;
        expect(root.ipLocation, 'IP属地：广东');
        expect(root.replies.single.ipLocation, 'IP属地：上海');
        expect(root.withLike(true).ipLocation, 'IP属地：广东');
        expect(
          root.withReplies(root.replies).replies.single.ipLocation,
          'IP属地：上海',
        );
      }
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
          'data': {
            'page': {'count': 1, 'size': 20},
            'replies': [
              {
                'rpid': '10',
                'member': {'uname': 'reader'},
                'content': {'message': 'comment'},
                'reply_control': {'location': 'IP属地：广东'},
                'replies': [
                  {
                    'rpid': '11',
                    'member': {'uname': 'reply author'},
                    'content': {'message': 'reply'},
                    'reply_control': {'location': 'IP属地：上海'},
                  },
                ],
              },
            ],
          },
        }),
      ),
    ),
    const {},
  );
}
