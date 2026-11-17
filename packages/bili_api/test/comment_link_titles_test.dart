import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  for (final cursor in [false, true]) {
    test(
      '${cursor ? 'WBI' : 'legacy'} retains bounded link titles in replies',
      () async {
        Map<String, Object?> comment(String id) => {
          'rpid_str': id,
          'member': {'uname': 'fixture'},
          'content': {
            'message': 'BV117BkBsEWw',
            'jump_url': {
              'BV117BkBsEWw': {
                'title': '  视频 &amp; 标题  ',
                'prefix_icon': 'unused',
              },
              'bad': false,
              'badTitle': {'title': 42},
              'empty': {'title': '  '},
              'oversize': {'title': 'x' * 301},
              'x' * 2049: {'title': 'too long key'},
            },
          },
        };
        final root = comment('1')..['replies'] = [comment('2')];
        final api = BiliApiClient(transport: _Transport(root));
        addTearDown(api.close);
        final page = cursor
            ? await api.getVideoCommentsByCursor('42')
            : await api.getVideoComments('42', commentType: 17);
        for (final entry in [
          page.items.single,
          page.items.single.replies.single,
        ]) {
          expect(entry.linkTitles, {'BV117BkBsEWw': '视频 &amp; 标题'});
          expect(() => entry.linkTitles.clear(), throwsUnsupportedError);
        }
      },
    );
  }

  for (final malformed in [null, false, 'invalid', <Object?>[]]) {
    test(
      'malformed optional jump_url $malformed does not discard comments',
      () async {
        final api = BiliApiClient(
          transport: _Transport({
            'rpid_str': '1',
            'member': {'uname': 'fixture'},
            'content': {'message': 'plain text', 'jump_url': malformed},
          }),
        );
        addTearDown(api.close);
        final page = await api.getVideoComments('42', commentType: 17);
        expect(page.items.single.message, 'plain text');
        expect(page.items.single.linkTitles, isEmpty);
      },
    );
  }

  test('retains at most 100 link titles per comment', () async {
    final api = BiliApiClient(
      transport: _Transport({
        'rpid_str': '1',
        'member': {'uname': 'fixture'},
        'content': {
          'message': 'fixture',
          'jump_url': {
            for (var i = 1; i <= 101; i++) 'av$i': {'title': '视频$i'},
          },
        },
      }),
    );
    addTearDown(api.close);
    final page = await api.getVideoComments('42', commentType: 17);
    expect(page.items.single.linkTitles, hasLength(100));
    expect(page.items.single.linkTitles['av100'], '视频100');
    expect(page.items.single.linkTitles.containsKey('av101'), isFalse);
  });
}

final class _Transport implements ApiTransport {
  _Transport(this.comment);
  final Map<String, Object?> comment;

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
                  'wbi_img': {
                    'img_url':
                        'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
                    'sub_url':
                        'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
                  },
                }
              : {
                  'page': {'count': 1, 'size': 20},
                  'cursor': {'is_end': true, 'all_count': 1},
                  'replies': [comment],
                },
        }),
      ),
    ),
    const {},
  );
}
