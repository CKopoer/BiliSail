import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/message_center_repository.dart';
import '../domain/message_repository.dart';

final messageCenterRepositoryProvider = Provider<MessageCenterRepository?>(
  (ref) => null,
);
final messageCenterControllerProvider =
    NotifierProvider.autoDispose<MessageCenterController, MessageCenterState>(
      MessageCenterController.new,
    );

final class MessageCenterState {
  const MessageCenterState({
    this.settings,
    this.chat,
    this.people = const [],
    this.peopleKind = MessagePeopleKind.fans,
    this.peopleHasMore = true,
    this.loadingSettings = false,
    this.loadingChat = false,
    this.loadingPeople = false,
    this.busy = false,
    this.blockedWords = const [],
    this.loadingWords = false,
    this.blockedWordLimit = 200,
    this.blockedWordLength = 20,
    this.error,
    this.message,
    this.assistants = const [],
    this.assistantKind = MessageAssistantKind.up,
    this.assistantsHasMore = true,
    this.loadingAssistants = false,
  });
  final MessageCenterSettings? settings;
  final ChatMessageSettings? chat;
  final List<MessagePerson> people;
  final MessagePeopleKind peopleKind;
  final bool peopleHasMore,
      loadingSettings,
      loadingChat,
      loadingPeople,
      busy,
      loadingWords;
  final List<String> blockedWords;
  final int blockedWordLimit, blockedWordLength;
  final String? error, message;
  final List<InboxEntry> assistants;
  final MessageAssistantKind assistantKind;
  final bool assistantsHasMore, loadingAssistants;
  MessageCenterState copy({
    MessageCenterSettings? settings,
    ChatMessageSettings? chat,
    bool clearChat = false,
    List<MessagePerson>? people,
    MessagePeopleKind? peopleKind,
    bool? peopleHasMore,
    bool? loadingSettings,
    bool? loadingChat,
    bool? loadingPeople,
    bool? busy,
    List<String>? blockedWords,
    bool? loadingWords,
    int? blockedWordLimit,
    int? blockedWordLength,
    String? error,
    String? message,
    bool clearError = false,
    bool clearMessage = false,
    List<InboxEntry>? assistants,
    MessageAssistantKind? assistantKind,
    bool? assistantsHasMore,
    bool? loadingAssistants,
  }) => MessageCenterState(
    settings: settings ?? this.settings,
    chat: clearChat ? null : chat ?? this.chat,
    people: people ?? this.people,
    peopleKind: peopleKind ?? this.peopleKind,
    peopleHasMore: peopleHasMore ?? this.peopleHasMore,
    loadingSettings: loadingSettings ?? this.loadingSettings,
    loadingChat: loadingChat ?? this.loadingChat,
    loadingPeople: loadingPeople ?? this.loadingPeople,
    busy: busy ?? this.busy,
    blockedWords: blockedWords ?? this.blockedWords,
    loadingWords: loadingWords ?? this.loadingWords,
    blockedWordLimit: blockedWordLimit ?? this.blockedWordLimit,
    blockedWordLength: blockedWordLength ?? this.blockedWordLength,
    error: clearError ? null : error ?? this.error,
    message: clearMessage ? null : message ?? this.message,
    assistants: assistants ?? this.assistants,
    assistantKind: assistantKind ?? this.assistantKind,
    assistantsHasMore: assistantsHasMore ?? this.assistantsHasMore,
    loadingAssistants: loadingAssistants ?? this.loadingAssistants,
  );
}

class MessageCenterController extends Notifier<MessageCenterState> {
  int _generation = 0,
      _settingsVersion = 0,
      _wordsVersion = 0,
      _peopleVersion = 0,
      _chatVersion = 0,
      _assistantVersion = 0,
      _assistantPages = 0;
  final Set<RequestCancellation> _operations = {};
  RequestCancellation? _settingsRead,
      _wordsRead,
      _peopleRead,
      _chatRead,
      _assistantRead;
  String? _peopleCursor, _assistantCursor;
  (String, int)? _chatAccount;
  (String, int)? _settingsAccount, _wordsAccount, _peopleAccount;
  InboxEntry? _chatEntry;
  String? _chatRequestedId;
  bool _wordsLoaded = false;

