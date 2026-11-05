import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import '../domain/message_center_repository.dart';
import '../domain/message_repository.dart';

final class ApiMessageCenterRepository implements MessageCenterRepository {
  const ApiMessageCenterRepository(
    this.client,
    this.requests, {
    required String Function() accountScope,
  }) : _scope = accountScope;
  final MessageCenterClient client;
  final ApiRequests requests;
  final String Function() _scope;
  @override
  String get accountScope => _scope();
  @override
  int get sessionEpoch => requests.sessionEpoch;

  Future<T> _run<T>(
    Future<T> Function(ApiRequestContext) action,
    RequestCancellation cancellation,
  ) {
    if (!accountScope.startsWith('user:')) {
      throw const AppFailure(AppFailureKind.authentication, '登录后管理消息');
    }
    return requests.run(action, cancellation: cancellation);
  }

  String _mid(InboxEntry entry) {
    final mid = entry.userId;
    if (!entry.canSend || mid == null || !mid.isValid) {
      throw const AppFailure(AppFailureKind.permission, '此会话暂不支持聊天设置');
    }
    return mid.value;
  }

  @override
  Future<MessageCenterSettings> settings({
    required RequestCancellation cancellation,
  }) => _run((context) async {
    final result = await client.settings(context: context);
    return MessageCenterSettings(
      Map.unmodifiable({
        for (final e in result.values.entries)
          MessageSetting.values.byName(e.key.name): e.value,
      }),
    );
  }, cancellation);
  @override
  Future<void> setSetting(
    MessageSetting setting,
    int value, {
    required RequestCancellation cancellation,
  }) => _run(
    (context) => client.setSetting(
      ApiMessageSetting.values.byName(setting.name),
      value,
      context: context,
    ),
    cancellation,
  );
  @override
  Future<MessageBlockedWords> blockedWords({
    required RequestCancellation cancellation,
  }) => _run((context) async {
    final result = await client.blockedWords(context: context);
    return MessageBlockedWords(
      result.words,
      limit: result.limit,
      wordLength: result.wordLength,
    );
  }, cancellation);
  @override
  Future<void> addBlockedWord(
    String word, {
    required RequestCancellation cancellation,
  }) => _run(
    (context) => client.addBlockedWord(word, context: context),
    cancellation,
  );
  @override
  Future<void> removeBlockedWord(
    String word, {
    required RequestCancellation cancellation,
  }) => _run(
    (context) => client.removeBlockedWord(word, context: context),
    cancellation,
  );
  @override
  Future<MessagePage<MessagePerson>> people(
    MessagePeopleKind kind, {
    String? cursor,
    required RequestCancellation cancellation,
  }) => _run((context) async {
    final result = await client.people(
      accountScope.substring(5),
      ApiMessagePeopleKind.values.byName(kind.name),
      cursor: cursor,
      context: context,
    );
    return MessagePage(
      List.unmodifiable(
        result.items.map(
          (e) => MessagePerson(
            id: UserId(e.mid),
            name: e.name,
            sign: e.sign,
            avatarUrl: e.avatarUrl,
          ),
        ),
      ),
      hasMore: result.hasMore,
      cursor: result.nextCursor,
    );
  }, cancellation);
  @override
  Future<MessagePage<InboxEntry>> assistantSessions(
    MessageAssistantKind kind, {
    String? cursor,
    required RequestCancellation cancellation,
  }) => _run((context) async {
    final result = await client.assistantSessions(
      fanGroups: kind == MessageAssistantKind.fanGroups,
      cursor: cursor,
      context: context,
    );
    return MessagePage(
      List.unmodifiable(
        result.items.map(
          (e) => InboxEntry(
            id: e.id,
            title: e.title,
            text: e.text,
            userId: UserId.tryParse(e.userMid),
            avatarUrl: e.avatarUrl,
            sessionType: e.sessionType,
            system: true,
            unread: e.unread,
          ),
        ),
      ),
      hasMore: result.hasMore,
      cursor: result.nextCursor,
    );
  }, cancellation);
  @override
  Future<ChatMessageSettings> chatSettings(
    InboxEntry entry, {
    required RequestCancellation cancellation,
  }) {
    final mid = _mid(entry);
    return _run((context) async {
      final result = await client.chatSettings(mid, context: context);
      return ChatMessageSettings(
        entryId: entry.id,
        contentPush: result.contentPush,
        showContentPush: result.showContentPush,
        blocked: result.blocked,
      );
    }, cancellation);
  }

