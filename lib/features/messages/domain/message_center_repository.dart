import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import 'message_repository.dart';

enum MessageSetting {
  notification('消息提醒', {1: '开启', 3: '关闭'}),
  receiveUnfollowed('接收未关注人消息', {1: '开启', 0: '关闭'}),
  foldUnfollowed('收起未关注人消息', {1: '开启', 0: '关闭'}),
  reply('回复我的消息提醒', {0: '所有人', 1: '关注的人', 2: '不接收'}),
  mention('@我的消息提醒', {0: '所有人', 1: '关注的人', 2: '不接收'}),
  like('收到的赞消息提醒', {0: '开启', 5: '关闭'}),
  smartIntercept('私信智能拦截', {1: '开启', 0: '关闭'});

  const MessageSetting(this.label, this.options);
  final String label;
  final Map<int, String> options;
}

final class MessageCenterSettings {
  const MessageCenterSettings(this.values);
  final Map<MessageSetting, int> values;
}

final class ChatMessageSettings {
  const ChatMessageSettings({
    required this.entryId,
    required this.contentPush,
    required this.showContentPush,
    required this.blocked,
  });
  final String entryId;
  final bool contentPush, showContentPush, blocked;
}

enum MessagePeopleKind { fans, contacts, blocked }

enum MessageAssistantKind { up, fanGroups }

final class MarkPrivateReadResult {
  const MarkPrivateReadResult({
    required this.requested,
    required this.acknowledged,
    this.failed = 0,
    this.uncertain = false,
  });
  final int requested, acknowledged, failed;
  final bool uncertain;
  bool get complete => requested == acknowledged && failed == 0;
  String get summary => complete
      ? '已将 $acknowledged 个已加载私信会话标为已读'
      : '已确认 $acknowledged/$requested 个会话已读，已停止后续操作。${uncertain ? '最后一次操作结果尚未确认，请刷新核对。' : '请刷新核对后再操作。'}';
}

final class MessagePerson {
  const MessagePerson({
    required this.id,
    required this.name,
    this.sign = '',
    this.avatarUrl,
  });
  final UserId id;
  final String name, sign;
  final Uri? avatarUrl;
}

final class MessageBlockedWords {
  const MessageBlockedWords(
    this.words, {
    this.limit = 200,
    this.wordLength = 20,
  });
  final List<String> words;
  final int limit, wordLength;
}

final class ClearConversationsResult {
  const ClearConversationsResult({
    required this.requested,
    required this.removed,
    this.failed = 0,
    this.uncertain = false,
  });
  final int requested, removed, failed;
  final bool uncertain;
  bool get complete => removed == requested && failed == 0;
  String get summary => complete
      ? '已移除 $removed 个已确认的会话'
      : '已确认移除 $removed/$requested 个会话，已停止后续操作。'
            '${uncertain ? '最后一次操作结果尚未确认，请刷新核对。' : '请刷新核对后再操作。'}';
}

abstract interface class MessageCenterRepository {
  String get accountScope;
  int get sessionEpoch;
  Future<MessageCenterSettings> settings({
    required RequestCancellation cancellation,
  });
  Future<void> setSetting(
    MessageSetting setting,
    int value, {
    required RequestCancellation cancellation,
  });
  Future<MessageBlockedWords> blockedWords({
    required RequestCancellation cancellation,
  });
  Future<void> addBlockedWord(
    String word, {
    required RequestCancellation cancellation,
  });
  Future<void> removeBlockedWord(
    String word, {
    required RequestCancellation cancellation,
  });
  Future<MessagePage<MessagePerson>> people(
    MessagePeopleKind kind, {
    String? cursor,
    required RequestCancellation cancellation,
  });
  Future<MessagePage<InboxEntry>> assistantSessions(
    MessageAssistantKind kind, {
    String? cursor,
    required RequestCancellation cancellation,
  });
  Future<ChatMessageSettings> chatSettings(
    InboxEntry entry, {
    required RequestCancellation cancellation,
  });
  Future<void> setContentPush(
    InboxEntry entry,
    bool enabled, {
    required RequestCancellation cancellation,
  });
  Future<void> setBlocked(
    InboxEntry entry,
    bool blocked, {
    required RequestCancellation cancellation,
  });
  Future<void> reportConversation(
    InboxEntry entry,
    int reason,
    String text, {
    required RequestCancellation cancellation,
  });
  Future<MarkPrivateReadResult> markAllPrivateRead(
    List<InboxEntry> entries, {
    required RequestCancellation cancellation,
  });
  Future<ClearConversationsResult> clearConversations(
    List<InboxEntry> entries, {
    required RequestCancellation cancellation,
  });
}