  @override
  MessageCenterState build() {
    ref.watch(authControllerProvider.select((s) => (s.isSignedIn, s.mid)));
    ref.watch(messageCenterRepositoryProvider);
    _cancel();
    ++_generation;
    ref.onDispose(() {
      ++_generation;
      _cancel();
    });
    return const MessageCenterState();
  }

  void _cancel() {
    for (final op in _operations) {
      op.cancel();
    }
    _operations.clear();
    _peopleCursor = null;
    _assistantCursor = null;
    _assistantPages = 0;
    _chatAccount = null;
    _settingsAccount = null;
    _wordsAccount = null;
    _peopleAccount = null;
    _chatEntry = null;
    _chatRequestedId = null;
    _wordsLoaded = false;
  }

  bool _current(
    int generation,
    MessageCenterRepository repo,
    (String, int) account,
  ) =>
      ref.mounted &&
      generation == _generation &&
      identical(ref.read(messageCenterRepositoryProvider), repo) &&
      (repo.accountScope, repo.sessionEpoch) == account;
  String? _error(Object error, {bool write = false}) => error is AppFailure
      ? error.kind == AppFailureKind.cancelled
            ? null
            : write &&
                  (error.kind == AppFailureKind.network ||
                      error.kind == AppFailureKind.timeout)
            ? '操作结果尚未确认，请刷新核对后再决定是否重试'
            : error.message
      : write
      ? '操作未完成，请刷新核对后再操作'
      : '消息功能加载失败，请重试';

  Future<void> loadSettings() async {
    final repo = ref.read(messageCenterRepositoryProvider);
    if (repo == null) return;
    final generation = _generation,
        version = ++_settingsVersion,
        account = (repo.accountScope, repo.sessionEpoch);
    _settingsRead?.cancel();
    final read = _settingsRead = RequestCancellation();
    _operations.add(read);
    state = state.copy(
      loadingSettings: true,
      clearError: true,
      clearMessage: true,
    );
    try {
      final result = await repo.settings(cancellation: read);
      if (_current(generation, repo, account) && version == _settingsVersion) {
        _settingsAccount = account;
        state = state.copy(settings: result, loadingSettings: false);
      }
    } catch (error) {
      if (_current(generation, repo, account) && version == _settingsVersion) {
        state = state.copy(loadingSettings: false, error: _error(error));
      }
    } finally {
      _operations.remove(read);
    }
  }

  Future<bool> setSetting(MessageSetting setting, int value) async {
    final repository = ref.read(messageCenterRepositoryProvider);
    if (repository == null ||
        _settingsAccount !=
            (repository.accountScope, repository.sessionEpoch)) {
      return false;
    }
    if (!setting.options.containsKey(value) ||
        !(state.settings?.values.containsKey(setting) ?? false)) {
      return false;
    }
    return _write(
      (repo, cancellation) =>
          repo.setSetting(setting, value, cancellation: cancellation),
      success: () {
        ++_settingsVersion;
        _settingsRead?.cancel();
        state = state.copy(
          settings: MessageCenterSettings(
            Map.unmodifiable({...?state.settings?.values, setting: value}),
          ),
          loadingSettings: false,
          message: '设置已保存',
        );
      },
    );
  }

  Future<void> loadWords() async {
    final repo = ref.read(messageCenterRepositoryProvider);
    if (repo == null) return;
    final generation = _generation,
        version = ++_wordsVersion,
        account = (repo.accountScope, repo.sessionEpoch);
    _wordsRead?.cancel();
    final read = _wordsRead = RequestCancellation();
    _operations.add(read);
    state = state.copy(
      loadingWords: true,
      clearError: true,
      clearMessage: true,
    );
    try {
      final result = await repo.blockedWords(cancellation: read);
      if (_current(generation, repo, account) && version == _wordsVersion) {
        _wordsLoaded = true;
        _wordsAccount = account;
        state = state.copy(
          blockedWords: result.words,
          blockedWordLimit: result.limit,
          blockedWordLength: result.wordLength,
          loadingWords: false,
        );
      }
    } catch (error) {
      if (_current(generation, repo, account) && version == _wordsVersion) {
        state = state.copy(loadingWords: false, error: _error(error));
      }
    } finally {
      _operations.remove(read);
    }
  }

