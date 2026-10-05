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
  });
  final String id, title, text;
  final UserId? userId;
  final Uri? avatarUrl, targetUrl;
  final DateTime? time;
  final int? sessionType;
  final bool system;
  final int unread;
  final String? lastSequence;
  bool get canSend => sessionType == 1 && !system && userId != null;
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
  });
  final String id, sequence, text;
  final UserId senderId;
  final int type;
  final DateTime? time;
  final Uri? imageUrl, targetUrl;
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
}
