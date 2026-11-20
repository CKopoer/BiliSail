import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/article_address.dart';
import 'package:bilisail/domain/comment_target.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/article/data/api_article_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'maps the opus comment target, count and closure into the reader model',
    () async {
      final requests = ApiRequests();
      final transport = _Transport();
      final api = BiliApiClient(
        transport: transport,
        sessionProvider: requests,
      );
      final article = await ApiArticleRepository(ArticleClient(api), requests)
          .read(
            const ArticleAddress(ArticleKind.opus, '99999999999999999999'),
            RequestCancellation(),
          );
      expect(
        article.commentTarget,
        const CommentTarget('456', CommentTargetType.article),
      );
      expect(article.commentCount, 9);
      expect(article.commentForbidden, isTrue);
      expect(transport.calls, [
        '/x/web-interface/nav',
        '/x/polymer/web-dynamic/v1/opus/detail',
      ]);
    },
  );
}

final class _Transport implements ApiTransport {
  final calls = <String>[];

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    calls.add(uri.path);
    final data = switch (uri.path) {
      '/x/web-interface/nav' => {
        'wbi_img': {
          'img_url': 'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
          'sub_url': 'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
        },
      },
      '/x/polymer/web-dynamic/v1/opus/detail' => {
        'item': {
          'id_str': '99999999999999999999',
          'basic': {'comment_id_str': '456', 'comment_type': 12},
          'modules': [
            {
              'module_content': {
                'paragraphs': [
                  {
                    'para_type': 7,
                    'code': {'content': '正文'},
                  },
                ],
              },
            },
            {
              'module_stat': {
                'comment': {'count': 9, 'forbidden': true},
              },
            },
          ],
        },
      },
      _ => throw StateError('Unexpected request to ${uri.path}'),
    };
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
      const {},
    );
  }
}