  Future<bool> addBlockedWord(String raw) async {
    final repository = ref.read(messageCenterRepositoryProvider);
    if (repository == null ||
        _wordsAccount != (repository.accountScope, repository.sessionEpoch)) {
      return false;
    }
    final word = raw.trim();
    if (!_wordsLoaded ||
        word.isEmpty ||
        word.runes.length > state.blockedWordLength ||
        state.blockedWords.length >= state.blockedWordLimit ||
        state.blockedWords.contains(word)) {
      state = state.copy(
        error:
            '请输入不重复的屏蔽词，最多 ${state.blockedWordLength} 字、${state.blockedWordLimit} 个',
      );
      return false;
    }
    return _write(
      (repo, cancellation) =>
          repo.addBlockedWord(word, cancellation: cancellation),
      success: () {
        ++_wordsVersion;
        _wordsRead?.cancel();
        state = state.copy(
          blockedWords: List.unmodifiable([word, ...state.blockedWords]),
          loadingWords: false,
          message: '已添加屏蔽词',
        );
      },
    );
  }

  Future<bool> removeBlockedWord(String word) async {
    final repository = ref.read(messageCenterRepositoryProvider);
    if (repository == null ||
        _wordsAccount != (repository.accountScope, repository.sessionEpoch)) {
      return false;
    }
    if (!_wordsLoaded || !state.blockedWords.contains(word)) return false;
    return _write(
      (repo, cancellation) =>
          repo.removeBlockedWord(word, cancellation: cancellation),
      success: () {
        ++_wordsVersion;
        _wordsRead?.cancel();
        state = state.copy(
          blockedWords: List.unmodifiable(
            state.blockedWords.where((e) => e != word),
          ),
          loadingWords: false,
          message: '已删除屏蔽词',
        );
      },
    );
  }

  Future<void> loadPeople(
    MessagePeopleKind kind, {
    bool refresh = false,
  }) async {
    final repo = ref.read(messageCenterRepositoryProvider);
    if (repo == null) return;
    final reset = refresh || kind != state.peopleKind;
    if (!reset && (state.loadingPeople || !state.peopleHasMore)) return;
    final generation = _generation,
        version = ++_peopleVersion,
        account = (repo.accountScope, repo.sessionEpoch);
    final old = reset ? const <MessagePerson>[] : state.people;
    final cursor = reset ? null : _peopleCursor;
    _peopleRead?.cancel();
    final read = _peopleRead = RequestCancellation();
    _operations.add(read);
    state = state.copy(
      peopleKind: kind,
      people: old,
      loadingPeople: true,
      clearError: true,
      clearMessage: true,
    );
    try {
      final result = await repo.people(
        kind,
        cursor: cursor,
        cancellation: read,
      );
      if (_current(generation, repo, account) && version == _peopleVersion) {
        final unique = {
          for (final item in old) item.id: item,
          for (final item in result.items) item.id: item,
        };
        _peopleCursor = result.cursor;
        _peopleAccount = account;
        state = state.copy(
          people: List.unmodifiable(unique.values.take(500)),
          peopleHasMore:
              result.hasMore &&
              result.cursor != null &&
              result.cursor != cursor &&
              result.items.isNotEmpty &&
              unique.length < 500,
          loadingPeople: false,
        );
      }
    } catch (error) {
      if (_current(generation, repo, account) && version == _peopleVersion) {
        state = state.copy(loadingPeople: false, error: _error(error));
      }
    } finally {
      _operations.remove(read);
    }
  }

