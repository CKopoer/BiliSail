import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/live_repository.dart';
import '../domain/live_chat_repository.dart';
import '../domain/live_room.dart';

final liveRepositoryProvider = Provider<LiveRepository>(
  (ref) => throw UnimplementedError('LiveRepository must be provided by app'),
);

final liveClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final liveChatRepositoryProvider = Provider<LiveChatRepository>(
  (ref) => const UnavailableLiveChatRepository(),
);

final liveViewerRepositoryProvider = Provider<LiveViewerRepository>(
  (ref) => const UnavailableLiveViewerRepository(),
);

final _liveDanmakuEmitterProvider = Provider.autoDispose
    .family<StreamController<List<LiveChatMessage>>, RoomId>((ref, id) {
      final emitter = StreamController<List<LiveChatMessage>>.broadcast(
        sync: true,
      );
      ref.onDispose(emitter.close);
      return emitter;
    });

final liveControllerProvider = NotifierProvider.autoDispose
    .family<LiveController, LiveState, RoomId>(LiveController.new);

final class LiveState {
  const LiveState({
    this.room,
    this.loading = false,
    this.roomMessage,
    this.messages = const [],
    this.chatLoading = false,
    this.chatMessage,
    this.chatUpdatedAt,
    this.superChats = const [],
    this.superChatLoading = false,
    this.superChatMessage,
    this.connectionPhase = LiveConnectionPhase.idle,
    this.connectionMessage,
    this.viewerCountText,
    this.watchedCountText,
    this.historyMessage,
  });

  final LiveRoom? room;
  final bool loading, chatLoading;
  final String? roomMessage, chatMessage;
  final List<LiveChatMessage> messages;
  final DateTime? chatUpdatedAt;
  final List<LiveSuperChatMessage> superChats;
  final bool superChatLoading;
  final String? superChatMessage;
  final LiveConnectionPhase connectionPhase;
  final String? connectionMessage;
  final String? viewerCountText;
  final String? watchedCountText;
  final String? historyMessage;

  LiveState copyWith({
    LiveRoom? room,
    bool? loading,
    String? roomMessage,
    bool clearRoomMessage = false,
    List<LiveChatMessage>? messages,
    bool? chatLoading,
    String? chatMessage,
    bool clearChatMessage = false,
    DateTime? chatUpdatedAt,
    List<LiveSuperChatMessage>? superChats,
    bool? superChatLoading,
    String? superChatMessage,
    bool clearSuperChatMessage = false,
    LiveConnectionPhase? connectionPhase,
    String? connectionMessage,
    bool clearConnectionMessage = false,
    String? viewerCountText,
    String? watchedCountText,
    String? historyMessage,
  }) => LiveState(
    room: room ?? this.room,
    loading: loading ?? this.loading,
    roomMessage: clearRoomMessage ? null : roomMessage ?? this.roomMessage,
    messages: messages ?? this.messages,
    chatLoading: chatLoading ?? this.chatLoading,
    chatMessage: clearChatMessage ? null : chatMessage ?? this.chatMessage,
    chatUpdatedAt: chatUpdatedAt ?? this.chatUpdatedAt,
    superChats: superChats ?? this.superChats,
    superChatLoading: superChatLoading ?? this.superChatLoading,
    superChatMessage: clearSuperChatMessage
        ? null
        : superChatMessage ?? this.superChatMessage,
    connectionPhase: connectionPhase ?? this.connectionPhase,
    connectionMessage: clearConnectionMessage
        ? null
        : connectionMessage ?? this.connectionMessage,
    viewerCountText: viewerCountText ?? this.viewerCountText,
    watchedCountText: watchedCountText ?? this.watchedCountText,
    historyMessage: historyMessage ?? this.historyMessage,
  );
}

class LiveController extends Notifier<LiveState> {
  LiveController(this.requestedId);

  static const chatRefreshInterval = Duration(seconds: 20);
  static const maxChatMessages = 500;
  static const maxSuperChats = 100;

