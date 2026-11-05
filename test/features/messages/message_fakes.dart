import 'dart:async';

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/messages/domain/message_repository.dart';
import 'package:bilisail/features/messages/domain/message_management.dart';

const conversation = InboxEntry(
  id: '1:2',
  title: '测试会话',
  text: '消息摘要',
  userId: UserId('2'),
  sessionType: 1,
  unread: 3,
  lastSequence: '999',
);
const otherConversation = InboxEntry(
  id: '1:3',
  title: '另一会话',
  text: '另一摘要',
  userId: UserId('3'),
  sessionType: 1,
);
const privateMessage = PrivateMessage(
  id: '1',
  sequence: '1',
  senderId: UserId('2'),
  text: '测试私信正文',
  type: 1,
);
const systemNotification = InboxEntry(
  id: '10',
  title: '系统通知标题',
  text: '系统通知正文',
  system: true,
  readCursor: '1705288500000000001',
);

class AuthFake implements AuthRepository {
  final stream = StreamController<AuthState>.broadcast(sync: true);
  AuthState state = const AuthState(
    status: AuthStatus.signedIn,
    userName: '测试账号',
    mid: '1',
  );
  @override
  AuthState get current => state;
  @override
  Stream<AuthState> get changes => stream.stream;
  void emit(AuthState next) {
    state = next;
    stream.add(next);
  }

  @override
  Future<void> restore() async {}
  @override
  Future<void> signIn() async {}
  @override
  void cancelSignIn() {}
  @override
  Future<void> signOut() async => emit(const AuthState());
}

class MessageRepositoryFake implements MessageRepository {
  @override
  String accountScope = 'user:1';
  @override
  int sessionEpoch = 1;
  List<InboxEntry> entries = const [conversation, otherConversation];
  List<PrivateMessage> messages = const [privateMessage];
  bool more = true;
  String? cursor = '10';
  Completer<MessagePage<InboxEntry>>? inboxPending;
  Completer<MessagePage<PrivateMessage>>? threadPending;
  Completer<void>? writePending;
  Completer<Map<InboxSection, int>>? unreadPending;
  Object? writeFailure;
  Object? inboxFailure;
  Object? threadFailure;
  Object? unreadFailure;
  Map<InboxSection, int> counts = {InboxSection.private: 3};
  RequestCancellation? inboxRead, threadRead, writeRead;
  int sends = 0, marks = 0, reads = 0, systemMarks = 0, unreadReads = 0;
  String? lastText, lastAck, lastSystemCursor;
  InboxEntry? lastThread, lastSend;
  @override
  Future<Map<InboxSection, int>> unread({
    required RequestCancellation cancellation,
  }) async {
    unreadReads++;
    if (unreadFailure case final error?) throw error;
    return unreadPending?.future ?? Map.unmodifiable(counts);
  }

  @override
  Future<MessagePage<InboxEntry>> inbox(
    InboxSection section, {
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    reads++;
    inboxRead = cancellation;
    if (inboxFailure case final error?) throw error;
    if (section == InboxSection.replies || section == InboxSection.mentions) {
      counts[section] = 0;
    }
    return inboxPending == null
        ? MessagePage(entries, hasMore: more, cursor: this.cursor)
        : inboxPending!.future;
  }

  @override
  Future<MessagePage<PrivateMessage>> thread(
    InboxEntry entry, {
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    threadRead = cancellation;
    lastThread = entry;
    if (threadFailure case final error?) throw error;
    return threadPending == null
        ? MessagePage(messages, hasMore: more, cursor: this.cursor)
        : threadPending!.future;
  }

  @override
  Future<void> sendText(
    InboxEntry entry,
    String text, {
    required RequestCancellation cancellation,
  }) async {
    sends++;
    lastSend = entry;
    lastText = text;
    writeRead = cancellation;
    if (writeFailure case final error?) throw error;
    await writePending?.future;
  }

  @override
  Future<void> markRead(
    InboxEntry entry,
    String sequence, {
    required RequestCancellation cancellation,
  }) async {
    marks++;
    lastAck = sequence;
    writeRead = cancellation;
    if (writeFailure case final error?) throw error;
    await writePending?.future;
    counts[InboxSection.private] = 0;
  }

  @override
  Future<void> markSystemNotificationsRead(
    String cursor, {
    required RequestCancellation cancellation,
  }) async {
    systemMarks++;
    lastSystemCursor = cursor;
    writeRead = cancellation;
    if (writeFailure case final error?) throw error;
    await writePending?.future;
    counts[InboxSection.system] = 0;
  }
}

class ManagementMessageRepositoryFake extends MessageRepositoryFake
    implements MessageManagementRepository {
  int pins = 0, mutes = 0, removals = 0;
  Completer<void>? managementPending;
  Object? managementFailure;
  RequestCancellation? managementCancellation;
  bool? pinnedValue, mutedValue;

  Future<void> _manage(RequestCancellation cancellation) async {
    managementCancellation = cancellation;
    if (managementFailure case final error?) throw error;
    await managementPending?.future;
  }

  @override
  Future<void> setPinned(
    InboxEntry entry,
    bool pinned, {
    required RequestCancellation cancellation,
  }) {
    pins++;
    pinnedValue = pinned;
    return _manage(cancellation);
  }

  @override
  Future<void> setMuted(
    InboxEntry entry,
    bool muted, {
    required RequestCancellation cancellation,
  }) {
    mutes++;
    mutedValue = muted;
    return _manage(cancellation);
  }

  @override
  Future<void> removeConversation(
    InboxEntry entry, {
    required RequestCancellation cancellation,
  }) {
    removals++;
    return _manage(cancellation);
  }
}
