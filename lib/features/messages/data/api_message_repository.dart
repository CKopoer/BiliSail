import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import '../domain/message_repository.dart';

class ApiMessageRepository implements MessageRepository {
  const ApiMessageRepository(
    this.client,
    this.requests, {
    required String Function() accountScope,
  }) : _scope = accountScope;
  final MessageClient client;
  final ApiRequests requests;
  final String Function() _scope;
  @override
  String get accountScope => _scope();
  @override
  int get sessionEpoch => requests.sessionEpoch;

  Future<T> _run<T>(
    Future<T> Function(ApiRequestContext) action,
    RequestCancellation cancellation,
  ) async {
    if (!accountScope.startsWith('user:')) {
      throw const AppFailure(AppFailureKind.authentication, '登录后查看我的消息');
    }
    try {
      return await requests.run(action, cancellation: cancellation);
    } on AppFailure catch (error) {
      if (error.kind == AppFailureKind.permission) {
        throw const AppFailure(
          AppFailureKind.permission,
          '当前消息不可访问或账号暂时无法执行此操作',
        );
      }
      rethrow;
    }
  }

  @override
  Future<Map<InboxSection, int>> unread({
    required RequestCancellation cancellation,
  }) => _run((context) async {
    final counts = await client.unread(context: context);
    return Map.unmodifiable({
      for (final entry in counts.entries)
        InboxSection.values.byName(entry.key.name): entry.value,
    });
  }, cancellation);

  @override
  Future<MessagePage<InboxEntry>> inbox(
    InboxSection section, {
    String? cursor,
    required RequestCancellation cancellation,
  }) => _run((context) async {
    final page = section == InboxSection.private
        ? await client.sessions(cursor: cursor, context: context)
        : await client.notifications(
            ApiInboxSection.values.byName(section.name),
            cursor: cursor,
            context: context,
          );
    return MessagePage(
      List.unmodifiable(
        page.items.map(
          (e) => InboxEntry(
            id: e.id,
            title: e.title,
            text: e.text,
            userId: UserId.tryParse(e.userMid),
            avatarUrl: e.avatarUrl,
            time: e.time,
            targetUrl: e.targetUrl,
            sessionType: e.sessionType,
            system: e.system,
            unread: e.unread,
            lastSequence: e.lastSequence,
          ),
        ),
      ),
      hasMore: page.hasMore,
      cursor: page.nextCursor,
    );
  }, cancellation);

  @override
  Future<MessagePage<PrivateMessage>> thread(
    InboxEntry entry, {
    String? cursor,
    required RequestCancellation cancellation,
  }) => _run((context) async {
    final mid = entry.userId, type = entry.sessionType;
    if (mid == null || type == null) throw ArgumentError('Not a conversation');
    final page = await client.thread(
      mid.value,
      type,
      cursor: cursor,
      context: context,
    );
    return MessagePage(
      List.unmodifiable(
        page.items.map(
          (m) => PrivateMessage(
            id: m.id,
            sequence: m.sequence,
            senderId: UserId(m.senderMid),
            text: m.text,
            type: m.type,
            time: m.time,
            imageUrl: m.imageUrl,
            targetUrl: m.targetUrl,
          ),
        ),
      ),
      hasMore: page.hasMore,
      cursor: page.nextCursor,
    );
  }, cancellation);

  @override
  Future<void> sendText(
    InboxEntry entry,
    String text, {
    required RequestCancellation cancellation,
  }) {
    if (!entry.canSend) {
      throw const AppFailure(AppFailureKind.permission, '此会话暂不支持发送');
    }
    final receiver = entry.userId;
    if (receiver == null) throw ArgumentError('Missing receiver');
    final sender = accountScope.substring('user:'.length);
    return _run(
      (context) =>
          client.sendText(sender, receiver.value, text, context: context),
      cancellation,
    );
  }

  @override
  Future<void> markRead(
    InboxEntry entry,
    String sequence, {
    required RequestCancellation cancellation,
  }) {
    final mid = entry.userId, type = entry.sessionType;
    if (mid == null || type == null) throw ArgumentError('Not a conversation');
    return _run(
      (context) => client.markRead(mid.value, type, sequence, context: context),
      cancellation,
    );
  }
}
