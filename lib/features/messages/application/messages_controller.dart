import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/message_repository.dart';

final messageRepositoryProvider = Provider<MessageRepository>(
  (ref) => throw UnimplementedError('MessageRepository'),
);
final unreadMessagesProvider =
    FutureProvider.autoDispose<Map<InboxSection, int>>((ref) async {
      final account = ref.watch(
        authControllerProvider.select((s) => (s.isSignedIn, s.mid)),
      );
      if (!account.$1) return const {};
      final cancellation = RequestCancellation();
      ref.onDispose(cancellation.cancel);
      return ref
          .watch(messageRepositoryProvider)
          .unread(cancellation: cancellation);
    });
final messagesControllerProvider =
    NotifierProvider.autoDispose<MessagesController, MessagesState>(
      MessagesController.new,
    );

final class MessageListState<T> {
  const MessageListState({
    this.items = const [],
    this.cursor,
    this.hasMore = true,
    this.loading = false,
    this.error,
  });
  final List<T> items;
  final String? cursor, error;
  final bool hasMore, loading;
}

final class MessagesState {
  const MessagesState({
    this.section = InboxSection.private,
    this.inbox = const MessageListState(),
    this.thread = const MessageListState(),
    this.selected,
    this.sending = false,
    this.markingRead = false,
    this.writeMessage,
  });
  final InboxSection section;
  final MessageListState<InboxEntry> inbox;
  final MessageListState<PrivateMessage> thread;
  final InboxEntry? selected;
  final bool sending, markingRead;
  final String? writeMessage;
  MessagesState copy({
    InboxSection? section,
    MessageListState<InboxEntry>? inbox,
    MessageListState<PrivateMessage>? thread,
    InboxEntry? selected,
    bool clearSelection = false,
    bool? sending,
    bool? markingRead,
    String? writeMessage,
    bool clearWriteMessage = false,
  }) => MessagesState(
    section: section ?? this.section,
    inbox: inbox ?? this.inbox,
    thread: thread ?? this.thread,
    selected: clearSelection ? null : selected ?? this.selected,
    sending: sending ?? this.sending,
    markingRead: markingRead ?? this.markingRead,
    writeMessage: clearWriteMessage ? null : writeMessage ?? this.writeMessage,
  );
}

class MessagesController extends Notifier<MessagesState> {
  int _generation = 0, _inboxVersion = 0, _threadVersion = 0;
  RequestCancellation? _inboxRead, _threadRead;
  final Set<RequestCancellation> _writes = {};

  @override
  MessagesState build() {
    final account = ref.watch(
      authControllerProvider.select((s) => (s.isSignedIn, s.mid)),
    );
    _cancel();
    final generation = ++_generation;
    ref.onDispose(() {
      ++_generation;
      _cancel();
    });
    if (account.$1) {
      Future<void>.microtask(() {
        if (ref.mounted && generation == _generation) loadInbox();
      });
    }
    return const MessagesState();
  }

  void _cancel() {
    _inboxRead?.cancel();
    _threadRead?.cancel();
    for (final write in _writes) {
      write.cancel();
    }
    _writes.clear();
    ++_inboxVersion;
    ++_threadVersion;
  }

  bool _current(int generation, String scope, int epoch) =>
      ref.mounted &&
      generation == _generation &&
      ref.read(messageRepositoryProvider).accountScope == scope &&
      ref.read(messageRepositoryProvider).sessionEpoch == epoch;
  String? _error(Object error, {bool write = false}) => error is AppFailure
      ? error.kind == AppFailureKind.cancelled
            ? null
            : write &&
                  (error.kind == AppFailureKind.timeout ||
                      error.kind == AppFailureKind.network)
            ? '操作结果尚未确认，请刷新核对后再决定是否重试'
            : error.message
      : write
      ? '操作未完成，请刷新核对后再重试'
      : '消息加载失败，请重试';