  Future<bool> unblockPerson(MessagePerson person) async {
    final repository = ref.read(messageCenterRepositoryProvider);
    if (repository == null ||
        _peopleAccount != (repository.accountScope, repository.sessionEpoch) ||
        state.peopleKind != MessagePeopleKind.blocked ||
        !state.people.any((item) => identical(item, person))) {
      return false;
    }
    final entry = InboxEntry(
      id: '1:${person.id.value}',
      title: person.name,
      text: '',
      userId: person.id,
      sessionType: 1,
    );
    return _write(
      (repo, cancellation) =>
          repo.setBlocked(entry, false, cancellation: cancellation),
      success: () {
        ++_peopleVersion;
        _peopleRead?.cancel();
        state = state.copy(
          people: List.unmodifiable(
            state.people.where((item) => item.id != person.id),
          ),
          loadingPeople: false,
          message: '已移出黑名单',
        );
      },
    );
  }

  Future<void> loadAssistants(
    MessageAssistantKind kind, {
    bool refresh = false,
  }) async {
    final repo = ref.read(messageCenterRepositoryProvider);
    if (repo == null) return;
    final reset = refresh || kind != state.assistantKind;
    if (!reset && (state.loadingAssistants || !state.assistantsHasMore)) return;
    final generation = _generation,
        version = ++_assistantVersion,
        account = (repo.accountScope, repo.sessionEpoch);
    final old = reset ? const <InboxEntry>[] : state.assistants;
    final cursor = reset ? null : _assistantCursor;
    if (reset) _assistantPages = 0;
    _assistantRead?.cancel();
    final read = _assistantRead = RequestCancellation();
    _operations.add(read);
    state = state.copy(
      assistantKind: kind,
      assistants: old,
      loadingAssistants: true,
      clearError: true,
      clearMessage: true,
    );
    try {
      final result = await repo.assistantSessions(
        kind,
        cursor: cursor,
        cancellation: read,
      );
      if (_current(generation, repo, account) && version == _assistantVersion) {
        final unique = {
          for (final item in old) item.id: item,
          for (final item in result.items) item.id: item,
        };
        _assistantCursor = result.cursor;
        ++_assistantPages;
        state = state.copy(
          assistants: List.unmodifiable(unique.values.take(500)),
          assistantsHasMore:
              result.hasMore &&
              result.cursor != null &&
              result.cursor != cursor &&
              unique.length < 500 &&
              _assistantPages < 10,
          loadingAssistants: false,
        );
      }
    } catch (error) {
      if (_current(generation, repo, account) && version == _assistantVersion) {
        state = state.copy(loadingAssistants: false, error: _error(error));
      }
    } finally {
      _operations.remove(read);
    }
  }

  Future<void> loadChat(InboxEntry entry) async {
    final repo = ref.read(messageCenterRepositoryProvider);
    if (repo == null || !entry.canSend) return;
    final generation = _generation,
        version = ++_chatVersion,
        account = (repo.accountScope, repo.sessionEpoch);
    _chatRead?.cancel();
    final read = _chatRead = RequestCancellation();
    _operations.add(read);
    _chatAccount = null;
    _chatEntry = null;
    _chatRequestedId = entry.id;
    state = state.copy(
      loadingChat: true,
      clearChat: true,
      clearError: true,
      clearMessage: true,
    );
    try {
      final result = await repo.chatSettings(entry, cancellation: read);
      if (_current(generation, repo, account) && version == _chatVersion) {
        _chatAccount = account;
        _chatEntry = entry;
        state = state.copy(chat: result, loadingChat: false);
      }
    } catch (error) {
      if (_current(generation, repo, account) && version == _chatVersion) {
        state = state.copy(loadingChat: false, error: _error(error));
      }
    } finally {
      _operations.remove(read);
    }
  }

  bool _chatCurrent(InboxEntry entry) {
    final repo = ref.read(messageCenterRepositoryProvider);
    return repo != null &&
        _chatAccount == (repo.accountScope, repo.sessionEpoch) &&
        _chatEntry?.id == entry.id &&
        _chatEntry?.userId == entry.userId &&
        entry.canSend &&
        state.chat?.entryId == entry.id;
  }