  final RoomId requestedId;
  int _generation = 0, _roomVersion = 0, _chatVersion = 0;
  int _superChatVersion = 0;
  int _viewerVersion = 0, _viewerRealtimeSequence = 0;
  int _viewerPreciseSequence = 0;
  int? _viewerLastLowerBound;
  int? _viewerSnapshotCount;
  DateTime? _viewerSnapshotAt;
  bool _viewerRefreshSuppressed = false;
  RequestCancellation? _viewerRead;
  RequestCancellation? _roomRead, _chatRead, _superChatRead;
  Timer? _chatTimer, _superChatExpiryTimer;
  DateTime? _superChatExpiryAt;
  RequestCancellation? _realtimeRead;
  StreamSubscription<List<LiveRealtimeEvent>>? _realtimeSubscription;
  StreamController<List<LiveChatMessage>>? _danmakuEmitter;
  int _realtimeVersion = 0, _liveSequence = 0;
  final Map<String, int> _realtimeSuperChats = {};
  final Map<String, int> _deletedSuperChats = {};
  final Map<String, ({DateTime? start, DateTime end})> _superChatTimes = {};
  final Set<String> _receivedChatKeys = {};
  Stream<List<LiveChatMessage>> get receivedDanmaku =>
      _danmakuEmitter?.stream ?? const Stream.empty();
  bool _active = false;
  RequestCancellation? _historyWrite;
  (String, int, RoomId)? _reportedEntry;
  bool get isMounted => ref.mounted;

  @override
  LiveState build() {
    ref.watch(authControllerProvider);
    _danmakuEmitter = ref.watch(_liveDanmakuEmitterProvider(requestedId));
    _cancel();
    if (_active) _startChatTimer();
    final generation = ++_generation;
    ref.onDispose(() {
      ++_generation;
      _cancel();
    });
    Future<void>.microtask(() {
      if (ref.mounted && generation == _generation) {
        load();
      }
    });
    return const LiveState(loading: true);
  }

  void _cancel() {
    _historyWrite?.cancel();
    _historyWrite = null;
    _stopRealtime();
    _realtimeSuperChats.clear();
    _deletedSuperChats.clear();
    _superChatTimes.clear();
    _receivedChatKeys.clear();
    _liveSequence = 0;
    _roomRead?.cancel();
    _cancelViewerRead();
    _viewerSnapshotCount = null;
    _viewerSnapshotAt = null;
    _viewerRefreshSuppressed = false;
    _chatRead?.cancel();
    _superChatRead?.cancel();
    _roomRead = null;
    _chatRead = null;
    _superChatRead = null;
    _chatTimer?.cancel();
    _chatTimer = null;
    _superChatExpiryTimer?.cancel();
    _superChatExpiryTimer = null;
    ++_roomVersion;
    ++_chatVersion;
    ++_superChatVersion;
  }

  bool _current(int generation, String scope, int epoch) {
    if (!ref.mounted || generation != _generation) return false;
    final repository = ref.read(liveRepositoryProvider);
    return repository.accountScope == scope && repository.sessionEpoch == epoch;
  }

  /// Workspace/background activity controls messages independently of media.
  void setActive(bool active) {
    if (!ref.mounted) return;
    if (_active == active) return;
    _active = active;
    _chatTimer?.cancel();
    _chatTimer = null;
    if (!active) {
      _stopRealtime();
      _cancelViewerRead();
      _chatRead?.cancel();
      _chatRead = null;
      _superChatRead?.cancel();
      _superChatRead = null;
      _superChatExpiryTimer?.cancel();
      _superChatExpiryTimer = null;
      ++_chatVersion;
      ++_superChatVersion;
      state = state.copyWith(
        chatLoading: false,
        superChatLoading: false,
        connectionPhase: LiveConnectionPhase.closed,
        clearConnectionMessage: true,
      );
      return;
    }
    _startChatTimer();
    _pruneExpiredSuperChats();
    if (state.room != null) {
      unawaited(_reportEntry());
      _startRealtime();
      refreshChat();
      refreshSuperChats();
      refreshViewerCount();
    }
  }