  void selectSection(InboxSection section) {
    if (section == state.section) return;
    _inboxRead?.cancel();
    _threadRead?.cancel();
    ++_threadVersion;
    state = state.copy(
      section: section,
      inbox: const MessageListState(),
      thread: const MessageListState(),
      clearSelection: true,
      clearWriteMessage: true,
    );
    unawaited(loadInbox());
  }

  Future<void> refresh() async {
    final generation = _generation;
    ref.invalidate(unreadMessagesProvider);
    await loadInbox(refresh: true);
    if (ref.mounted && generation == _generation && state.selected != null) {
      await loadThread(refresh: true);
    }
  }

  Future<void> loadInbox({bool refresh = false}) async {
    final old = refresh ? const MessageListState<InboxEntry>() : state.inbox;
    if (!refresh && (old.loading || !old.hasMore)) return;
    final repository = ref.read(messageRepositoryProvider);
    if (repository.accountScope == 'guest') return;
    final generation = _generation, version = ++_inboxVersion;
    final scope = repository.accountScope,
        epoch = repository.sessionEpoch,
        section = state.section;
    _inboxRead?.cancel();
    final read = _inboxRead = RequestCancellation();
    state = state.copy(
      inbox: MessageListState(
        items: old.items,
        cursor: old.cursor,
        hasMore: old.hasMore,
        loading: true,
      ),
    );
    try {
      final page = await repository.inbox(
        section,
        cursor: old.cursor,
        cancellation: read,
      );
      if (!_current(generation, scope, epoch) || version != _inboxVersion) {
        return;
      }
      final unique = {for (final item in old.items) item.id: item};
      for (final item in page.items) {
        unique[item.id] = item;
      }
      state = state.copy(
        selected: unique[state.selected?.id],
        inbox: MessageListState(
          items: List.unmodifiable(unique.values.take(500)),
          cursor: page.cursor,
          hasMore:
              page.hasMore &&
              page.items.isNotEmpty &&
              page.cursor != null &&
              page.cursor != old.cursor &&
              unique.length < 500,
        ),
      );
    } catch (error) {
      if (_current(generation, scope, epoch) && version == _inboxVersion) {
        state = state.copy(
          inbox: MessageListState(
            items: old.items,
            cursor: old.cursor,
            hasMore: old.hasMore,
            error: _error(error),
          ),
        );
      }
    }
  }

  void selectConversation(InboxEntry entry) {
    if (entry.sessionType == null || entry.id == state.selected?.id) return;
    _threadRead?.cancel();
    ++_threadVersion;
    state = state.copy(
      selected: entry,
      thread: const MessageListState(),
      clearWriteMessage: true,
    );
    unawaited(loadThread());
  }

  /// Opening a profile starts a local conversation; only Send writes remotely.
  bool openUserConversation(UserId id, {String? name, Uri? avatarUrl}) {
    final auth = ref.read(authControllerProvider);
    final repository = ref.read(messageRepositoryProvider);
    if (!id.isValid ||
        !auth.isSignedIn ||
        auth.mid == id.value ||
        repository.accountScope != 'user:${auth.mid}') {
      return false;
    }
    selectSection(InboxSection.private);
    final title = name?.trim() ?? '';
    final entry = state.inbox.items
        .where((entry) => entry.sessionType == 1 && entry.userId == id)
        .firstOrNull;
    selectConversation(
      entry ??
          InboxEntry(
            id: '1:${id.value}',
            title: title.isEmpty ? '用户 ${id.value}' : title,
            text: '',
            userId: id,
            avatarUrl: avatarUrl,
            sessionType: 1,
          ),
    );
    return true;
  }

  void closeConversation() {
    _threadRead?.cancel();
    ++_threadVersion;
    state = state.copy(
      clearSelection: true,
      thread: const MessageListState(),
      clearWriteMessage: true,
    );
  }