  void _updateChat(
    InboxEntry entry,
    ChatMessageSettings before, {
    bool? contentPush,
    bool? blocked,
  }) {
    if (_chatRequestedId != entry.id) return;
    final repo = ref.read(messageCenterRepositoryProvider);
    if (repo == null) return;
    ++_chatVersion;
    _chatRead?.cancel();
    _chatEntry = entry;
    _chatAccount = (repo.accountScope, repo.sessionEpoch);
    final current = state.chat;
    final old = current != null && current.entryId == entry.id
        ? current
        : before;
    state = state.copy(
      chat: ChatMessageSettings(
        entryId: entry.id,
        contentPush: contentPush ?? old.contentPush,
        showContentPush: old.showContentPush,
        blocked: blocked ?? old.blocked,
      ),
      loadingChat: false,
      message: contentPush != null
          ? '内容推送设置已保存'
          : blocked == true
          ? '已加入黑名单'
          : '已移出黑名单',
    );
  }

  Future<bool> setContentPush(InboxEntry entry, bool enabled) async {
    if (!_chatCurrent(entry) || state.chat?.showContentPush != true) {
      return false;
    }
    final before = state.chat;
    if (before == null) return false;
    return _write(
      (repo, cancellation) =>
          repo.setContentPush(entry, enabled, cancellation: cancellation),
      success: () => _updateChat(entry, before, contentPush: enabled),
    );
  }

  Future<bool> setBlocked(InboxEntry entry, bool blocked) async {
    if (!_chatCurrent(entry)) return false;
    final before = state.chat;
    if (before == null) return false;
    return _write(
      (repo, cancellation) =>
          repo.setBlocked(entry, blocked, cancellation: cancellation),
      success: () => _updateChat(entry, before, blocked: blocked),
    );
  }

  Future<bool> reportConversation(
    InboxEntry entry,
    int reason,
    String text,
  ) async {
    if (!_chatCurrent(entry) ||
        reason < 0 ||
        reason > 6 ||
        text.trim().isEmpty ||
        text.runes.length > 160) {
      return false;
    }
    return _write(
      (repo, cancellation) => repo.reportConversation(
        entry,
        reason,
        text.trim(),
        cancellation: cancellation,
      ),
      success: () => state = state.copy(message: '举报已提交'),
    );
  }

  Future<MarkPrivateReadResult?> markAllPrivateRead(
    List<InboxEntry> entries,
  ) async {
    if (entries.isEmpty || entries.length > 500) return null;
    MarkPrivateReadResult? result;
    final ok = await _write((repo, cancellation) async {
      result = await repo.markAllPrivateRead(
        List.unmodifiable(entries),
        cancellation: cancellation,
      );
    }, success: () => state = state.copy(message: result?.summary));
    return ok ? result : null;
  }

  Future<ClearConversationsResult?> clearConversations(
    List<InboxEntry> entries,
  ) async {
    if (entries.isEmpty ||
        entries.length > 500 ||
        entries.any((e) => !e.canSend)) {
      return null;
    }
    ClearConversationsResult? result;
    final ok = await _write((repo, cancellation) async {
      result = await repo.clearConversations(
        List.unmodifiable(entries),
        cancellation: cancellation,
      );
    }, success: () => state = state.copy(message: result?.summary));
    return ok ? result : null;
  }

  Future<bool> _write(
    Future<void> Function(MessageCenterRepository, RequestCancellation)
    action, {
    required void Function() success,
  }) async {
    final repo = ref.read(messageCenterRepositoryProvider);
    if (repo == null || state.busy) return false;
    final generation = _generation,
        account = (repo.accountScope, repo.sessionEpoch);
    final write = RequestCancellation();
    _operations.add(write);
    state = state.copy(busy: true, clearError: true, clearMessage: true);
    try {
      await action(repo, write);
      if (!_current(generation, repo, account)) return false;
      success();
      return true;
    } catch (error) {
      if (_current(generation, repo, account)) {
        state = state.copy(error: _error(error, write: true));
      }
      return false;
    } finally {
      _operations.remove(write);
      if (ref.mounted && generation == _generation) {
        state = state.copy(busy: false);
      }
    }
  }
}
