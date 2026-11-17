import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/comments/domain/comment_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const bv = 'BV117BkBsEWw';
  test('recognizes IDs, web, mobile, schemeless and app video references', () {
    const message =
        '看看$bv，av170001；bv117BkBsEWw AV170001\n'
        'https://www.bilibili.com/video/$bv?p=2&amp;t=00:09。'
        'm.bilibili.com/video/$bv.html '
        '//www.bilibili.com/video/av170001 '
        'bilibili.com/video/$bv '
        'bilibili://video/170001 '
        'https://b23.tv/$bv b23.tv/av170001';
    final parts = parseCommentText(message);
    expect(
      parts.map((part) => part.text).join(),
      decodeCommentEntities(message),
    );
    final videos = parts.where(
      (part) => part.kind == CommentTextKind.videoLink,
    );
    expect(videos, hasLength(11));
    expect(videos.every((part) => part.url?.scheme == 'https'), isTrue);
    expect(videos.first.url.toString(), 'https://www.bilibili.com/video/$bv');
    expect(parts.where((part) => part.position != null), isEmpty);
    expect(videos.elementAt(4).url?.queryParameters, {'p': '2', 't': '00:09'});
  });

  test(
    'keeps whole URLs, unknown schemes, lookalike hosts and IDs separate',
    () {
      const message =
          'x$bv ${bv}x /$bv @$bv _av170001 av0 av12evil '
          'https://example.com/video/$bv https://b23.tv.evil/$bv '
          'www.bilibili.com.evil/video/$bv evil.bilibili.com/video/$bv '
          'ftp://b23.tv/$bv file:///$bv '
          'https://user:secret@www.bilibili.com/video/$bv '
          'bilibili://video/0 https://www.bilibili.com/video/${bv}x';
      final parts = parseCommentText(message);
      expect(parts.map((part) => part.text).join(), message);
      expect(
        parts.where((part) => part.kind == CommentTextKind.videoLink),
        isEmpty,
      );
      expect(parts.where((part) => part.url?.scheme == 'bilibili'), isEmpty);
    },
  );

  test(
    'server titles decorate recognized targets while preserving raw text',
    () {
      const message = '$bv $bv b23.tv/token https://example.com/x av170001';
      final parts = parseCommentText(
        message,
        linkTitles: const {
          bv: '  视频 &amp; 标题  ',
          'b23.tv/token': '分享的链接',
          'https://example.com/x': '伪装成视频',
          'av170001': '  ',
        },
      );
      expect(parts.map((part) => part.text).join(), message);
      expect(
        parts
            .where((part) => part.linkTitle != null)
            .map((part) => part.linkTitle),
        ['视频 & 标题', '视频 & 标题', '分享的链接'],
      );
      expect(parts.where((part) => part.url != null), hasLength(5));
      expect(
        parts.where((part) => part.kind == CommentTextKind.videoLink),
        hasLength(3),
      );
      expect(
        parts.where((part) => part.text == 'b23.tv/token').single.kind,
        CommentTextKind.link,
      );
    },
  );

  test('emotes and server mentions own their tokens beside video IDs', () {
    const message = '[$bv] @$bv $bv 00:09';
    final parts = parseCommentText(
      message,
      emoteTokens: const ['[$bv]'],
      mentionedUsers: const {bv: UserId('42')},
    );
    expect(parts.map((part) => part.text).join(), message);
    expect(
      parts.where((part) => part.kind == CommentTextKind.emote),
      hasLength(1),
    );
    expect(parts.where((part) => part.userId != null), hasLength(1));
    expect(
      parts.where((part) => part.kind == CommentTextKind.videoLink),
      hasLength(1),
    );
    expect(parts.where((part) => part.position != null), hasLength(1));
  });
}
