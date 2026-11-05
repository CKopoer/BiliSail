import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/message_repository.dart';
import '../domain/message_management.dart';
import '../domain/message_composer.dart';

final messageRepositoryProvider = Provider<MessageRepository>(
  (ref) => throw UnimplementedError('MessageRepository'),
);
final unreadMessagesProvider =
    AsyncNotifierProvider.autoDispose<
      UnreadMessagesController,
      Map<InboxSection, int>
    >(UnreadMessagesController.new);

class UnreadMessagesController extends AsyncNotifier<Map<InboxSection, int>> {
  @override
  Future<Map<InboxSection, int>> build() async {
    final account = ref.watch(
      authControllerProvider.select((s) => (s.isSignedIn, s.mid)),
    );
    if (!account.$1) return const {};
    final cancellation = RequestCancellation();
    ref.onDispose(cancellation.cancel);
    return ref
        .watch(messageRepositoryProvider)
        .unread(cancellation: cancellation);
  }

  void markLikesRead() {
    final counts = state.value;
    if (counts == null || (counts[InboxSection.likes] ?? 0) == 0) return;
    // Like-list reads acknowledge the category. The Web client also clears
    // its local count instead of waiting for another unread response.
    state = AsyncData(Map.unmodifiable({...counts, InboxSection.likes: 0}));
  }
}

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
    this.managingIds = const {},
    this.supportsManagement = false,
    this.supportsRichComposition = false,
    this.emotePackages = const [],
    this.emotesLoading = false,
    this.emotesMessage,
  });
  final InboxSection section;
  final MessageListState<InboxEntry> inbox;
  final MessageListState<PrivateMessage> thread;
  final InboxEntry? selected;
  final bool sending, markingRead;
  final String? writeMessage;
  final Set<String> managingIds;
  final bool supportsManagement;
  final bool supportsRichComposition, emotesLoading;
  final List<MessageEmotePackage> emotePackages;
  final String? emotesMessage;
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
    Set<String>? managingIds,
    List<MessageEmotePackage>? emotePackages,
    bool? emotesLoading,
    String? emotesMessage,
    bool clearEmotesMessage = false,
  }) => MessagesState(
    section: section ?? this.section,
    inbox: inbox ?? this.inbox,
    thread: thread ?? this.thread,
    selected: clearSelection ? null : selected ?? this.selected,
    sending: sending ?? this.sending,
    markingRead: markingRead ?? this.markingRead,
    writeMessage: clearWriteMessage ? null : writeMessage ?? this.writeMessage,
    managingIds: managingIds ?? this.managingIds,
    supportsManagement: supportsManagement,
    supportsRichComposition: supportsRichComposition,
    emotePackages: emotePackages ?? this.emotePackages,
    emotesLoading: emotesLoading ?? this.emotesLoading,
    emotesMessage: clearEmotesMessage
        ? null
        : emotesMessage ?? this.emotesMessage,
  );
}

class MessagesController extends Notifier<MessagesState> {
  int _generation = 0, _inboxVersion = 0, _threadVersion = 0;
  RequestCancellation? _inboxRead, _threadRead;
  final Set<RequestCancellation> _writes = {};
  MessageListState<InboxEntry>? _systemReadAttempt;
  MessageListState<PrivateMessage>? _threadReadAttempt;
  (String, int)? _inboxAccount;
  (String, int)? _threadAccount;
  final Map<InboxSection, Map<InboxSection, int>> _readUnreadSnapshots = {};
  int _managementRevision = 0;
  final Map<String, ({int revision, bool? pinned, bool? muted, bool removed})>
  _managementChanges = {};
  final Map<String, int> _privateOrder = {};
  RequestCancellation? _emotesRead;
  int _emoteVersion = 0;
  (String, int)? _emoteAccount;
  final Map<String, Uri> _emoteLookup = {};