  void _startChatTimer() {
    _chatTimer?.cancel();
    _chatTimer = Timer.periodic(chatRefreshInterval, (_) {
      refreshChat(background: true);
      refreshSuperChats(background: true);
      refreshViewerCount();
    });
  }

  Future<void> load() async {
    _stopRealtime();
    _cancelViewerRead();
    _viewerSnapshotCount = null;
    _viewerSnapshotAt = null;
    _viewerRefreshSuppressed = false;
    _realtimeSuperChats.clear();
    _deletedSuperChats.clear();
    _receivedChatKeys.clear();
    _roomRead?.cancel();
    _chatRead?.cancel();
    _superChatRead?.cancel();
    _chatRead = null;
    _superChatRead = null;
    _superChatExpiryTimer?.cancel();
    _superChatExpiryTimer = null;
    final read = RequestCancellation();
    _roomRead = read;
    final version = ++_roomVersion;
    ++_chatVersion;
    ++_superChatVersion;
    final generation = _generation;
    final repository = ref.read(liveRepositoryProvider);
    final scope = repository.accountScope, epoch = repository.sessionEpoch;
    state = state.copyWith(
      loading: true,
      chatLoading: false,
      superChatLoading: false,
      clearRoomMessage: true,
    );
    _scheduleSuperChatExpiry();
    try {
      final room = await repository.loadRoom(requestedId, cancellation: read);
      if (!_current(generation, scope, epoch) || version != _roomVersion) {
        return;
      }
      state = LiveState(room: room);
      if (_active) {
        unawaited(_reportEntry());
        _startRealtime();
        await Future.wait([
          refreshChat(),
          refreshSuperChats(),
          refreshViewerCount(),
        ]);
      }
    } on AppFailure catch (error) {
      if (_current(generation, scope, epoch) && version == _roomVersion) {
        state = state.copyWith(
          loading: false,
          roomMessage: error.kind == AppFailureKind.cancelled
              ? null
              : error.message,
        );
      }
    } catch (_) {
      if (_current(generation, scope, epoch) && version == _roomVersion) {
        state = state.copyWith(loading: false, roomMessage: '直播间暂时无法加载，请重试');
      }
    }
  }

  void _cancelViewerRead() {
    ++_viewerVersion;
    _viewerRead?.cancel();
    _viewerRead = null;
  }

  Future<void> _reportEntry() async {
    final room = state.room;
    final repository = ref.read(liveRepositoryProvider);
    if (!_active ||
        room == null ||
        repository is! LiveHistoryRepository ||
        !repository.accountScope.startsWith('user:')) {
      return;
    }
    final scope = repository.accountScope, epoch = repository.sessionEpoch;
    final key = (scope, epoch, room.id);
    if (_reportedEntry == key) return;
    _reportedEntry = key;
    final write = RequestCancellation();
    _historyWrite?.cancel();
    _historyWrite = write;
    final generation = _generation;
    try {
      await (repository as LiveHistoryRepository).reportEntry(
        room.id,
        cancellation: write,
      );
    } catch (error) {
      if (!write.isCancelled &&
          _current(generation, scope, epoch) &&
          !(error is AppFailure && error.kind == AppFailureKind.cancelled)) {
        state = state.copyWith(historyMessage: '直播观看记录上报失败');
      }
    } finally {
      if (identical(_historyWrite, write)) _historyWrite = null;
    }
  }

