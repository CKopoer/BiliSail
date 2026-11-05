import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import '../domain/message_repository.dart';
import '../domain/message_management.dart';
import '../domain/message_composer.dart';

class ApiMessageRepository
    implements
        MessageRepository,
        MessageManagementRepository,
        MessageComposeRepository {
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
            readCursor: e.readCursor,
            sourceText: e.sourceText,
            sourceTitle: e.sourceTitle,
            sourceImageUrl: e.sourceImageUrl,
            pinned: e.pinned,
            muted: e.muted,
            emotes: e.emotes,
            replyContext: switch (e.replyContext) {
              final context? => MessageReplyContext(
                subjectId: context.subjectId,
                businessId: context.businessId,
                rootId: context.rootId,
                parentId: context.parentId,
                author: context.author,
                userId: UserId.tryParse(context.userMid),
              ),
              _ => null,
            },
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
            kind: MessageContentKind.values.byName(m.kind.name),
            title: m.title,
            subtitle: m.subtitle,
            cards: List.unmodifiable(
              m.cards.map(
                (card) => MessageCard(
                  title: card.title,
                  description: card.description,
                  imageUrl: card.imageUrl,
                  targetUrl: card.targetUrl,
                ),
              ),
            ),
            details: List.unmodifiable(
              m.details.map(
                (detail) =>
                    MessageDetail(label: detail.label, value: detail.value),
              ),
            ),
            links: List.unmodifiable(
              m.links.map(
                (link) => MessageLink(label: link.label, url: link.url),
              ),
            ),
            durationSeconds: m.durationSeconds,
            imageAspectRatio: m.imageAspectRatio,
            emotes: m.emotes,
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
  Future<List<MessageEmotePackage>> emotes({
    required RequestCancellation cancellation,
  }) => _run((context) async {
    final packages = await client.emotes(context: context);
    return List.unmodifiable(
      packages.map(
        (package) => MessageEmotePackage(
          package.name,
          List.unmodifiable(
            package.items.map((item) => MessageEmote(item.text, item.imageUrl)),
          ),
        ),
      ),
    );
  }, cancellation);

  @override
  Future<void> sendImage(
    InboxEntry entry,
    MessageLocalImage image, {
    required RequestCancellation cancellation,
  }) {
    if (!entry.canSend) {
      throw const AppFailure(AppFailureKind.permission, '此会话暂不支持发送');
    }
    final receiver = entry.userId;
    if (receiver == null) throw ArgumentError('Missing receiver');
    final sender = accountScope.substring('user:'.length);
    return _run((context) async {
      final picture = await client.api.uploadMessagePicture(
        image.bytes,
        image.mimeType,
        context: context,
      );
      // The second write keeps the original cancellation/epoch/deadline. An
      // account transition after upload must never send into the next account.
      await client.sendImage(
        sender,
        receiver.value,
        picture,
        mimeType: image.mimeType,
        context: context,
      );
    }, cancellation);
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

  @override
  Future<void> markSystemNotificationsRead(
    String cursor, {
    required RequestCancellation cancellation,
  }) => _run(
    (context) => client.markSystemNotificationsRead(cursor, context: context),
    cancellation,
  );

  String _managedMid(InboxEntry entry) {
    final mid = entry.userId;
    if (!entry.canSend || mid == null || !mid.isValid) {
      throw const AppFailure(AppFailureKind.permission, '此会话暂不支持管理');
    }
    return mid.value;
  }

  @override
  Future<void> setPinned(
    InboxEntry entry,
    bool pinned, {
    required RequestCancellation cancellation,
  }) {
    final mid = _managedMid(entry);
    return _run(
      (context) =>
          MessageManagementClient(client.api)
              .setPinned(mid, pinned, context: context),
      cancellation,
    );
  }

  @override
  Future<void> setMuted(
    InboxEntry entry,
    bool muted, {
    required RequestCancellation cancellation,
  }) {
    final mid = _managedMid(entry);
    return _run(
      (context) => MessageManagementClient(client.api).setMuted(
        accountScope.substring('user:'.length),
        mid,
        muted,
        context: context,
      ),
      cancellation,
    );
  }

  @override
  Future<void> removeConversation(
    InboxEntry entry, {
    required RequestCancellation cancellation,
  }) {
    final mid = _managedMid(entry);
    return _run(
      (context) =>
          MessageManagementClient(client.api)
              .removeConversation(mid, context: context),
      cancellation,
    );
  }
}