  bool get supportsManagement => state.supportsManagement;
  bool get supportsRichComposition => state.supportsRichComposition;

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
    return MessagesState(
      supportsManagement:
          ref.read(messageRepositoryProvider) is MessageManagementRepository,
      supportsRichComposition:
          ref.read(messageRepositoryProvider) is MessageComposeRepository,
    );
  }

  void _cancel() {
    _emotesRead?.cancel();
    _emoteAccount = null;
    _emoteLookup.clear();
    ++_emoteVersion;
    _systemReadAttempt = null;
    _threadReadAttempt = null;
    _inboxAccount = null;
    _threadAccount = null;
    _readUnreadSnapshots.clear();
    _managementChanges.clear();
    _privateOrder.clear();
    _managementRevision = 0;
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

  Future<Map<InboxSection, int>?> _unreadSnapshot() async {
    try {
      return await ref.read(unreadMessagesProvider.future);
    } catch (_) {
      // The shared provider retains the error. An unavailable count is not
      // evidence of a read transition and must not block the message list.
      return null;
    }
  }

  Future<void> _refreshUnreadAfterRead(
    InboxSection section,
    Future<Map<InboxSection, int>?> snapshot,
    int generation,
    String scope,
    int epoch,
  ) async {
    final counts = await snapshot;
    if (!_current(generation, scope, epoch) ||
        counts == null ||
        (counts[section] ?? 0) == 0 ||
        identical(_readUnreadSnapshots[section], counts)) {
      return;
    }
    // Rapid tab switches can finish against the same unread snapshot.
    // Each category needs only one reconciliation for that snapshot.
    _readUnreadSnapshots[section] = counts;
    if (section == InboxSection.likes) {
      ref.read(unreadMessagesProvider.notifier).markLikesRead();
    } else {
      ref.invalidate(unreadMessagesProvider);
    }
  }

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
    _threadAccount = null;
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
    await loadInbox(refresh: true);
    if (!ref.mounted || generation != _generation) return;
    ref.invalidate(unreadMessagesProvider);
    if (state.selected != null) {
      await loadThread(refresh: true);
    }
  }

  Future<void> loadInbox({bool refresh = false}) async {
    final old = refresh ? const MessageListState<InboxEntry>() : state.inbox;
    if (!refresh && (old.loading || !old.hasMore)) return;
    final repository = ref.read(messageRepositoryProvider);
    if (repository.accountScope == 'guest') return;
    final generation = _generation, version = ++_inboxVersion;
    final managementRevision = _managementRevision;
    final scope = repository.accountScope,
        epoch = repository.sessionEpoch,
        section = state.section;
    _inboxRead?.cancel();
    final read = _inboxRead = RequestCancellation();
    final unreadBefore =
        section != InboxSection.private && section != InboxSection.system
        ? _unreadSnapshot()
        : null;
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
        unique[item.id] = _enrichEntry(item);
      }
      if (section == InboxSection.private) {
        if (refresh) _privateOrder.clear();
        for (final id in unique.keys) {
          if (_privateOrder.length < 500) {
            _privateOrder.putIfAbsent(id, () => _privateOrder.length);
          }
        }
        _applyManagementChanges(unique, managementRevision);
      }
      _inboxAccount = (scope, epoch);
      state = state.copy(
        selected: unique[state.selected?.id],
        inbox: MessageListState(
          items: List.unmodifiable(
            (section == InboxSection.private
                    ? _sortConversations(unique.values)
                    : unique.values)
                .take(500),
          ),
          cursor: page.cursor,
          hasMore:
              page.hasMore &&
              page.items.isNotEmpty &&
              page.cursor != null &&
              page.cursor != old.cursor &&
              unique.length < 500,
        ),
      );
      if (supportsRichComposition &&
          page.items.any(
            (item) => item.text.contains('[') || item.sourceText.contains('['),
          )) {
        unawaited(loadEmotes());
      }
      // These reads acknowledge notifications, but revisiting a read category
      // must not refresh the account badge.
      if (unreadBefore != null &&
          (page.items.isNotEmpty || section == InboxSection.likes)) {
        await _refreshUnreadAfterRead(
          section,
          unreadBefore,
          generation,
          scope,
          epoch,
        );
      }
    } catch (error) {
      if (_current(generation, scope, epoch) && version == _inboxVersion) {
        final restored = {for (final item in old.items) item.id: item};
        if (section == InboxSection.private) {
          _applyManagementChanges(restored, managementRevision);
        }
        state = state.copy(
          inbox: MessageListState(
            items: section == InboxSection.private
                ? List.unmodifiable(_sortConversations(restored.values))
                : old.items,
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
    _threadAccount = null;
    state = state.copy(
      selected: entry,
      thread: const MessageListState(),
      clearWriteMessage: true,
    );
    unawaited(loadThread());
    if (supportsRichComposition) unawaited(loadEmotes());
  }

  /// Opening a profile reuses a conversation or creates a local empty one.
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
    _threadAccount = null;
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
        unique[item.id] = _enrichMessage(item);
      }
      final sorted = unique.values.toList()
        ..sort(
          (a, b) =>
              BigInt.parse(a.sequence).compareTo(BigInt.parse(b.sequence)),
        );
      final bounded = sorted.length > 500
          ? sorted.sublist(sorted.length - 500)
          : sorted;
      _threadAccount = (scope, epoch);
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

  Future<void> loadEmotes() async {
    final repository = ref.read(messageRepositoryProvider);
    if (repository is! MessageComposeRepository ||
        !repository.accountScope.startsWith('user:')) {
      return;
    }
    final account = (repository.accountScope, repository.sessionEpoch);
    if (_emoteAccount == account &&
        (state.emotesLoading || state.emotePackages.isNotEmpty)) {
      return;
    }
    if (_emoteAccount != account) {
      _emoteLookup.clear();
      state = state.copy(
        emotePackages: const [],
        emotesLoading: false,
        clearEmotesMessage: true,
      );
    }
    _emotesRead?.cancel();
    final cancellation = _emotesRead = RequestCancellation();
    final version = ++_emoteVersion, generation = _generation;
    _emoteAccount = account;
    state = state.copy(emotesLoading: true, clearEmotesMessage: true);
    try {
      final packages = await (repository as MessageComposeRepository).emotes(
        cancellation: cancellation,
      );
      if (!_current(generation, account.$1, account.$2) ||
          version != _emoteVersion) {
        return;
      }
      for (final package in packages.take(50)) {
        for (final item in package.items.take(200)) {
          if (item.imageUrl case final url?
              when item.text.isNotEmpty &&
                  item.text.length <= 100 &&
                  _emoteLookup.length < 2000) {
            _emoteLookup[item.text] = url;
          }
        }
      }
      final inbox = state.inbox, thread = state.thread;
      final enrichedInbox = MessageListState<InboxEntry>(
        items: List.unmodifiable(inbox.items.map(_enrichEntry)),
        cursor: inbox.cursor,
        hasMore: inbox.hasMore,
        loading: inbox.loading,
        error: inbox.error,
      );
      final enrichedThread = MessageListState<PrivateMessage>(
        items: List.unmodifiable(thread.items.map(_enrichMessage)),
        cursor: thread.cursor,
        hasMore: thread.hasMore,
        loading: thread.loading,
        error: thread.error,
      );
      if (identical(_systemReadAttempt, inbox)) {
        _systemReadAttempt = enrichedInbox;
      }
      if (identical(_threadReadAttempt, thread)) {
        _threadReadAttempt = enrichedThread;
      }
      state = state.copy(
        emotePackages: List.unmodifiable(packages),
        emotesLoading: false,
        emotesMessage: packages.isEmpty ? '暂无可用表情' : null,
        clearEmotesMessage: packages.isNotEmpty,
        selected: switch (state.selected) {
          final selected? => _enrichEntry(selected),
          _ => null,
        },
        inbox: enrichedInbox,
        thread: enrichedThread,
      );
    } catch (error) {
      if (_current(generation, account.$1, account.$2) &&
          version == _emoteVersion) {
        state = state.copy(emotesLoading: false, emotesMessage: _error(error));
      }
    } finally {
      if (ref.mounted &&
          generation == _generation &&
          version == _emoteVersion) {
        _emotesRead = null;
        if (state.emotesLoading) state = state.copy(emotesLoading: false);
      }
    }
  }

  Map<String, Uri>? _emotesFor(String text, Map<String, Uri> original) {
    if (_emoteLookup.isEmpty) return null;
    final emotes = {...original};
    for (final entry in _emoteLookup.entries) {
      if (emotes.length >= 100) break;
      if (text.contains(entry.key)) {
        emotes.putIfAbsent(entry.key, () => entry.value);
      }
    }
    return emotes.length == original.length ? null : emotes;
  }

  InboxEntry _enrichEntry(InboxEntry entry) {
    final emotes = _emotesFor(
      '${entry.text}\n${entry.sourceText}',
      entry.emotes,
    );
    return emotes == null ? entry : entry.withEmotes(emotes);
  }

  PrivateMessage _enrichMessage(PrivateMessage message) {
    if (message.kind == MessageContentKind.withdrawn) return message;
    final emotes = _emotesFor(
      '${message.text}\n${message.title}\n${message.subtitle}\n${message.cards.map((card) => '${card.title}\n${card.description}').join('\n')}',
      message.emotes,
    );
    return emotes == null ? message : message.withEmotes(emotes);
  }

  Future<bool> sendImage(MessageLocalImage image) async {
    final entry = state.selected;
    final repository = ref.read(messageRepositoryProvider);
    if (repository is! MessageComposeRepository ||
        entry == null ||
        !entry.canSend ||
        state.sending ||
        state.markingRead ||
        state.managingIds.contains(entry.id)) {
      return false;
    }
    return _write(
      entry,
      send: true,
      action: (repository, cancellation) =>
          (repository as MessageComposeRepository).sendImage(
            entry,
            image,
            cancellation: cancellation,
          ),
    );
  }

  Future<bool> send(String text) async {
    final entry = state.selected;
    if (entry == null ||
        !entry.canSend ||
        state.sending ||
        state.markingRead ||
        state.managingIds.contains(entry.id)) {
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

  Future<bool> markRead({bool automatic = false}) async {
    final entry = state.selected;
    final thread = state.thread;
    final repository = ref.read(messageRepositoryProvider);
    if (entry == null ||
        state.section != InboxSection.private ||
        state.markingRead ||
        state.sending ||
        state.managingIds.contains(entry.id) ||
        thread.loading ||
        thread.error != null ||
        _threadAccount != (repository.accountScope, repository.sessionEpoch) ||
        (automatic &&
            (entry.unread <= 0 || identical(thread, _threadReadAttempt)))) {
      return false;
    }
    // Acknowledge only a sequence that was actually displayed, not the session's unseen latest one.
    final sequence = thread.items.lastOrNull?.sequence;
    if (sequence == null) return false;
    // Rebuilds must not replay a failed or uncertain automatic write.
    _threadReadAttempt = thread;
    return _write(
      entry,
      send: false,
      notifySuccess: !automatic,
      action: (repository, cancellation) =>
          repository.markRead(entry, sequence, cancellation: cancellation),
    );
  }

  Future<bool> markSystemNotificationsRead() async {
    final inbox = state.inbox;
    final repository = ref.read(messageRepositoryProvider);
    if (state.section != InboxSection.system ||
        inbox.loading ||
        inbox.error != null ||
        identical(inbox, _systemReadAttempt) ||
        state.sending ||
        state.markingRead ||
        _inboxAccount != (repository.accountScope, repository.sessionEpoch)) {
      return false;
    }
    BigInt? newest;
    for (final entry in inbox.items) {
      final cursor = BigInt.tryParse(entry.readCursor ?? '');
      if (cursor != null &&
          cursor > BigInt.zero &&
          (newest == null || cursor > newest)) {
        newest = cursor;
      }
    }
    if (newest == null) return false;
    // A failed/uncertain write may be tried again only after a new list load.
    // Rebuilds and unread-count updates must not resubmit the same snapshot.
    _systemReadAttempt = inbox;
    final generation = _generation,
        scope = repository.accountScope,
        epoch = repository.sessionEpoch;
    final cancellation = RequestCancellation();
    final unreadBefore = _unreadSnapshot();
    _writes.add(cancellation);
    state = state.copy(markingRead: true, clearWriteMessage: true);
    try {
      await repository.markSystemNotificationsRead(
        newest.toString(),
        cancellation: cancellation,
      );
      if (!_current(generation, scope, epoch)) return false;
      state = state.copy(markingRead: false);
      await _refreshUnreadAfterRead(
        InboxSection.system,
        unreadBefore,
        generation,
        scope,
        epoch,
      );
      return true;
    } catch (error) {
      if (_current(generation, scope, epoch)) {
        state = state.copy(
          markingRead: false,
          writeMessage:
              state.section == InboxSection.system &&
                  identical(state.inbox, inbox)
              ? _error(error, write: true)
              : null,
        );
      }
      return false;
    } finally {
      _writes.remove(cancellation);
    }
  }

  void _applyManagementChanges(Map<String, InboxEntry> entries, int revision) {
    // Both successful and failed old reads must retain newer confirmed writes.
    for (final change in _managementChanges.entries) {
      if (change.value.revision <= revision) continue;
      final item = entries[change.key];
      if (change.value.removed) {
        entries.remove(change.key);
      } else if (item != null) {
        entries[change.key] = _withFlags(
          item,
          pinned: change.value.pinned,
          muted: change.value.muted,
        );
      }
    }
  }

  List<InboxEntry> _sortConversations(Iterable<InboxEntry> entries) {
    final sorted = entries.toList();
    sorted.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return (_privateOrder[a.id] ?? 500).compareTo(_privateOrder[b.id] ?? 500);
    });
    return sorted;
  }

  InboxEntry _withFlags(InboxEntry entry, {bool? pinned, bool? muted}) =>
      InboxEntry(
        id: entry.id,
        title: entry.title,
        text: entry.text,
        userId: entry.userId,
        avatarUrl: entry.avatarUrl,
        time: entry.time,
        targetUrl: entry.targetUrl,
        sessionType: entry.sessionType,
        system: entry.system,
        unread: entry.unread,
        lastSequence: entry.lastSequence,
        readCursor: entry.readCursor,
        sourceText: entry.sourceText,
        sourceTitle: entry.sourceTitle,
        sourceImageUrl: entry.sourceImageUrl,
        pinned: pinned ?? entry.pinned,
        muted: muted ?? entry.muted,
        emotes: entry.emotes,
        replyContext: entry.replyContext,
      );

  Future<bool> setPinned(InboxEntry entry, bool pinned) => _manage(
    entry,
    pinned: pinned,
    action: (repository, cancellation) =>
        repository.setPinned(entry, pinned, cancellation: cancellation),
  );

  Future<bool> setMuted(InboxEntry entry, bool muted) => _manage(
    entry,
    muted: muted,
    action: (repository, cancellation) =>
        repository.setMuted(entry, muted, cancellation: cancellation),
  );

  Future<bool> removeConversation(InboxEntry entry) => _manage(
    entry,
    removed: true,
    action: (repository, cancellation) =>
        repository.removeConversation(entry, cancellation: cancellation),
  );

  Future<bool> _manage(
    InboxEntry entry, {
    bool? pinned,
    bool? muted,
    bool removed = false,
    required Future<void> Function(
      MessageManagementRepository,
      RequestCancellation,
    )
    action,
  }) async {
    final repository = ref.read(messageRepositoryProvider);
    final account = (repository.accountScope, repository.sessionEpoch);
    final currentEntry =
        (_inboxAccount == account &&
            state.section == InboxSection.private &&
            state.inbox.items.any((item) => identical(item, entry))) ||
        (_threadAccount == account && identical(state.selected, entry));
    if (repository is! MessageManagementRepository ||
        !currentEntry ||
        !entry.canSend ||
        state.managingIds.contains(entry.id) ||
        (state.selected?.id == entry.id &&
            (state.sending || state.markingRead))) {
      return false;
    }
    final generation = _generation,
        scope = repository.accountScope,
        epoch = repository.sessionEpoch;
    final cancellation = RequestCancellation();
    _writes.add(cancellation);
    state = state.copy(
      managingIds: Set.unmodifiable({...state.managingIds, entry.id}),
      clearWriteMessage: true,
    );
    try {
      await action(repository as MessageManagementRepository, cancellation);
      if (!_current(generation, scope, epoch)) return false;
      final previous = _managementChanges[entry.id];
      _managementChanges.remove(entry.id);
      _managementChanges[entry.id] = (
        revision: ++_managementRevision,
        pinned: pinned ?? previous?.pinned,
        muted: muted ?? previous?.muted,
        removed: removed,
      );
      if (_managementChanges.length > 500) {
        _managementChanges.remove(_managementChanges.keys.first);
      }
      final selected = state.selected;
      final clearSelection = removed && selected?.id == entry.id;
      if (clearSelection) {
        _threadRead?.cancel();
        ++_threadVersion;
        _threadAccount = null;
      }
      final inbox = state.inbox;
      state = state.copy(
        selected: selected?.id == entry.id && selected != null
            ? _withFlags(selected, pinned: pinned, muted: muted)
            : null,
        clearSelection: clearSelection,
        thread: clearSelection ? const MessageListState() : null,
        inbox: state.section == InboxSection.private
            ? MessageListState(
                items: List.unmodifiable(
                  _sortConversations([
                    for (final item in inbox.items)
                      if (item.id != entry.id)
                        item
                      else if (!removed)
                        _withFlags(item, pinned: pinned, muted: muted),
                  ]),
                ),
                cursor: inbox.cursor,
                hasMore: inbox.hasMore,
                loading: inbox.loading,
                error: inbox.error,
              )
            : null,
        writeMessage: state.section == InboxSection.private
            ? removed
                  ? '已移除会话'
                  : pinned != null
                  ? pinned
                        ? '已置顶会话'
                        : '已取消置顶'
                  : muted == true
                  ? '已开启免打扰'
                  : '已关闭免打扰'
            : null,
        clearWriteMessage: state.section != InboxSection.private,
      );
      if (removed && entry.unread > 0) ref.invalidate(unreadMessagesProvider);
      return true;
    } catch (error) {
      if (_current(generation, scope, epoch) &&
          state.section == InboxSection.private) {
        state = state.copy(writeMessage: _error(error, write: true));
      }
      return false;
    } finally {
      _writes.remove(cancellation);
      if (ref.mounted && generation == _generation) {
        state = state.copy(
          managingIds: Set.unmodifiable(
            {...state.managingIds}..remove(entry.id),
          ),
        );
      }
    }
  }

  Future<bool> _write(
    InboxEntry entry, {
    required bool send,
    bool notifySuccess = true,
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
        writeMessage: state.selected?.id == entry.id && notifySuccess
            ? send
                  ? '已发送'
                  : '已标为已读'
            : null,
        clearWriteMessage: state.selected?.id != entry.id || !notifySuccess,
      );
      if (!send && entry.unread > 0) {
        ref.invalidate(unreadMessagesProvider);
      }
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