  /// Refresh once per active-page interval; never overlap or replace a newer
  /// precise socket event with a snapshot that began before that event.
  Future<void> refreshViewerCount() async {
    final room = state.room;
    final anchor = room?.anchorId;
    if (!_active ||
        state.loading ||
        room == null ||
        !room.isLive ||
        anchor == null ||
        !anchor.isValid ||
        _viewerRead != null ||
        _viewerRefreshSuppressed) {
      return;
    }
    final read = RequestCancellation();
    _viewerRead = read;
    final version = ++_viewerVersion, generation = _generation;
    final repository = ref.read(liveRepositoryProvider);
    final scope = repository.accountScope, epoch = repository.sessionEpoch;
    final sequence = _viewerRealtimeSequence;
    final preciseSequence = _viewerPreciseSequence;
    bool current() =>
        _active &&
        _current(generation, scope, epoch) &&
        version == _viewerVersion &&
        state.room?.id == room.id &&
        state.room?.isLive == true;
    try {
      final count = await ref
          .read(liveViewerRepositoryProvider)
          .loadViewerCount(room.id, anchor, cancellation: read);
      if (!current() || count == null || count < 0) return;
      final lowerBound = _viewerLastLowerBound;
      if (preciseSequence == _viewerPreciseSequence &&
          (sequence == _viewerRealtimeSequence ||
              lowerBound == null ||
              count >= lowerBound)) {
        _viewerSnapshotCount = count;
        _viewerSnapshotAt = ref.read(liveClockProvider)();
        if (state.viewerCountText != '$count') {
          state = state.copyWith(viewerCountText: '$count');
        }
      }
    } on AppFailure catch (error) {
      if (current() &&
          const {
            AppFailureKind.rateLimited,
            AppFailureKind.authentication,
            AppFailureKind.permission,
            AppFailureKind.protocol,
          }.contains(error.kind)) {
        // An optional statistic must not turn failure into an empty success,
        // interrupt playback or repeatedly hit a blocked endpoint.
        _viewerRefreshSuppressed = true;
      }
    } catch (_) {
      if (current()) _viewerRefreshSuppressed = true;
    } finally {
      if (identical(_viewerRead, read)) _viewerRead = null;
    }
  }

  static int? _viewerLowerBound(String? text) {
    if (text == '9999') return 9999;
    if (text == null || !text.endsWith('+')) return null;
    final match = RegExp(r'^(\d+(?:\.\d+)?)([千万亿]?)\+$').firstMatch(text);
    if (match == null) return null;
    final number = double.tryParse(match.group(1) ?? '');
    if (number == null || !number.isFinite) return null;
    final unit = switch (match.group(2)) {
      '千' => 1000,
      '万' => 10000,
      '亿' => 100000000,
      _ => 1,
    };
    return (number * unit).ceil();
  }

  Future<void> refreshChat({bool background = false}) async {
    final room = state.room;
    if (!_active || room == null) return;
    if (_chatRead != null) {
      if (!background && !state.chatLoading) {
        state = state.copyWith(chatLoading: true, clearChatMessage: true);
      }
      return;
    }
    final read = RequestCancellation();
    _chatRead = read;
    final version = ++_chatVersion, generation = _generation;
    final repository = ref.read(liveRepositoryProvider);
    final scope = repository.accountScope, epoch = repository.sessionEpoch;
    if (!background) {
      state = state.copyWith(chatLoading: true, clearChatMessage: true);
    }
    try {
      final incoming = await repository.loadChatHistory(
        room.id,
        cancellation: read,
      );
      if (!_active ||
          !_current(generation, scope, epoch) ||
          version != _chatVersion) {
        return;
      }
      final unique = <String, LiveChatMessage>{
        for (final message in state.messages) message.deduplicationKey: message,
      };
      for (final message in incoming) {
        final key = message.deduplicationKey;
        final previous = unique[key];
        final merged = message.withFallbackMetadata(previous);
        unique[key] = previous != null && _sameChat(previous, merged)
            ? previous
            : merged;
      }
      final all = unique.values.toList(growable: false);
      if (all.every((message) => message.timestamp != null)) {
        all.sort((a, b) {
          final at = a.timestamp, bt = b.timestamp;
          return at == null || bt == null ? 0 : at.compareTo(bt);
        });
      }
      final retained = all.length <= maxChatMessages
          ? all
          : all.sublist(all.length - maxChatMessages);
      final changed = !_sameList(state.messages, retained, _sameChat);
      if (changed || state.chatLoading || state.chatMessage != null) {
        state = state.copyWith(
          chatLoading: false,
          clearChatMessage: true,
          messages: changed ? List.unmodifiable(retained) : null,
          chatUpdatedAt: ref.read(liveClockProvider)(),
        );
      }
    } on AppFailure catch (error) {
      if (_active &&
          _current(generation, scope, epoch) &&
          version == _chatVersion) {
        final message = error.kind == AppFailureKind.cancelled
            ? null
            : error.message;
        if (state.chatLoading || state.chatMessage != message) {
          state = state.copyWith(
            chatLoading: false,
            chatMessage: message,
            clearChatMessage: message == null,
          );
        }
      }
    } catch (_) {
      if (_active &&
          _current(generation, scope, epoch) &&
          version == _chatVersion) {
        if (state.chatLoading || state.chatMessage != '历史消息暂时无法更新') {
          state = state.copyWith(chatLoading: false, chatMessage: '历史消息暂时无法更新');
        }
      }
    } finally {
      if (identical(_chatRead, read)) _chatRead = null;
    }
  }

