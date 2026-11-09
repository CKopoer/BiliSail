import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

Map<String, Object?> _comment(String id, {String mid = '7'}) => {
  'rpid_str': id,
  'member': {'mid': mid, 'uname': 'fixture'},
  'content': {'message': 'fixture'},
};

void main() {
  for (final cursorApi in [true, false]) {
    for (final source in [
      'top_replies',
      'upper.top',
      'top.upper',
      'top.admin',
      'top.vote',
    ]) {
      test(
        '${cursorApi ? 'WBI' : 'legacy'} marks and de-duplicates $source',
        () async {
          final pinned = _comment('10');
          final upper = <String, Object?>{'mid': '9007199254740993'};
          final data = _data([
            _comment('10'),
            {
              ..._comment('11'),
              'up_action': {'like': true, 'reply': true},
              'replies': [_comment('12', mid: '9007199254740993')],
            },
          ])..['upper'] = upper;
          switch (source) {
            case 'top_replies':
              data[source] = [pinned];
            case 'upper.top':
              upper['top'] = pinned;
            default:
              data['top'] = {source.split('.').last: pinned};
          }
          final api = BiliApiClient(transport: _Transport(data));
          addTearDown(api.close);
          final result = cursorApi
              ? await api.getVideoCommentsByCursor('42')
              : await api.getVideoComments('42', commentType: 17);
          expect(result.items.map((c) => c.id), ['10', '11']);
          expect(result.items.first.isPinned, isTrue);
          expect(result.items.first.isUpAuthor, isFalse);
          expect(result.items.first.upLiked, isFalse);
          expect(result.items.first.upReplied, isFalse);
          final root = result.items.last;
          expect(root.isPinned, isFalse);
          expect(root.upLiked, isTrue);
          expect(root.upReplied, isTrue);
          final reply = root.replies.single;
          expect(reply.isUpAuthor, isTrue);
          expect(reply.authorMid, '9007199254740993');
          expect(reply.isPinned, isFalse);
          expect(reply.upLiked, isFalse);
          expect(reply.upReplied, isFalse);
        },
      );
    }

    test(
      '${cursorApi ? 'WBI' : 'legacy'} later pages omit pinned copies but retain UP identity',
      () async {
        final data = _data([_comment('11', mid: '9007199254740993')])
          ..['top_replies'] = [_comment('10')]
          ..['upper'] = {'mid': '9007199254740993', 'top': _comment('10')};
        final api = BiliApiClient(transport: _Transport(data));
        addTearDown(api.close);
        final result = cursorApi
            ? await api.getVideoCommentsByCursor('42', cursor: 'next')
            : await api.getVideoComments('42', commentType: 17, page: 2);
        expect(result.items.single.id, '11');
        expect(result.items.single.isPinned, isFalse);
        expect(result.items.single.isUpAuthor, isTrue);
      },
    );
  }

  test(
    'reply pages use their own UP identity and never inject top-level pins',
    () async {
      final api = BiliApiClient(
        transport: _Transport(
          _data([
              {
                ..._comment('12', mid: '9007199254740993'),
                'up_action': {'like': true, 'reply': true},
              },
            ])
            ..['top_replies'] = [_comment('10')]
            ..['upper'] = {'mid': '9007199254740993', 'top': _comment('10')},
        ),
      );
      addTearDown(api.close);
      final result = await api.getVideoReplies('42', '11');
      expect(result.items.single.id, '12');
      expect(result.items.single.isPinned, isFalse);
      expect(result.items.single.isUpAuthor, isTrue);
      expect(result.items.single.upLiked, isTrue);
      expect(result.items.single.upReplied, isTrue);
    },
  );

  test('explicit pin and top-level decimal author IDs are supported', () async {
    final api = BiliApiClient(
      transport: _Transport(
        _data([
          {
            ..._comment('10'),
            'member': {'uname': 'fixture'},
            'mid_str': '9007199254740993',
            'reply_control': {'is_up_top': true},
          },
        ])..['upper'] = {'mid': '9007199254740993'},
      ),
    );
    addTearDown(api.close);
    final value = (await api.getVideoComments('42')).items.single;
    expect(value.isPinned, isTrue);
    expect(value.isUpAuthor, isTrue);
  });

  for (final invalid in [
    null,
    false,
    'true',
    1,
    <String, Object?>{},
    <Object?>[],
  ]) {
    test(
      'invalid optional marker $invalid does not invent UP status',
      () async {
        final api = BiliApiClient(
          transport: _Transport(
            _data([
              {
                ..._comment('10'),
                'up_action': {'like': invalid, 'reply': invalid},
                'reply_control': {'is_up_top': invalid},
              },
              {
                ..._comment('11'),
                'up_action': invalid,
                'reply_control': invalid,
              },
            ])..['upper'] = {'mid': '7.0'},
          ),
        );
        addTearDown(api.close);
        for (final value in (await api.getVideoComments('42')).items) {
          expect(value.isPinned, isFalse);
          expect(value.isUpAuthor, isFalse);
          expect(value.upLiked, isFalse);
          expect(value.upReplied, isFalse);
        }
      },
    );
  }
}

Map<String, Object?> _data(List<Object?> replies) => {
  'replies': replies,
  'page': {'count': 2, 'size': 20},
  'cursor': {'is_end': true, 'all_count': 2},
};

final class _Transport implements ApiTransport {
  _Transport(this.data);
  final Map<String, Object?> data;

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
              : data,
        }),
      ),
    ),
    const {},
  );
}
