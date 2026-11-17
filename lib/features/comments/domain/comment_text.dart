import '../../../domain/user.dart';
import 'comment_video_link.dart';

enum CommentTextKind { plain, emote, link, videoLink, timestamp, mention }

final class CommentTextPart {
  const CommentTextPart(
    this.text,
    this.kind, {
    this.url,
    this.position,
    this.userId,
    this.linkTitle,
  });

  final String text;
  final CommentTextKind kind;
  final Uri? url;
  final Duration? position;
  final UserId? userId;
  final String? linkTitle;
}

/// Decode once for display; the original comment remains available unchanged.
/// Encoded markup stays literal text and is never interpreted as HTML.
String decodeCommentEntities(String text) => text.replaceAllMapped(
  RegExp(r'&(#(?:[xX][0-9a-fA-F]+|[0-9]+)|amp|lt|gt|quot|apos|nbsp);'),
  (match) {
    final entity = match[1] ?? '';
    if (entity.startsWith('#')) {
      final hex = entity.startsWith('#x') || entity.startsWith('#X');
      final code = int.tryParse(
        entity.substring(hex ? 2 : 1),
        radix: hex ? 16 : 10,
      );
      if (code != null &&
          code > 0 &&
          code <= 0x10ffff &&
          !(code >= 0xd800 && code <= 0xdfff)) {
        return String.fromCharCode(code);
      }
    }
    return const {
          'amp': '&',
          'lt': '<',
          'gt': '>',
          'quot': '"',
          'apos': "'",
          'nbsp': '\u00a0',
        }[entity] ??
        match[0] ??
        '';
  },
);

List<CommentTextPart> parseCommentText(
  String message, {
  Iterable<String> emoteTokens = const [],
  Map<String, UserId> mentionedUsers = const {},
  Map<String, String> linkTitles = const {},
}) {
  final text = decodeCommentEntities(message);
  final emotes = emoteTokens.where((token) => token.isNotEmpty).toSet().toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final mentions = <String, UserId>{
    for (final entry in mentionedUsers.entries)
      if (entry.key.isNotEmpty && entry.value.isValid)
        '@${entry.key}': entry.value,
  };
  final mentionTokens = mentions.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final pattern = RegExp(
    [
      if (emotes.isNotEmpty) emotes.map(RegExp.escape).join('|'),
      // Consume a whole URL before looking for timestamps within its path/query.
      // Other schemes also own their entire token, preventing a BV inside an
      // unsupported URL from becoming a separate clickable video reference.
      r'''[A-Za-z][A-Za-z0-9+.-]*://[^\s<>"'，。！？；：、（）【】「」『』《》]+''',
      r'''(?<![0-9A-Za-z_@./:?=&%#-])(?://)?(?:(?:(?:[wW]{3}|[mM])\.)?[bB][iI][lL][iI][bB][iI][lL][iI]\.[cC][oO][mM]|[bB]23\.[tT][vV])/[^\s<>"'，。！？；：、（）【】「」『』《》]+''',
      if (mentionTokens.isNotEmpty)
        '(?<![0-9A-Za-z_@])(?:${mentionTokens.map(RegExp.escape).join('|')})'
            r'(?=$|[\s:：,，.。!?！？;；、()（）\[\]【】「」『』《》@])',
      r'(?<![0-9A-Za-z_/@.?=&%#:-])(?:[bB][vV][0-9A-Za-z]{10}|[aA][vV][1-9][0-9]*)(?![0-9A-Za-z_])',
      // A full-width colon can also punctuate Chinese prose beside a timecode.
      // Reject digit-colon chains without losing labels such as "高能：00：09".
      r'(?<![0-9A-Za-z_:])(?<![0-9]：)(?:[0-9]{1,3}[:：][0-5][0-9][:：][0-5][0-9]|[0-9]{1,4}[:：][0-5][0-9])(?![0-9A-Za-z_:]|：[0-9])',
    ].join('|'),
  );
  final parts = <CommentTextPart>[];
  var cursor = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > cursor) {
      parts.add(
        CommentTextPart(
          text.substring(cursor, match.start),
          CommentTextKind.plain,
        ),
      );
    }
    final token = match[0] ?? '';
    if (emotes.contains(token)) {
      parts.add(CommentTextPart(token, CommentTextKind.emote));
      cursor = match.end;
    } else if (mentions[token] case final userId?) {
      parts.add(
        CommentTextPart(token, CommentTextKind.mention, userId: userId),
      );
      cursor = match.end;
    } else if (!RegExp(r'^[0-9]').hasMatch(token)) {
      final link = _trimLinkPunctuation(token);
      final uri = parseCommentLinkUri(link);
      final video = uri != null && parseCommentVideoLink(uri) != null;
      final title = linkTitles[link];
      parts.add(
        CommentTextPart(
          link,
          uri == null
              ? CommentTextKind.plain
              : video
              ? CommentTextKind.videoLink
              : CommentTextKind.link,
          url: uri,
          linkTitle:
              uri != null &&
                  (video || isBilibiliShortLink(uri)) &&
                  title != null &&
                  title.trim().isNotEmpty
              ? decodeCommentEntities(title.trim())
              : null,
        ),
      );
      // Keep punctuation in the comment, outside the clickable link.
      cursor = match.start + link.length;
    } else {
      final fields = token
          .replaceAll('：', ':')
          .split(':')
          .map(int.parse)
          .toList();
      final seconds = fields.length == 3
          ? fields[0] * 3600 + fields[1] * 60 + fields[2]
          : fields[0] * 60 + fields[1];
      parts.add(
        CommentTextPart(
          token,
          CommentTextKind.timestamp,
          position: Duration(seconds: seconds),
        ),
      );
      cursor = match.end;
    }
  }
  if (cursor < text.length) {
    parts.add(CommentTextPart(text.substring(cursor), CommentTextKind.plain));
  }
  return List.unmodifiable(parts);
}

String _trimLinkPunctuation(String text) {
  var end = text.length;
  while (end > 0) {
    final last = text[end - 1];
    if ('.,!?;:'.contains(last)) {
      end--;
      continue;
    }
    final opening = const {')': '(', ']': '[', '}': '{'}[last];
    if (opening != null) {
      final candidate = text.substring(0, end);
      if (opening.allMatches(candidate).length <
          last.allMatches(candidate).length) {
        end--;
        continue;
      }
    }
    break;
  }
  return text.substring(0, end);
}
