import 'dart:async';

import 'package:bili_lite/domain/request_cancellation.dart';
import 'package:bili_lite/domain/user.dart';
import 'package:bili_lite/features/auth/domain/auth_repository.dart';
import 'package:bili_lite/features/messages/domain/message_repository.dart';

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
  Object? writeFailure;
  RequestCancellation? inboxRead, threadRead, writeRead;
  int sends = 0, marks = 0, reads = 0;
  String? lastText, lastAck;
  @override
  Future<Map<InboxSection, int>> unread({
    required RequestCancellation cancellation,
  }) async => {InboxSection.private: 3};
  @override
  Future<MessagePage<InboxEntry>> inbox(
    InboxSection section, {
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    reads++;
    inboxRead = cancellation;
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
  }
}