  @override
  Future<void> setContentPush(
    InboxEntry entry,
    bool enabled, {
    required RequestCancellation cancellation,
  }) {
    final mid = _mid(entry);
    return _run(
      (context) => client.setContentPush(mid, enabled, context: context),
      cancellation,
    );
  }

  @override
  Future<void> setBlocked(
    InboxEntry entry,
    bool blocked, {
    required RequestCancellation cancellation,
  }) {
    final mid = _mid(entry);
    return _run(
      (context) => client.setBlocked(mid, blocked, context: context),
      cancellation,
    );
  }

  @override
  Future<void> reportConversation(
    InboxEntry entry,
    int reason,
    String text, {
    required RequestCancellation cancellation,
  }) {
    final mid = _mid(entry);
    return _run(
      (context) =>
          client.reportConversation(mid, reason, text, context: context),
      cancellation,
    );
  }

  @override
  Future<MarkPrivateReadResult> markAllPrivateRead(
    List<InboxEntry> entries, {
    required RequestCancellation cancellation,
  }) {
    if (entries.length > 500) throw ArgumentError('Too many conversations');
    final unique = {for (final entry in entries) entry.id: entry};
    final targets = <({String mid, String sequence})>[];
    for (final entry in unique.values) {
      final mid = entry.userId, sequence = entry.lastSequence;
      if (entry.sessionType != 1 ||
          mid == null ||
          !mid.isValid ||
          sequence == null ||
          !RegExp(r'^[0-9]+$').hasMatch(sequence)) {
        throw ArgumentError('Invalid conversation acknowledgement');
      }
      targets.add((mid: mid.value, sequence: sequence));
    }
    return _run((context) async {
      var acknowledged = 0;
      for (final target in targets) {
        try {
          await MessageClient(client.api)
              .markRead(target.mid, 1, target.sequence, context: context);
          acknowledged++;
        } on ApiFailure catch (error) {
          if (error.category == ApiFailureCategory.cancelled) rethrow;
          return MarkPrivateReadResult(
            requested: unique.length,
            acknowledged: acknowledged,
            failed: 1,
            uncertain:
                error.category == ApiFailureCategory.network ||
                error.category == ApiFailureCategory.timeout ||
                (error.httpStatus ?? 0) >= 500,
          );
        }
      }
      return MarkPrivateReadResult(
        requested: unique.length,
        acknowledged: acknowledged,
      );
    }, cancellation);
  }

  @override
  Future<ClearConversationsResult> clearConversations(
    List<InboxEntry> entries, {
    required RequestCancellation cancellation,
  }) {
    if (entries.length > 500) throw ArgumentError('Too many conversations');
    final unique = {for (final entry in entries) entry.id: entry};
    for (final entry in unique.values) {
      _mid(entry);
    }
    return _run((context) async {
      var removed = 0;
      for (final entry in unique.values) {
        try {
          await MessageManagementClient(client.api)
              .removeConversation(_mid(entry), context: context);
          removed++;
        } on ApiFailure catch (error) {
          if (error.category == ApiFailureCategory.cancelled) rethrow;
          return ClearConversationsResult(
            requested: unique.length,
            removed: removed,
            failed: 1,
            uncertain:
                error.category == ApiFailureCategory.network ||
                error.category == ApiFailureCategory.timeout ||
                (error.httpStatus ?? 0) >= 500,
          );
        }
      }
      return ClearConversationsResult(
        requested: unique.length,
        removed: removed,
      );
    }, cancellation);
  }
}