  Future<void> refreshSuperChats({bool background = false}) async {
    final room = state.room;
    if (!_active || room == null) return;
    if (_superChatRead != null) {
      if (!background && !state.superChatLoading) {
        state = state.copyWith(
          superChatLoading: true,
          clearSuperChatMessage: true,
        );
      }
      return;
    }
    final read = RequestCancellation();
    _superChatRead = read;
    final version = ++_superChatVersion, generation = _generation;
    final repository = ref.read(liveRepositoryProvider);
    final scope = repository.accountScope, epoch = repository.sessionEpoch;
    final sequence = _liveSequence;
    if (!background) {
      state = state.copyWith(
        superChatLoading: true,
        clearSuperChatMessage: true,
      );
    }
    try {
      final incoming = await repository.loadSuperChats(
        room.id,
        cancellation: read,
      );
      if (!_active ||
          !_current(generation, scope, epoch) ||
          version != _superChatVersion) {
        return;
      }
      final now = ref.read(liveClockProvider)();
      final previous = {
        for (final message in state.superChats) message.id: message,
      };
      final unique = <String, LiveSuperChatMessage>{};
      for (final incomingMessage in incoming.take(maxSuperChats)) {
        final message = _resolveSuperChatTiming(incomingMessage, now);
        if (_deletedSuperChats.containsKey(message.id)) continue;
        if (message.expiresAt case final expiry?) {
          if (!expiry.isAfter(now)) continue;
        }
        final old = previous[message.id];
        unique[message.id] = old != null && _sameSuperChat(old, message)
            ? old
            : message;
      }
      // The snapshot describes the start of this read. Events arriving while
      // it was in flight must win over missing/stale HTTP snapshot entries.
      for (final message in state.superChats) {
        if ((_realtimeSuperChats[message.id] ?? 0) > sequence &&
            !_deletedSuperChats.containsKey(message.id) &&
            (message.expiresAt?.isAfter(now) ?? true)) {
          unique[message.id] = message;
        }
      }
      final merged = unique.values.toList();
      final retained = merged.sublist(
        (merged.length - maxSuperChats).clamp(0, merged.length),
      );
      final changed = !_sameList(state.superChats, retained, _sameSuperChat);
      if (changed || state.superChatLoading || state.superChatMessage != null) {
        state = state.copyWith(
          superChatLoading: false,
          clearSuperChatMessage: true,
          superChats: changed ? List.unmodifiable(retained) : null,
        );
      }
      _scheduleSuperChatExpiry();
    } on AppFailure catch (error) {
      if (_active &&
          _current(generation, scope, epoch) &&
          version == _superChatVersion) {
        final message = error.kind == AppFailureKind.cancelled
            ? null
            : error.message;
        if (state.superChatLoading || state.superChatMessage != message) {
          state = state.copyWith(
            superChatLoading: false,
            superChatMessage: message,
            clearSuperChatMessage: message == null,
          );
        }
      }
    } catch (_) {
      if (_active &&
          _current(generation, scope, epoch) &&
          version == _superChatVersion) {
        if (state.superChatLoading || state.superChatMessage != '醒目留言暂时无法更新') {
          state = state.copyWith(
            superChatLoading: false,
            superChatMessage: '醒目留言暂时无法更新',
          );
        }
      }
    } finally {
      if (identical(_superChatRead, read)) _superChatRead = null;
    }
  }

