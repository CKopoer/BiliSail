import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/messages/application/message_center_controller.dart';
import 'package:bilisail/features/messages/domain/message_center_repository.dart';
import 'package:bilisail/features/messages/domain/message_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'message_fakes.dart';

class CenterFake implements MessageCenterRepository {
  @override
  String accountScope = 'user:1';
  @override
  int sessionEpoch = 1;
  int writes = 0;
  Object? failure;
  Completer<void>? pending;
  Completer<MessageCenterSettings>? settingsPending;
  Completer<MessagePage<MessagePerson>>? peoplePending;
  Completer<ChatMessageSettings>? chatPending;
  RequestCancellation? writeCancellation;
  List<String> words = const ['广告'];
  List<MessagePerson> persons = const [
    MessagePerson(id: UserId('2'), name: '联系人'),
  ];
  List<InboxEntry> assistants = const [];
  bool assistantsMore = false;
  String? assistantsCursor;
  @override
  Future<MessageCenterSettings> settings({
    required RequestCancellation cancellation,
  }) async =>
      settingsPending?.future ??
      const MessageCenterSettings({
        MessageSetting.notification: 1,
        MessageSetting.like: 0,
      });
  Future<void> _write(RequestCancellation cancellation) async {
    writes++;
    writeCancellation = cancellation;
    if (failure case final error?) throw error;
    await pending?.future;
  }

  @override
  Future<void> setSetting(
    MessageSetting setting,
    int value, {
    required RequestCancellation cancellation,
  }) => _write(cancellation);
  @override
  Future<MessageBlockedWords> blockedWords({
    required RequestCancellation cancellation,
  }) async => MessageBlockedWords(words, limit: 2, wordLength: 3);
  @override
  Future<void> addBlockedWord(
    String word, {
    required RequestCancellation cancellation,
  }) => _write(cancellation);
  @override
  Future<void> removeBlockedWord(
    String word, {
    required RequestCancellation cancellation,
  }) => _write(cancellation);
  @override
  Future<MessagePage<MessagePerson>> people(
    MessagePeopleKind kind, {
    String? cursor,
    required RequestCancellation cancellation,
  }) async => peoplePending?.future ?? MessagePage(persons, hasMore: false);
  @override
  Future<MessagePage<InboxEntry>> assistantSessions(
    MessageAssistantKind kind, {
    String? cursor,
    required RequestCancellation cancellation,
  }) async => MessagePage(
    assistants,
    hasMore: assistantsMore,
    cursor: assistantsCursor,
  );
  @override
  Future<ChatMessageSettings> chatSettings(
    InboxEntry entry, {
    required RequestCancellation cancellation,
  }) async =>
      chatPending?.future ??
      ChatMessageSettings(
        entryId: entry.id,
        contentPush: true,
        showContentPush: true,
        blocked: false,
      );
  @override
  Future<void> setContentPush(
    InboxEntry entry,
    bool enabled, {
    required RequestCancellation cancellation,
  }) => _write(cancellation);
  @override
  Future<void> setBlocked(
    InboxEntry entry,
    bool blocked, {
    required RequestCancellation cancellation,
  }) => _write(cancellation);
  @override
  Future<void> reportConversation(
    InboxEntry entry,
    int reason,
    String text, {
    required RequestCancellation cancellation,
  }) => _write(cancellation);
  @override
  Future<MarkPrivateReadResult> markAllPrivateRead(
    List<InboxEntry> entries, {
    required RequestCancellation cancellation,
  }) async {
    await _write(cancellation);
    return MarkPrivateReadResult(
      requested: entries.length,
      acknowledged: 1,
      failed: entries.length > 1 ? 1 : 0,
      uncertain: entries.length > 1,
    );
  }

  @override
  Future<ClearConversationsResult> clearConversations(
    List<InboxEntry> entries, {
    required RequestCancellation cancellation,
  }) async {
    await _write(cancellation);
    return ClearConversationsResult(
      requested: entries.length,
      removed: 1,
      failed: entries.length > 1 ? 1 : 0,
      uncertain: entries.length > 1,
    );
  }
}

