import '../../../domain/user.dart';

enum CommentTextKind { plain, emote, link, timestamp, mention }

final class CommentTextPart {
  const CommentTextPart(
    this.text,
    this.kind, {
    this.url,
    this.position,
    this.userId,
  });

  final String text;
  final CommentTextKind kind;
  final Uri? url;
  final Duration? position;
  final UserId? userId;
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
      r'''[hH][tT][tT][pP][sS]?://[^\s<>"'，。！？；：、（）【】「」『』《》]+''',
      if (mentionTokens.isNotEmpty)
        '(?<![0-9A-Za-z_@])(?:${mentionTokens.map(RegExp.escape).join('|')})'
            r'(?=$|[\s:：,，.。!?！？;；、()（）\[\]【】「」『』《》@])',
      r'(?<![0-9A-Za-z_:])(?:[0-9]{1,3}:[0-5][0-9]:[0-5][0-9]|[0-9]{1,4}:[0-5][0-9])(?![0-9A-Za-z_:])',
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
    } else if (token.toLowerCase().startsWith('http')) {
      final link = _trimLinkPunctuation(token);
      final uri = Uri.tryParse(link);
      final valid =
          uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty;
      parts.add(
        CommentTextPart(
          link,
          valid ? CommentTextKind.link : CommentTextKind.plain,
          url: valid ? uri : null,
        ),
      );
      // Keep punctuation in the comment, outside the clickable link.
      cursor = match.start + link.length;
    } else {
      final fields = token.split(':').map(int.parse).toList();
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
