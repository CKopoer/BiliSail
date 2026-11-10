import '../../../domain/local_image.dart';

enum DynamicTextKind { mention, emote }

final class DynamicTextSpan {
  const DynamicTextSpan(this.start, this.end, this.kind, {this.id = ''});
  final int start, end;
  final DynamicTextKind kind;
  final String id;
}

/// Keeps identities only for untouched tokens; offsets use UTF-16 like editors.
List<DynamicTextSpan> reconcileDynamicText(
  String before,
  String after,
  List<DynamicTextSpan> spans,
) {
  if (before == after) return spans;
  var start = 0;
  while (start < before.length &&
      start < after.length &&
      before.codeUnitAt(start) == after.codeUnitAt(start)) {
    start++;
  }
  var oldEnd = before.length, newEnd = after.length;
  while (oldEnd > start &&
      newEnd > start &&
      before.codeUnitAt(oldEnd - 1) == after.codeUnitAt(newEnd - 1)) {
    oldEnd--;
    newEnd--;
  }
  final shift = newEnd - oldEnd;
  return List.unmodifiable([
    for (final span in spans)
      if (span.end <= start)
        span
      else if (span.start >= oldEnd)
        DynamicTextSpan(
          span.start + shift,
          span.end + shift,
          span.kind,
          id: span.id,
        ),
  ]);
}

enum DynamicReplyPolicy { allow, close, selected }

final class DynamicPublishOptions {
  const DynamicPublishOptions({
    this.replyPolicy = DynamicReplyPolicy.allow,
    this.onlySelf = false,
    this.publishAt,
  });
  final DynamicReplyPolicy replyPolicy;
  final bool onlySelf;
  final DateTime? publishAt;
  bool validAt(DateTime now) =>
      publishAt == null ||
      (!onlySelf &&
          !publishAt!.isBefore(now.add(const Duration(minutes: 6))) &&
          !publishAt!.isAfter(now.add(const Duration(days: 7))));
}

final class DynamicMention {
  const DynamicMention(this.id, this.name, {this.avatar});
  final String id, name;
  final Uri? avatar;
}

final class DynamicEmote {
  const DynamicEmote(this.text, this.imageUrl);
  final String text;
  final Uri? imageUrl;
}

final class DynamicEmotePackage {
  const DynamicEmotePackage(this.name, this.items);
  final String name;
  final List<DynamicEmote> items;
}

final class DynamicPollOption {
  const DynamicPollOption(this.text, {this.image});
  final String text;
  final LocalImage? image;
}

final class DynamicPollDraft {
  DynamicPollDraft({
    required this.title,
    this.description = '',
    required List<DynamicPollOption> options,
    required this.endsAt,
    this.maxChoices = 1,
    this.withImages = false,
  }) : options = List.unmodifiable(options);
  final String title, description;
  final List<DynamicPollOption> options;
  final DateTime endsAt;
  final int maxChoices;
  final bool withImages;
  bool validAt(DateTime now) =>
      title.trim().isNotEmpty &&
      title.runes.length <= 100 &&
      description.runes.length <= 500 &&
      options.length >= 2 &&
      options.length <= 20 &&
      maxChoices >= 1 &&
      maxChoices <= options.length &&
      endsAt.isAfter(now) &&
      !endsAt.isAfter(now.add(const Duration(days: 90))) &&
      options.every(
        (o) =>
            o.text.trim().isNotEmpty &&
            o.text.runes.length <= 50 &&
            (!withImages ||
                (o.image != null &&
                    o.image!.bytes.isNotEmpty &&
                    o.image!.bytes.length <= LocalImage.maxBytes &&
                    const {
                      'image/jpeg',
                      'image/png',
                      'image/gif',
                    }.contains(o.image!.mimeType))),
      );
}

final class DynamicReserveDraft {
  const DynamicReserveDraft(
    this.title,
    this.startsAt, {
    this.onlyMembers = false,
  });
  final String title;
  final DateTime startsAt;
  final bool onlyMembers;
  bool validAt(DateTime now) =>
      title.trim().isNotEmpty &&
      title.runes.length <= 50 &&
      startsAt.isAfter(now) &&
      !startsAt.isAfter(now.add(const Duration(days: 90)));
}
