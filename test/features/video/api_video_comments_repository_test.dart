import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/comments/data/api_comments_repository.dart';
import 'package:bilisail/features/video/domain/video_comments_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'repository retains locations and mentions in comments and nested replies',
    () async {
      final requests = ApiRequests();
      final transport = _Transport();
      final api = BiliApiClient(
        transport: transport,
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
        for (final entry in [
          root,
          root.withLike(true),
          root.withReplies(root.replies),
        ]) {
          expect(
            entry.pendantUrl.toString(),
            'https://i0.hdslb.com/pendant.webp',
          );
          expect(entry.isPinned, isTrue);
          expect(entry.isUpAuthor, isFalse);
          expect(entry.upLiked, isTrue);
          expect(entry.upReplied, isTrue);
          expect(entry.replies.single.isUpAuthor, isTrue);
          expect(entry.replies.single.isPinned, isFalse);
        }
        for (final entry in [
          root.replies.single.withLike(true),
          root.replies.single.withReplies(const []),
        ]) {
          expect(entry.isUpAuthor, isTrue);
          expect(entry.isPinned, isFalse);
          expect(entry.upLiked, isFalse);
          expect(entry.upReplied, isFalse);
        }
        expect(root.nicknameColor, 0xfb7299);
        expect(root.withLike(true).nicknameColor, 0xfb7299);
        expect(root.withReplies(root.replies).nicknameColor, 0xfb7299);
        expect(root.replies.single.nicknameColor, 0x123456);
        expect(root.replies.single.withLike(true).nicknameColor, 0x123456);
        expect(root.visibility, CommentVisibility.restricted);
        expect(root.withLike(true).visibility, CommentVisibility.restricted);
        expect(
          root.withReplies(root.replies).visibility,
          CommentVisibility.restricted,
        );
        expect(root.replies.single.visibility, CommentVisibility.normal);
        expect(root.replies.single.ipLocation, 'IP属地：上海');
        expect(root.mentionedUsers, {
          'reader': const UserId('9007199254740993'),
        });
        expect(root.replies.single.mentionedUsers, {
          'reader': const UserId('100'),
        });
        expect(root.withLike(true).mentionedUsers, root.mentionedUsers);
        expect(
          root.withReplies(root.replies).mentionedUsers,
          root.mentionedUsers,
        );
        expect(
          root.replies.single.withLike(true).mentionedUsers,
          root.replies.single.mentionedUsers,
        );
        expect(() => root.mentionedUsers.clear(), throwsUnsupportedError);
        expect(root.withLike(true).ipLocation, 'IP属地：广东');
        expect(
          root.withReplies(root.replies).replies.single.ipLocation,
          'IP属地：上海',
        );
      }
      expect(transport.requests[1].path, '/x/v2/reply/wbi/main');
      expect(transport.requests.last.path, '/x/v2/reply/reply');
    },
  );
}

final class _Transport implements ApiTransport {
  final requests = <Uri>[];
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    requests.add(uri);
    return ApiHttpResponse(
      200,
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'code': 0,
            'data': uri.path.endsWith('/nav')
                ? {
                    'wbi_img': {
                      'img_url': 'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
                      'sub_url': 'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
                    },
                  }
                : {
                    'cursor': {'is_end': true, 'all_count': 1},
                    'page': {'count': 1, 'size': 20},
                    'upper': {'mid': '9007199254740993'},
                    'replies': [
                      {
                        'rpid': '10',
                        'state': 17,
                        'up_action': {'like': true, 'reply': true},
                        'member': {
                          'uname': 'reader',
                          'pendant': {
                            'image_enhance': '//i0.hdslb.com/pendant.webp',
                          },
                          'vip': {'nickname_color': '#fb7299'},
                        },
                        'content': {
                          'message': 'comment',
                          'at_name_to_mid_str': {'reader': '9007199254740993'},
                        },
                        'reply_control': {
                          'location': 'IP属地：广东',
                          'is_up_top': true,
                        },
                        'replies': [
                          {
                            'rpid': '11',
                            'state': 0,
                            'member': {
                              'uname': 'reply author',
                              'mid': '9007199254740993',
                              'vip': {'nickname_color': '#123456'},
                            },
                            'content': {
                              'message': 'reply',
                              'members': [
                                {'uname': 'reader', 'mid': '100'},
                              ],
                            },
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
}
