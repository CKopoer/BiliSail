import 'package:bilisail/features/video/domain/comment_text.dart';
import 'package:bilisail/domain/user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'server-backed mentions match full names and preserve surrounding text',
    () {
      const message = '回复 @小迷糊陈 :看了 @名字.+ [笑] @名字 00:09 @A&amp;B';
      final parts = parseCommentText(
        message,
        mentionedUsers: const {
          '小迷糊陈': UserId('100'),
          '名字': UserId('101'),
          '名字.+': UserId('102'),
          'A&B': UserId('9007199254740993'),
        },
        emoteTokens: ['[笑]'],
      );
      expect(
        parts.map((part) => part.text).join(),
        decodeCommentEntities(message),
      );
      expect(
        parts
            .where((part) => part.userId != null)
            .map((part) => (part.text, part.userId)),
        [
          ('@小迷糊陈', const UserId('100')),
          ('@名字.+', const UserId('102')),
          ('@名字', const UserId('101')),
          ('@A&B', const UserId('9007199254740993')),
        ],
      );
      expect(
        parts.where((part) => part.kind == CommentTextKind.emote),
        hasLength(1),
      );
      expect(parts.where((part) => part.position != null), hasLength(1));
    },
  );

  test('unknown, invalid, email and partial names stay plain text', () {
    final parts = parseCommentText(
      '@未知 @无效 @名字更长 @名字abc email@名字 @名字',
      mentionedUsers: const {'无效': UserId('0'), '名字': UserId('100')},
    );
    expect(
      parts.where((part) => part.userId != null).map((part) => part.text),
      ['@名字'],
    );
  });

  test('whole URLs retain ownership of mention-like path and query text', () {
    final parts = parseCommentText(
      'https://example.com/@名字?q=@名字 @名字',
      mentionedUsers: const {'名字': UserId('100')},
    );
    expect(
      parts.where((part) => part.url != null).single.text,
      'https://example.com/@名字?q=@名字',
    );
    expect(parts.where((part) => part.userId != null).single.text, '@名字');
  });

  test('decodes the reported arrows without changing line breaks', () {
    const message = '30tps -&gt; 50tps没有\n20tps -&gt; 30tps倒是差不多，看起来也确实是提升50%';
    expect(
      parseCommentText(message).map((p) => p.text).join(),
      '30tps -> 50tps没有\n20tps -> 30tps倒是差不多，看起来也确实是提升50%',
    );
  });

  test('entities decode once and encoded markup remains literal', () {
    expect(
      decodeCommentEntities(
        '&amp;gt; &lt;b&gt; &quot; &apos; &nbsp; &#62; &#x1F600; &#X3E;',
      ),
      '&gt; <b> " \' \u00a0 > 😀 >',
    );
    expect(
      decodeCommentEntities('&#0; &#xD800; &#1114112; &unknown; &#no;'),
      '&#0; &#xD800; &#1114112; &unknown; &#no;',
    );
  });

  test('recognizes the reported URL and all three timestamps', () {
    const message =
        '相关链接和文字版请看：https://daily.juya.uk/issues/2026-10-06/\n'
        '00:09  OpenAI 宣布提速 GPT-6 Astra 和 GPT-6.1 Sol\n'
        '00:34  Reflection 介绍 501B 开放模型 Beam\n'
        '00:52  Reka AI 发布全能模型 Rho-1 研究预览';
    final parts = parseCommentText(message);
    expect(parts.map((p) => p.text).join(), message);
    expect(
      parts.where((p) => p.url != null).single.url,
      Uri.parse('https://daily.juya.uk/issues/2026-10-06/'),
    );
    expect(parts.where((p) => p.position != null).map((p) => p.position), [
      const Duration(seconds: 9),
      const Duration(seconds: 34),
      const Duration(seconds: 52),
    ]);
  });

  test('supports minutes and hours without matching partial invalid times', () {
    final parts = parseCommentText(
      '0:09 123:45 1:02:03 00:00 12:60 1:99:09 1:02:99 12345:09 a00:09 00:09z 12:34:56:78',
    );
    expect(parts.where((p) => p.position != null).map((p) => p.text), [
      '0:09',
      '123:45',
      '1:02:03',
      '00:00',
    ]);
    expect(parts.where((p) => p.position != null).map((p) => p.position), [
      const Duration(seconds: 9),
      const Duration(minutes: 123, seconds: 45),
      const Duration(hours: 1, minutes: 2, seconds: 3),
      Duration.zero,
    ]);
  });

  test(
    'URLs own their query timestamps and decode escaped query separators',
    () {
      final parts = parseCommentText(
        'https://example.com/00:09?t=00:34&amp;p=1 00:52',
      );
      expect(
        parts.where((p) => p.url != null).single.text,
        'https://example.com/00:09?t=00:34&p=1',
      );
      expect(
        parts.where((p) => p.position != null).single.position,
        const Duration(seconds: 52),
      );
    },
  );

  test('keeps punctuation outside links and balanced path brackets inside', () {
    const message =
        '(https://example.com/a(b)), http://example.com/end。下一句：HTTPS://example.com/x! （https://example.com/last）';
    final parts = parseCommentText(message);
    expect(parts.map((p) => p.text).join(), message);
    expect(parts.where((p) => p.url != null).map((p) => p.text), [
      'https://example.com/a(b)',
      'http://example.com/end',
      'HTTPS://example.com/x',
      'https://example.com/last',
    ]);
  });

  test('preserves emotes beside links and timecodes, including literal regex tokens', () {
    const message = '[笑]00:09[笑哭] https://example.com [a+b] [A+B]';
    final parts = parseCommentText(
      message,
      emoteTokens: ['', '[笑]', '[笑哭]', '[a+b]'],
    );
    expect(parts.map((p) => p.text).join(), message);
    expect(
      parts.where((p) => p.kind == CommentTextKind.emote).map((p) => p.text),
      ['[笑]', '[笑哭]', '[a+b]'],
    );
    expect(
      parts.where((p) => p.position != null).single.position,
      const Duration(seconds: 9),
    );
  });

  test('malformed and credential-bearing URLs remain noninteractive text', () {
    const message =
        'https:// https:///path https://user:secret@example.com/x javascript:alert(1) file:///tmp/x';
    final parts = parseCommentText(message);
    expect(parts.map((p) => p.text).join(), message);
    expect(parts.where((p) => p.url != null), isEmpty);
  });
}
