import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/messages/application/messages_controller.dart';
import 'package:bilisail/features/messages/domain/message_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'message_fakes.dart';

void main() {
  late MessageRepositoryFake repo;
  late AuthFake auth;
  late ProviderContainer container;
  late MessagesController controller;
  MessagesState state() => container.read(messagesControllerProvider);
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  setUp(() async {
    repo = MessageRepositoryFake();
    auth = AuthFake();
    container = ProviderContainer(
      overrides: [
        messageRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(auth),
      ],
    );
    container.listen(messagesControllerProvider, (_, _) {});
    controller = container.read(messagesControllerProvider.notifier);
    await flush();
  });
  tearDown(() async {
    container.dispose();
    await auth.stream.close();
  });
  test('opening inbox/thread performs no writes', () async {
    expect(state().inbox.items, hasLength(2));
    controller.selectConversation(conversation);
    await flush();
    expect(state().thread.items.single.text, '测试私信正文');
    expect(repo.sends + repo.marks, 0);
  });
  test('refresh cancels pagination and rejects its late completion', () async {
    final pending = repo.inboxPending = Completer<MessagePage<InboxEntry>>();
    final old = controller.loadInbox();
    final read = repo.inboxRead;
    repo.inboxPending = null;
    repo.entries = [];
    await controller.loadInbox(refresh: true);
    expect(read?.isCancelled, isTrue);
    pending.complete(const MessagePage([conversation], hasMore: false));
    await old;
    expect(state().inbox.items, isEmpty);
  });
  test('category selection isolates old inbox responses', () async {
    final pending = repo.inboxPending = Completer<MessagePage<InboxEntry>>();
    final old = controller.loadInbox(refresh: true);
    repo.inboxPending = null;
    repo.entries = [];
    controller.selectSection(InboxSection.replies);
    await flush();
    pending.complete(const MessagePage([conversation], hasMore: false));
    await old;
    expect(state().section, InboxSection.replies);
    expect(state().inbox.items, isEmpty);
  });
  test('conversation selection cancels and isolates previous thread', () async {
    final pending = repo.threadPending =
        Completer<MessagePage<PrivateMessage>>();
    controller.selectConversation(conversation);
    final read = repo.threadRead;
    repo.threadPending = null;
    repo.messages = [];
    controller.selectConversation(otherConversation);
    await flush();
    pending.complete(const MessagePage([privateMessage], hasMore: false));
    await flush();
    expect(read?.isCancelled, true);
    expect(state().selected?.id, otherConversation.id);
    expect(state().thread.items, isEmpty);
  });
  test('logout cancels pending send and clears private state', () async {
    controller.selectConversation(conversation);
    await flush();
    final pending = repo.writePending = Completer<void>();
    final send = controller.send('草稿');
    final read = repo.writeRead;
    repo.accountScope = 'guest';
    repo.sessionEpoch++;
    auth.emit(const AuthState());
    await flush();
    pending.complete();
    expect(await send, false);
    expect(read?.isCancelled, true);
    expect(state().inbox.items, isEmpty);
    expect(state().thread.items, isEmpty);
    expect(state().selected, isNull);
  });
  test('same user with a new epoch rejects old reads', () async {
    final pending = repo.inboxPending = Completer<MessagePage<InboxEntry>>();
    final old = controller.loadInbox(refresh: true);
    repo.sessionEpoch++;
    pending.complete(const MessagePage([otherConversation], hasMore: false));
    await old;
    expect(state().inbox.items, isEmpty);
  });
  test(
    'duplicate send clicks collapse; uncertain outcomes never replay',
    () async {
      controller.selectConversation(conversation);
      await flush();
      final pending = repo.writePending = Completer<void>();
      final send = controller.send('中文 & + %');
      expect(await controller.send('duplicate'), false);
      pending.completeError(
        const AppFailure(AppFailureKind.timeout, 'timeout'),
      );
      expect(await send, false);
      expect(repo.sends, 1);
      expect(repo.lastText, '中文 & + %');
      expect(state().writeMessage, contains('尚未确认'));
    },
  );
  test('acknowledgement uses only displayed newest sequence', () async {
    controller.selectConversation(conversation);
    await flush();
    expect(await controller.markRead(), true);
    expect(repo.lastAck, '1');
    expect(repo.marks, 1);
  });
  test(
    'system conversations cannot send and invalid drafts stay local',
    () async {
      const system = InboxEntry(
        id: 'sys',
        title: '系统',
        text: '',
        system: true,
        sessionType: 1,
      );
      controller.selectConversation(system);
      await flush();
      expect(await controller.send('text'), false);
      controller.selectConversation(conversation);
      await flush();
      expect(await controller.send(' '), false);
      expect(await controller.send('啊' * 1001), false);
      expect(repo.sends, 0);
    },
  );
  test(
    'pagination deduplicates, caps at 500 and stops stationary cursor',
    () async {
      await controller.loadInbox();
      expect(state().inbox.items, hasLength(2));
      expect(state().inbox.hasMore, false);
      repo.entries = List.generate(
        501,
        (i) => InboxEntry(id: '$i', title: '$i', text: ''),
      );
      await controller.loadInbox(refresh: true);
      expect(state().inbox.items, hasLength(500));
      expect(state().inbox.hasMore, false);
    },
  );
  test('empty pagination stops even if repository claims more', () async {
    repo.entries = [];
    repo.cursor = '20';
    await controller.loadInbox();
    expect(state().inbox.hasMore, false);
  });
  test(
    'thread cap retains newest messages when older page crosses the limit',
    () async {
      repo.messages = List.generate(
        501,
        (i) => PrivateMessage(
          id: '${i + 1}',
          sequence: '${i + 1}',
          senderId: privateMessage.senderId,
          text: '$i',
          type: 1,
        ),
      );
      controller.selectConversation(conversation);
      await flush();
      expect(state().thread.items, hasLength(500));
      expect(state().thread.items.first.sequence, '2');
      expect(state().thread.items.last.sequence, '501');
      expect(state().thread.hasMore, false);
    },
  );
  test('disposing a tab cancels its pending thread', () async {
    final pending = repo.threadPending =
        Completer<MessagePage<PrivateMessage>>();
    controller.selectConversation(conversation);
    final read = repo.threadRead;
    container.dispose();
    pending.complete(const MessagePage([], hasMore: false));
    await flush();
    expect(read?.isCancelled, true);
    // Keep tearDown idempotent by replacing the disposed container.
    container = ProviderContainer();
  });
}
