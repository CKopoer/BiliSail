import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';

enum InboxSection {
  private('私信'),
  replies('回复我的'),
  mentions('@我的'),
  likes('收到的赞'),
  system('系统通知');

  const InboxSection(this.label);
  final String label;
}

enum MessageContentKind {
  text,
  image,
  share,
  notification,
  video,
  article,
  pictureCard,
  commonCard,
  autoReply,
  notice,
  voice,
  miniProgram,
  withdrawn,
  unsupported,
}

final class MessageCard {
  const MessageCard({
    this.title = '',
    this.description = '',
    this.imageUrl,
    this.targetUrl,
  });
  final String title, description;
  final Uri? imageUrl, targetUrl;
}

final class MessageDetail {
  const MessageDetail({required this.label, required this.value});
  final String label, value;
}

final class MessageLink {
  const MessageLink({required this.label, required this.url});
  final String label;
  final Uri url;
}

final class MessageReplyContext {
  const MessageReplyContext({
    required this.subjectId,
    required this.businessId,
    this.rootId,
    required this.parentId,
    required this.author,
    this.userId,
  });
  final String subjectId, parentId, author;
  final int businessId;
  final String? rootId;
  final UserId? userId;
}

final class InboxEntry {
  const InboxEntry({
    required this.id,
    required this.title,
    required this.text,
    this.userId,
    this.avatarUrl,
    this.time,
    this.targetUrl,
    this.sessionType,
    this.system = false,
    this.unread = 0,
    this.lastSequence,
    this.readCursor,
    this.sourceText = '',
    this.sourceTitle = '',
    this.sourceImageUrl,
    this.pinned = false,
    this.muted = false,
    this.emotes = const {},
    this.replyContext,
  });
  final String id, title, text;
  final UserId? userId;
  final Uri? avatarUrl, targetUrl;
  final DateTime? time;
  final int? sessionType;
  final bool system;
  final int unread;
  final String? lastSequence;
  final String? readCursor;
  final String sourceText, sourceTitle;
  final Uri? sourceImageUrl;
  final bool pinned, muted;
  final Map<String, Uri> emotes;
  final MessageReplyContext? replyContext;
  bool get canSend => sessionType == 1 && !system && userId != null;

  InboxEntry withEmotes(Map<String, Uri> value) => InboxEntry(
    id: id,
    title: title,
    text: text,
    userId: userId,
    avatarUrl: avatarUrl,
    time: time,
    targetUrl: targetUrl,
    sessionType: sessionType,
    system: system,
    unread: unread,
    lastSequence: lastSequence,
    readCursor: readCursor,
    sourceText: sourceText,
    sourceTitle: sourceTitle,
    sourceImageUrl: sourceImageUrl,
    pinned: pinned,
    muted: muted,
    emotes: Map.unmodifiable(value),
    replyContext: replyContext,
  );
}

final class PrivateMessage {
  const PrivateMessage({
    required this.id,
    required this.sequence,
    required this.senderId,
    required this.text,
    required this.type,
    this.time,
    this.imageUrl,
    this.targetUrl,
    this.kind = MessageContentKind.text,
    this.title = '',
    this.subtitle = '',
    this.cards = const [],
    this.details = const [],
    this.links = const [],
    this.durationSeconds,
    this.imageAspectRatio,
    this.emotes = const {},
  });
  final String id, sequence, text;
  final UserId senderId;
  final int type;
  final DateTime? time;
  final Uri? imageUrl, targetUrl;
  final MessageContentKind kind;
  final String title, subtitle;
  final List<MessageCard> cards;
  final List<MessageDetail> details;
  final List<MessageLink> links;
  final int? durationSeconds;
  final double? imageAspectRatio;
  final Map<String, Uri> emotes;

  PrivateMessage withEmotes(Map<String, Uri> value) => PrivateMessage(
    id: id,
    sequence: sequence,
    senderId: senderId,
    text: text,
    type: type,
    time: time,
    imageUrl: imageUrl,
    targetUrl: targetUrl,
    kind: kind,
    title: title,
    subtitle: subtitle,
    cards: cards,
    details: details,
    links: links,
    durationSeconds: durationSeconds,
    imageAspectRatio: imageAspectRatio,
    emotes: Map.unmodifiable(value),
  );
}

final class MessagePage<T> {
  const MessagePage(this.items, {required this.hasMore, this.cursor});
  final List<T> items;
  final bool hasMore;
  final String? cursor;
}

abstract interface class MessageRepository {
  String get accountScope;
  int get sessionEpoch;
  Future<Map<InboxSection, int>> unread({
    required RequestCancellation cancellation,
  });
  Future<MessagePage<InboxEntry>> inbox(
    InboxSection section, {
    String? cursor,
    required RequestCancellation cancellation,
  });
  Future<MessagePage<PrivateMessage>> thread(
    InboxEntry entry, {
    String? cursor,
    required RequestCancellation cancellation,
  });
  Future<void> sendText(
    InboxEntry entry,
    String text, {
    required RequestCancellation cancellation,
  });
  Future<void> markRead(
    InboxEntry entry,
    String sequence, {
    required RequestCancellation cancellation,
  });
  Future<void> markSystemNotificationsRead(
    String cursor, {
    required RequestCancellation cancellation,
  });
}