  static bool _sameList<T>(List<T> a, List<T> b, bool Function(T, T) same) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (!same(a[index], b[index])) return false;
    }
    return true;
  }

  void _stopRealtime() {
    ++_realtimeVersion;
    _realtimeRead?.cancel();
    _realtimeRead = null;
    final subscription = _realtimeSubscription;
    _realtimeSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  /// Explicit user retry restarts the bounded WS attempt budget.
  void retryRealtime() {
    if (!ref.mounted || !_active) return;
    _stopRealtime();
    _startRealtime();
  }

  void _startRealtime() {
    final room = state.room;
    if (!_active ||
        room == null ||
        !room.isLive ||
        _realtimeSubscription != null) {
      return;
    }
    final read = RequestCancellation();
    _realtimeRead = read;
    final version = ++_realtimeVersion, generation = _generation;
    final repository = ref.read(liveRepositoryProvider);
    final scope = repository.accountScope, epoch = repository.sessionEpoch;
    _realtimeSubscription = ref
        .read(liveChatRepositoryProvider)
        .watchRoom(room.id, cancellation: read)
        .listen(
          (batch) {
            if (!_active ||
                !_current(generation, scope, epoch) ||
                version != _realtimeVersion) {
              return;
            }
            _acceptRealtime(batch);
          },
          onError: (Object _, StackTrace _) {
            if (_active &&
                _current(generation, scope, epoch) &&
                version == _realtimeVersion) {
              state = state.copyWith(
                connectionPhase: LiveConnectionPhase.failed,
                connectionMessage: '实时弹幕暂时无法连接，请重试',
              );
            }
          },
        );
  }

  void _acceptRealtime(List<LiveRealtimeEvent> batch) {
    var next = state;
    Map<String, LiveChatMessage>? chats;
    Map<String, LiveSuperChatMessage>? superChats;
    var chatsChanged = false;
    var superChatsChanged = false;
    final danmaku = <LiveChatMessage>[];
    final now = ref.read(liveClockProvider)();
    var offline = false;
    for (final event in batch.take(500)) {
      ++_liveSequence;
      switch (event) {
        case LiveConnectionChanged(:final phase, :final message):
          if (next.connectionPhase != phase ||
              next.connectionMessage != message) {
            next = next.copyWith(
              connectionPhase: phase,
              connectionMessage: message,
              clearConnectionMessage: message == null,
            );
          }
        case LiveChatReceived(:final message):
          final messages = chats ??= {
            for (final item in state.messages) item.deduplicationKey: item,
          };
          final key = message.deduplicationKey;
          final previous = messages[key];
          final merged = message.withFallbackMetadata(previous);
          if (!_sameChat(previous, merged)) {
            messages[key] = merged;
            chatsChanged = true;
          }
          if (_receivedChatKeys.add(message.id ?? message.deduplicationKey)) {
            danmaku.add(message);
          }
        case LiveSuperChatReceived(:final message):
          final timed = _resolveSuperChatTiming(message, now);
          if (_deletedSuperChats.containsKey(message.id) ||
              !(timed.expiresAt?.isAfter(now) ?? true)) {
            continue;
          }
          final messages = superChats ??= {
            for (final item in state.superChats) item.id: item,
          };
          if (!_sameSuperChat(messages[message.id], timed)) {
            messages[message.id] = timed;
            superChatsChanged = true;
          }
          _realtimeSuperChats[message.id] = _liveSequence;
        case LiveSuperChatDeleted(:final ids):
          for (final id in ids.take(maxSuperChats)) {
            final messages = superChats ??= {
              for (final item in state.superChats) item.id: item,
            };
            if (messages.remove(id) != null) superChatsChanged = true;
            _realtimeSuperChats.remove(id);
            _deletedSuperChats[id] = _liveSequence;
          }
        case LiveRoomStatusChanged(:final isLive):
          final room = next.room;
          if (room != null && room.isLive != isLive) {
            next = next.copyWith(room: _withRoomStatus(room, isLive: isLive));
          }
          if (!isLive) {
            offline = true;
            if (next.connectionPhase != LiveConnectionPhase.offline ||
                next.connectionMessage != null) {
              next = next.copyWith(
                connectionPhase: LiveConnectionPhase.offline,
                clearConnectionMessage: true,
              );
            }
          }
        case LivePopularityChanged():
          // Heartbeats may report a placeholder 1. Keep the room-load snapshot;
          // the chat session still handles heartbeat liveness independently.
          continue;
        case LiveViewerCountChanged(:final countText):
          ++_viewerRealtimeSequence;
          final count = int.tryParse(countText);
          final lowerBound = _viewerLowerBound(countText);
          _viewerLastLowerBound = lowerBound;
          final capped = lowerBound != null;
          final snapshotAt = _viewerSnapshotAt;
          final preciseSnapshot =
              _viewerSnapshotCount != null &&
              lowerBound != null &&
              (_viewerSnapshotCount ?? 0) >= lowerBound &&
              snapshotAt != null &&
              now.difference(snapshotAt) <= chatRefreshInterval * 2;
          if ((!capped || !preciseSnapshot) &&
              next.viewerCountText != countText) {
            next = next.copyWith(viewerCountText: countText);
          }
          if (!capped) {
            ++_viewerPreciseSequence;
            _viewerSnapshotCount = count;
            _viewerSnapshotAt = count == null ? null : now;
          } else if (!preciseSnapshot) {
            _viewerSnapshotCount = null;
            _viewerSnapshotAt = null;
          }
        case LiveWatchedCountChanged(:final countText):
          if (next.watchedCountText != countText) {
            next = next.copyWith(watchedCountText: countText);
          }
      }
    }
    if (chatsChanged && chats != null) {
      next = next.copyWith(
        messages: List.unmodifiable(
          chats.values.skip(
            (chats.length - maxChatMessages).clamp(0, chats.length),
          ),
        ),
      );
    }
    if (superChatsChanged && superChats != null) {
      final live = superChats.values
          .where((message) => message.expiresAt?.isAfter(now) ?? true)
          .toList();
      next = next.copyWith(
        superChats: List.unmodifiable(
          live.skip((live.length - maxSuperChats).clamp(0, live.length)),
        ),
      );
    }
    if (danmaku.isNotEmpty) next = next.copyWith(chatUpdatedAt: now);
    if (!identical(next, state)) state = next;
    while (_realtimeSuperChats.length > maxSuperChats) {
      _realtimeSuperChats.remove(_realtimeSuperChats.keys.first);
    }
    while (_deletedSuperChats.length > maxSuperChats * 2) {
      _deletedSuperChats.remove(_deletedSuperChats.keys.first);
    }
    while (_receivedChatKeys.length > maxChatMessages) {
      _receivedChatKeys.remove(_receivedChatKeys.first);
    }
    if (danmaku.isNotEmpty && !(_danmakuEmitter?.isClosed ?? true)) {
      _danmakuEmitter?.add(List.unmodifiable(danmaku));
    }
    if (superChatsChanged) _scheduleSuperChatExpiry();
    if (offline) {
      _stopRealtime();
      _cancelViewerRead();
    }
  }

  static bool _sameImage(LiveChatImage? a, LiveChatImage? b) =>
      identical(a, b) ||
      (a != null &&
          b != null &&
          a.url == b.url &&
          a.width == b.width &&
          a.height == b.height);

  static bool _sameChat(LiveChatMessage? a, LiveChatMessage b) =>
      identical(a, b) ||
      (a != null &&
          a.id == b.id &&
          a.userName == b.userName &&
          a.text == b.text &&
          a.timestamp == b.timestamp &&
          a.userId == b.userId &&
          a.color == b.color &&
          a.mode == b.mode &&
          a.fontSize == b.fontSize &&
          a.medal == b.medal &&
          a.userLevel == b.userLevel &&
          _sameImage(a.sticker, b.sticker) &&
          a.emotes.length == b.emotes.length &&
          a.emotes.entries.every(
            (entry) => _sameImage(entry.value, b.emotes[entry.key]),
          ));

  static bool _sameSuperChat(LiveSuperChatMessage? a, LiveSuperChatMessage b) =>
      identical(a, b) ||
      (a != null &&
          a.id == b.id &&
          a.userName == b.userName &&
          a.text == b.text &&
          a.userId == b.userId &&
          a.price == b.price &&
          a.avatarUrl == b.avatarUrl &&
          a.startedAt == b.startedAt &&
          a.expiresAt == b.expiresAt &&
          a.displayDuration == b.displayDuration &&
          a.remainingDuration == b.remainingDuration &&
          a.backgroundColor == b.backgroundColor &&
          a.backgroundBottomColor == b.backgroundBottomColor &&
          a.textColor == b.textColor);

  static LiveRoom _withRoomStatus(LiveRoom room, {bool? isLive}) => LiveRoom(
    id: room.id,
    title: room.title,
    anchorName: room.anchorName,
    anchorId: room.anchorId,
    anchorAvatarUrl: room.anchorAvatarUrl,
    coverUrl: room.coverUrl,
    description: room.description,
    areaName: room.areaName,
    isLive: isLive ?? room.isLive,
    popularity: room.popularity,
  );

  void _pruneExpiredSuperChats() {
    if (!ref.mounted) return;
    final now = ref.read(liveClockProvider)();
    final live = state.superChats
        .where((message) => message.expiresAt?.isAfter(now) ?? true)
        .toList(growable: false);
    if (live.length != state.superChats.length) {
      state = state.copyWith(superChats: List.unmodifiable(live));
    }
    _scheduleSuperChatExpiry();
  }

  LiveSuperChatMessage _resolveSuperChatTiming(
    LiveSuperChatMessage message,
    DateTime now,
  ) {
    final known = _superChatTimes[message.id];
    var start = message.startedAt;
    var end = message.expiresAt;
    final duration = message.displayDuration;
    if (end == null) {
      // A duration-only fallback is anchored once. Repeated snapshots/socket
      // delivery must not restart its lifetime or resurrect an expired SC.
      start ??= known?.start;
      end = known?.end;
      final remaining = message.remainingDuration;
      if (end == null && remaining != null && remaining >= Duration.zero) {
        end = now.add(remaining);
      } else if (end == null && duration != null && duration > Duration.zero) {
        start ??= now;
        end = start.add(duration);
      }
    }
    if (end == null) return message;
    _superChatTimes[message.id] = (start: start, end: end);
    while (_superChatTimes.length > maxSuperChats * 2) {
      _superChatTimes.remove(_superChatTimes.keys.first);
    }
    return message.withTiming(start, end);
  }

  void _scheduleSuperChatExpiry() {
    if (!_active || !ref.mounted) return;
    final now = ref.read(liveClockProvider)();
    DateTime? earliest;
    for (final message in state.superChats) {
      final expiry = message.expiresAt;
      if (expiry != null && (earliest == null || expiry.isBefore(earliest))) {
        earliest = expiry;
      }
    }
    if (_superChatExpiryAt == earliest &&
        (_superChatExpiryTimer?.isActive ?? false)) {
      return;
    }
    _superChatExpiryTimer?.cancel();
    _superChatExpiryTimer = null;
    _superChatExpiryAt = earliest;
    if (earliest != null) {
      final delay = earliest.difference(now);
      _superChatExpiryTimer = Timer(
        delay > Duration.zero ? delay : Duration.zero,
        () {
          _superChatExpiryTimer = null;
          _superChatExpiryAt = null;
          _pruneExpiredSuperChats();
        },
      );
    }
  }
}