  Future<void> loadThread({bool refresh = false}) async {
    final entry = state.selected;
    if (entry == null) return;
    final old = refresh
        ? const MessageListState<PrivateMessage>()
        : state.thread;
    if (!refresh && (old.loading || !old.hasMore)) return;
    final repository = ref.read(messageRepositoryProvider);
    final generation = _generation, version = ++_threadVersion;
    final scope = repository.accountScope, epoch = repository.sessionEpoch;
    _threadRead?.cancel();
    final read = _threadRead = RequestCancellation();
    state = state.copy(
      thread: MessageListState(
        items: old.items,
        cursor: old.cursor,
        hasMore: old.hasMore,
        loading: true,
      ),
    );
    try {
      final page = await repository.thread(
        entry,
        cursor: old.cursor,
        cancellation: read,
      );
      if (!_current(generation, scope, epoch) || version != _threadVersion) {
        return;
      }
      final unique = {for (final item in old.items) item.id: item};
      for (final item in page.items) {
        unique[item.id] = item;
      }
      final sorted = unique.values.toList()
        ..sort(
          (a, b) =>
              BigInt.parse(a.sequence).compareTo(BigInt.parse(b.sequence)),
        );
      final bounded = sorted.length > 500
          ? sorted.sublist(sorted.length - 500)
          : sorted;
      state = state.copy(
        thread: MessageListState(
          items: List.unmodifiable(bounded),
          cursor: page.cursor,
          hasMore:
              page.hasMore &&
              page.items.isNotEmpty &&
              page.cursor != null &&
              page.cursor != old.cursor &&
              unique.length < 500,
        ),
      );
    } catch (error) {
      if (_current(generation, scope, epoch) && version == _threadVersion) {
        state = state.copy(
          thread: MessageListState(
            items: old.items,
            cursor: old.cursor,
            hasMore: old.hasMore,
            error: _error(error),
          ),
        );
      }
    }
  }

  Future<bool> send(String text) async {
    final entry = state.selected;
    if (entry == null || !entry.canSend || state.sending || state.markingRead) {
      return false;
    }
    if (text.trim().isEmpty || text.runes.length > 1000) {
      state = state.copy(writeMessage: '请输入 1–1000 字的消息');
      return false;
    }
    return _write(
      entry,
      send: true,
      action: (repository, cancellation) =>
          repository.sendText(entry, text, cancellation: cancellation),
    );
  }

  Future<bool> markRead() async {
    final entry = state.selected;
    if (entry == null ||
        state.markingRead ||
        state.sending ||
        state.thread.loading) {
      return false;
    }
    // Acknowledge only a sequence that was actually displayed, not the session's unseen latest one.
    final sequence = state.thread.items.lastOrNull?.sequence;
    if (sequence == null) return false;
    return _write(
      entry,
      send: false,
      action: (repository, cancellation) =>
          repository.markRead(entry, sequence, cancellation: cancellation),
    );
  }

  Future<bool> _write(
    InboxEntry entry, {
    required bool send,
    required Future<void> Function(MessageRepository, RequestCancellation)
    action,
  }) async {
    final repository = ref.read(messageRepositoryProvider);
    final generation = _generation,
        scope = repository.accountScope,
        epoch = repository.sessionEpoch;
    final cancellation = RequestCancellation();
    _writes.add(cancellation);
    state = state.copy(
      sending: send,
      markingRead: !send,
      clearWriteMessage: true,
    );
    try {
      await action(repository, cancellation);
      if (!_current(generation, scope, epoch)) return false;
      state = state.copy(
        sending: false,
        markingRead: false,
        writeMessage: state.selected?.id == entry.id
            ? send
                  ? '已发送'
                  : '已标为已读'
            : null,
        clearWriteMessage: state.selected?.id != entry.id,
      );
      ref.invalidate(unreadMessagesProvider);
      if (state.selected?.id == entry.id && send) {
        unawaited(loadThread(refresh: true));
      }
      if (state.section == InboxSection.private) {
        unawaited(loadInbox(refresh: true));
      }
      return true;
    } catch (error) {
      if (_current(generation, scope, epoch)) {
        state = state.copy(
          sending: false,
          markingRead: false,
          writeMessage: state.selected?.id == entry.id
              ? _error(error, write: true)
              : null,
        );
      }
      return false;
    } finally {
      _writes.remove(cancellation);
    }
  }
}