void main() {
  late AuthFake auth;
  late CenterFake repo;
  late ProviderContainer container;
  late MessageCenterController controller;
  MessageCenterState state() => container.read(messageCenterControllerProvider);
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  setUp(() {
    auth = AuthFake();
    repo = CenterFake();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        messageCenterRepositoryProvider.overrideWithValue(repo),
      ],
    );
    container.listen(messageCenterControllerProvider, (_, _) {});
    controller = container.read(messageCenterControllerProvider.notifier);
  });
  tearDown(() async {
    container.dispose();
    await auth.stream.close();
  });

  test('settings save only on success, reject exact enum mismatch and duplicate click', () async {
    await controller.loadSettings();
    expect(await controller.setSetting(MessageSetting.like, 1), isFalse);
    final pending = repo.pending = Completer<void>();
    final write = controller.setSetting(MessageSetting.notification, 3);
    expect(state().settings?.values[MessageSetting.notification], 1);
    expect(
      await controller.setSetting(MessageSetting.notification, 3),
      isFalse,
    );
    pending.complete();
    expect(await write, isTrue);
    expect(state().settings?.values[MessageSetting.notification], 3);
    expect(repo.writes, 1);
    repo.pending = null;
    repo.failure = const AppFailure(AppFailureKind.timeout, 'timeout');
    expect(
      await controller.setSetting(MessageSetting.notification, 1),
      isFalse,
    );
    expect(state().settings?.values[MessageSetting.notification], 3);
    expect(state().error, contains('结果尚未确认'));
  });
  test('old settings read cannot roll back a confirmed update', () async {
    await controller.loadSettings();
    final pending = repo.settingsPending = Completer<MessageCenterSettings>();
    final read = controller.loadSettings();
    expect(await controller.setSetting(MessageSetting.notification, 3), isTrue);
    pending.complete(
      const MessageCenterSettings({MessageSetting.notification: 1}),
    );
    await read;
    expect(state().settings?.values[MessageSetting.notification], 3);
    expect(state().loadingSettings, isFalse);
  });
  test('words obey server limits and failures preserve the list', () async {
    await controller.loadWords();
    expect(await controller.addBlockedWord('太长的词语'), isFalse);
    expect(await controller.addBlockedWord('广告'), isFalse);
    expect(await controller.addBlockedWord('你好'), isTrue);
    expect(state().blockedWords, ['你好', '广告']);
    expect(await controller.addBlockedWord('满了'), isFalse);
    repo.failure = const AppFailure(AppFailureKind.permission, '拒绝');
    expect(await controller.removeBlockedWord('广告'), isFalse);
    expect(state().blockedWords, contains('广告'));
  });
  test('account changes cancel writes and reject stale settings', () async {
    await controller.loadSettings();
    final pending = repo.pending = Completer<void>();
    final write = controller.setSetting(MessageSetting.notification, 3);
    repo.accountScope = 'user:9';
    repo.sessionEpoch++;
    auth.emit(const AuthState(status: AuthStatus.signedIn, mid: '9'));
    await flush();
    expect(repo.writeCancellation?.isCancelled, isTrue);
    pending.complete();
    expect(await write, isFalse);
    expect(state().settings, isNull);
    expect(state().busy, isFalse);
  });
  test(
    'same account new epoch rejects loaded settings and chat writes',
    () async {
      await controller.loadSettings();
      await controller.loadChat(conversation);
      await controller.loadWords();
      repo.sessionEpoch++;
      expect(
        await controller.setSetting(MessageSetting.notification, 3),
        isFalse,
      );
      expect(await controller.setBlocked(conversation, true), isFalse);
      expect(await controller.addBlockedWord('你好'), isFalse);
      expect(repo.writes, 0);
    },
  );
  test(
    'chat settings and reports require loaded conversation identity',
    () async {
      expect(await controller.setBlocked(conversation, true), isFalse);
      await controller.loadChat(conversation);
      expect(await controller.setContentPush(conversation, false), isTrue);
      expect(state().chat?.contentPush, isFalse);
      expect(await controller.setBlocked(conversation, true), isTrue);
      expect(state().chat?.blocked, isTrue);
      expect(
        await controller.reportConversation(otherConversation, 4, '广告骚扰'),
        isFalse,
      );
      expect(await controller.reportConversation(conversation, 0, ''), isFalse);
      expect(
        await controller.reportConversation(conversation, 4, '广告骚扰'),
        isTrue,
      );
    },
  );
  test(
    'confirmed chat write survives a stale same-conversation refresh',
    () async {
      await controller.loadChat(conversation);
      final pending = repo.pending = Completer<void>();
      final write = controller.setBlocked(conversation, true);
      final chat = repo.chatPending = Completer<ChatMessageSettings>();
      final read = controller.loadChat(conversation);
      pending.complete();
      expect(await write, isTrue);
      chat.complete(
        ChatMessageSettings(
          entryId: conversation.id,
          contentPush: true,
          showContentPush: true,
          blocked: false,
        ),
      );
      await read;
      expect(state().chat?.blocked, isTrue);
      expect(state().loadingChat, isFalse);
    },
  );
  test(
    'partial batches retain accurate confirmed counts and no replay',
    () async {
      final clear = await controller.clearConversations([
        conversation,
        otherConversation,
      ]);
      expect(clear?.removed, 1);
      expect(clear?.complete, isFalse);
      expect(state().message, contains('1/2'));
      final read = await controller.markAllPrivateRead([
        conversation,
        otherConversation,
      ]);
      expect(read?.acknowledged, 1);
      expect(read?.uncertain, isTrue);
      expect(repo.writes, 2);
    },
  );
  test('people change isolates an old category and blacklist removal requires current row', () async {
    final pending = repo.peoplePending =
        Completer<MessagePage<MessagePerson>>();
    final read = controller.loadPeople(MessagePeopleKind.fans);
    repo.peoplePending = null;
    await controller.loadPeople(MessagePeopleKind.blocked);
    final person = state().people.single;
    expect(await controller.unblockPerson(person), isTrue);
    expect(state().people, isEmpty);
    pending.complete(
      const MessagePage([
        MessagePerson(id: UserId('9'), name: '旧粉丝'),
      ], hasMore: false),
    );
    await read;
    expect(state().people, isEmpty);
  });
  test('filtered assistant pages retain progressing cursor but stop at bounded request count', () async {
    repo.assistantsMore = true;
    for (var i = 0; i < 10; i++) {
      repo.assistantsCursor = '${100 - i}';
      await controller.loadAssistants(MessageAssistantKind.up);
    }
    expect(state().assistants, isEmpty);
    expect(state().assistantsHasMore, isFalse);
  });
}
