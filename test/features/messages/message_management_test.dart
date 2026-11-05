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
  late ManagementMessageRepositoryFake repo;
  late AuthFake auth;
  late ProviderContainer container;
  late MessagesController controller;
  MessagesState state() => container.read(messagesControllerProvider);
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  setUp(() async {
    repo = ManagementMessageRepositoryFake();
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

  test(
    'pin reorders only after success and unpin restores source order',
    () async {
      expect(controller.supportsManagement, isTrue);
      final pending = repo.managementPending = Completer<void>();
      final write = controller.setPinned(otherConversation, true);
      expect(state().managingIds, contains(otherConversation.id));
      expect(state().inbox.items.first.id, conversation.id);
      pending.complete();
      expect(await write, isTrue);
      expect(state().inbox.items.first.id, otherConversation.id);
      expect(state().inbox.items.first.pinned, isTrue);
      expect(state().managingIds, isEmpty);
      repo.managementPending = null;
      expect(
        await controller.setPinned(state().inbox.items.first, false),
        isTrue,
      );
      expect(state().inbox.items.first.id, conversation.id);
    },
  );

  test(
    'mute preserves selected metadata and serializes one conversation',
    () async {
      controller.selectConversation(conversation);
      await flush();
      final pending = repo.managementPending = Completer<void>();
      final write = controller.setMuted(conversation, true);
      expect(await controller.setPinned(conversation, true), isFalse);
      expect(await controller.send('pending'), isFalse);
      expect(repo.pins, 0);
      expect(state().selected?.muted, isFalse);
      pending.complete();
      expect(await write, isTrue);
      expect(repo.mutedValue, isTrue);
      expect(state().selected?.muted, isTrue);
      expect(state().selected?.lastSequence, conversation.lastSequence);
      expect(state().thread.items, isNotEmpty);
    },
  );

  test(
    'uncertain mutation keeps row and exposes refresh guidance without retry',
    () async {
      repo.managementFailure = const AppFailure(
        AppFailureKind.timeout,
        'timeout',
      );
      expect(await controller.removeConversation(conversation), isFalse);
      expect(state().inbox.items.map((e) => e.id), contains(conversation.id));
      expect(state().writeMessage, contains('请刷新核对'));
      expect(repo.removals, 1);
      expect(state().managingIds, isEmpty);
    },
  );

  test(
    'removing selected conversation cancels late thread and clears selection',
    () async {
      final pending = repo.threadPending =
          Completer<MessagePage<PrivateMessage>>();
      controller.selectConversation(conversation);
      final read = repo.threadRead;
      expect(await controller.removeConversation(conversation), isTrue);
      expect(read?.isCancelled, isTrue);
      expect(state().selected, isNull);
      expect(
        state().inbox.items.map((e) => e.id),
        isNot(contains(conversation.id)),
      );
      pending.complete(const MessagePage([privateMessage], hasMore: false));
      await flush();
      expect(state().thread.items, isEmpty);
    },
  );

  test('a stale page cannot undo completed pin, mute or removal', () async {
    final pending = repo.inboxPending = Completer<MessagePage<InboxEntry>>();
    final read = controller.loadInbox();
    expect(await controller.setPinned(otherConversation, true), isTrue);
    expect(await controller.setMuted(state().inbox.items.first, true), isTrue);
    expect(await controller.removeConversation(conversation), isTrue);
    pending.complete(
      const MessagePage([conversation, otherConversation], hasMore: false),
    );
    await read;
    expect(state().inbox.items.single.id, otherConversation.id);
    expect(state().inbox.items.single.pinned, isTrue);
    expect(state().inbox.items.single.muted, isTrue);
  });

  test('a refresh begun during a write cannot undo its result', () async {
    final mutation = repo.managementPending = Completer<void>();
    final write = controller.setPinned(otherConversation, true);
    final pending = repo.inboxPending = Completer<MessagePage<InboxEntry>>();
    final read = controller.loadInbox(refresh: true);
    mutation.complete();
    expect(await write, isTrue);
    pending.complete(
      const MessagePage([conversation, otherConversation], hasMore: false),
    );
    await read;
    expect(state().inbox.items.first.id, otherConversation.id);
    expect(state().inbox.items.first.pinned, isTrue);
  });

  test(
    'a failed stale page cannot restore a removed row or undo mute',
    () async {
      final pending = repo.inboxPending = Completer<MessagePage<InboxEntry>>();
      final read = controller.loadInbox();
      expect(await controller.setMuted(otherConversation, true), isTrue);
      expect(await controller.removeConversation(conversation), isTrue);
      pending.completeError(
        const AppFailure(AppFailureKind.network, 'offline'),
      );
      await read;
      expect(state().inbox.items.single.id, otherConversation.id);
      expect(state().inbox.items.single.muted, isTrue);
      expect(state().inbox.error, 'offline');
    },
  );

  test(
    'stale entries cannot toggle a newer row or mutate another account',
    () async {
      expect(await controller.setPinned(conversation, true), isTrue);
      expect(await controller.setMuted(conversation, true), isFalse);
      expect(repo.mutes, 0);
      final stale = state().inbox.items.first;
      repo.accountScope = 'user:9';
      repo.sessionEpoch++;
      repo.entries = [
        InboxEntry(
          id: conversation.id,
          title: conversation.title,
          text: conversation.text,
          userId: conversation.userId,
          sessionType: 1,
        ),
      ];
      auth.emit(const AuthState(status: AuthStatus.signedIn, mid: '9'));
      await flush();
      expect(state().inbox.items.single.id, stale.id);
      expect(await controller.removeConversation(stale), isFalse);
      expect(repo.removals, 0);
    },
  );

  test(
    'late mutation after category switch cannot alter other category',
    () async {
      final pending = repo.managementPending = Completer<void>();
      final write = controller.setPinned(conversation, true);
      controller.selectSection(InboxSection.replies);
      await flush();
      pending.complete();
      expect(await write, isTrue);
      expect(state().section, InboxSection.replies);
      expect(state().inbox.items.first.pinned, isFalse);
      expect(state().writeMessage, isNull);
    },
  );

  test(
    'account transition cancels mutations and rejects late completion',
    () async {
      final pending = repo.managementPending = Completer<void>();
      final write = controller.setPinned(conversation, true);
      repo.accountScope = 'user:9';
      repo.sessionEpoch++;
      auth.emit(const AuthState(status: AuthStatus.signedIn, mid: '9'));
      await flush();
      expect(repo.managementCancellation?.isCancelled, isTrue);
      pending.complete();
      expect(await write, isFalse);
      expect(state().inbox.items.first.pinned, isFalse);
      expect(state().managingIds, isEmpty);
    },
  );

  test('unsupported system and group entries never mutate', () async {
    const group = InboxEntry(id: '2:4', title: '群', text: '', sessionType: 2);
    expect(await controller.setMuted(systemNotification, true), isFalse);
    expect(await controller.removeConversation(group), isFalse);
    expect(repo.mutes + repo.removals, 0);
  });
}
