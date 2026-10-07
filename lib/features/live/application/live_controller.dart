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
  RequestCancellation? _roomRead, _chatRead, _superChatRead;
  Timer? _chatTimer, _superChatExpiryTimer;
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
    _stopRealtime();
    _realtimeSuperChats.clear();
    _deletedSuperChats.clear();
    _superChatTimes.clear();
    _receivedChatKeys.clear();
    _liveSequence = 0;
    _roomRead?.cancel();
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
      _startRealtime();
      refreshChat();
      refreshSuperChats();
    }
  }

  void _startChatTimer() {
    _chatTimer?.cancel();
    _chatTimer = Timer.periodic(chatRefreshInterval, (_) {
      refreshChat();
      refreshSuperChats();
    });
  }

  Future<void> load() async {
    _stopRealtime();
    _realtimeSuperChats.clear();
    _deletedSuperChats.clear();
    _receivedChatKeys.clear();
    _roomRead?.cancel();
    _chatRead?.cancel();
    _superChatRead?.cancel();
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
        _startRealtime();
        await Future.wait([refreshChat(), refreshSuperChats()]);
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

  Future<void> refreshChat() async {
    final room = state.room;
    if (!_active || room == null || state.chatLoading) return;
    _chatRead?.cancel();
    final read = RequestCancellation();
    _chatRead = read;
    final version = ++_chatVersion, generation = _generation;
    final repository = ref.read(liveRepositoryProvider);
    final scope = repository.accountScope, epoch = repository.sessionEpoch;
    state = state.copyWith(chatLoading: true, clearChatMessage: true);
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
        unique[message.deduplicationKey] = message.withFallbackMetadata(
          unique[message.deduplicationKey],
        );
      }
      final all = unique.values.toList(growable: false);
      if (all.every((message) => message.timestamp != null)) {
        all.sort((a, b) {
          final at = a.timestamp, bt = b.timestamp;
          return at == null || bt == null ? 0 : at.compareTo(bt);
        });
      }
      state = state.copyWith(
        chatLoading: false,
        messages: List.unmodifiable(
          all.length <= maxChatMessages
              ? all
              : all.skip(all.length - maxChatMessages),
        ),
        chatUpdatedAt: DateTime.now(),
      );
    } on AppFailure catch (error) {
      if (_active &&
          _current(generation, scope, epoch) &&
          version == _chatVersion) {
        state = state.copyWith(
          chatLoading: false,
          chatMessage: error.kind == AppFailureKind.cancelled
              ? null
              : error.message,
        );
      }
    } catch (_) {
      if (_active &&
          _current(generation, scope, epoch) &&
          version == _chatVersion) {
        state = state.copyWith(chatLoading: false, chatMessage: '历史消息暂时无法更新');
      }
    }
  }

  Future<void> refreshSuperChats() async {
    final room = state.room;
    if (!_active || room == null || state.superChatLoading) return;
    _superChatRead?.cancel();
    final read = RequestCancellation();
    _superChatRead = read;
    final version = ++_superChatVersion, generation = _generation;
    final repository = ref.read(liveRepositoryProvider);
    final scope = repository.accountScope, epoch = repository.sessionEpoch;
    final sequence = _liveSequence;
    state = state.copyWith(superChatLoading: true, clearSuperChatMessage: true);
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
      final unique = <String, LiveSuperChatMessage>{};
      for (final incomingMessage in incoming.take(maxSuperChats)) {
        final message = _resolveSuperChatTiming(incomingMessage, now);
        if (_deletedSuperChats.containsKey(message.id)) continue;
        if (message.expiresAt case final expiry?) {
          if (!expiry.isAfter(now)) continue;
        }
        unique[message.id] = message;
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
      state = state.copyWith(
        superChatLoading: false,
        superChats: List.unmodifiable(
          merged.skip((merged.length - maxSuperChats).clamp(0, merged.length)),
        ),
      );
      _scheduleSuperChatExpiry();
    } on AppFailure catch (error) {
      if (_active &&
          _current(generation, scope, epoch) &&
          version == _superChatVersion) {
        state = state.copyWith(
          superChatLoading: false,
          superChatMessage: error.kind == AppFailureKind.cancelled
              ? null
              : error.message,
        );
      }
    } catch (_) {
      if (_active &&
          _current(generation, scope, epoch) &&
          version == _superChatVersion) {
        state = state.copyWith(
          superChatLoading: false,
          superChatMessage: '醒目留言暂时无法更新',
        );
      }
    }
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
    final chats = <String, LiveChatMessage>{
      for (final message in state.messages) message.deduplicationKey: message,
    };
    final superChats = <String, LiveSuperChatMessage>{
      for (final message in state.superChats) message.id: message,
    };
    final danmaku = <LiveChatMessage>[];
    final now = ref.read(liveClockProvider)();
    var offline = false;
    for (final event in batch.take(500)) {
      ++_liveSequence;
      switch (event) {
        case LiveConnectionChanged(:final phase, :final message):
          next = next.copyWith(
            connectionPhase: phase,
            connectionMessage: message,
            clearConnectionMessage: message == null,
          );
        case LiveChatReceived(:final message):
          chats[message.deduplicationKey] = message.withFallbackMetadata(
            chats[message.deduplicationKey],
          );
          if (_receivedChatKeys.add(message.id ?? message.deduplicationKey)) {
            danmaku.add(message);
          }
        case LiveSuperChatReceived(:final message):
          final timed = _resolveSuperChatTiming(message, now);
          if (_deletedSuperChats.containsKey(message.id) ||
              !(timed.expiresAt?.isAfter(now) ?? true)) {
            continue;
          }
          superChats[message.id] = timed;
          _realtimeSuperChats[message.id] = _liveSequence;
        case LiveSuperChatDeleted(:final ids):
          for (final id in ids.take(maxSuperChats)) {
            superChats.remove(id);
            _realtimeSuperChats.remove(id);
            _deletedSuperChats[id] = _liveSequence;
          }
        case LiveRoomStatusChanged(:final isLive):
          final room = next.room;
          if (room != null) {
            next = next.copyWith(room: _withRoomStatus(room, isLive: isLive));
          }
          if (!isLive) {
            offline = true;
            next = next.copyWith(
              connectionPhase: LiveConnectionPhase.offline,
              clearConnectionMessage: true,
            );
          }
        case LivePopularityChanged(:final popularity):
          final room = next.room;
          if (room != null) {
            next = next.copyWith(
              room: _withRoomStatus(room, popularity: popularity),
            );
          }
        case LiveViewerCountChanged(:final countText):
          next = next.copyWith(viewerCountText: countText);
        case LiveWatchedCountChanged(:final countText):
          next = next.copyWith(watchedCountText: countText);
      }
    }
    final allChats = chats.values.toList();
    final allSuperChats = superChats.values
        .where((message) => message.expiresAt?.isAfter(now) ?? true)
        .toList();
    state = next.copyWith(
      messages: List.unmodifiable(
        allChats.skip(
          (allChats.length - maxChatMessages).clamp(0, allChats.length),
        ),
      ),
      superChats: List.unmodifiable(
        allSuperChats.skip(
          (allSuperChats.length - maxSuperChats).clamp(0, allSuperChats.length),
        ),
      ),
      chatUpdatedAt: danmaku.isEmpty ? null : now,
    );
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
    _scheduleSuperChatExpiry();
    if (offline) _stopRealtime();
  }

  static LiveRoom _withRoomStatus(
    LiveRoom room, {
    bool? isLive,
    int? popularity,
  }) => LiveRoom(
    id: room.id,
    title: room.title,
    anchorName: room.anchorName,
    anchorId: room.anchorId,
    anchorAvatarUrl: room.anchorAvatarUrl,
    coverUrl: room.coverUrl,
    description: room.description,
    areaName: room.areaName,
    isLive: isLive ?? room.isLive,
    popularity: popularity ?? room.popularity,
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
    _superChatExpiryTimer?.cancel();
    _superChatExpiryTimer = null;
    if (!_active || !ref.mounted) return;
    final now = ref.read(liveClockProvider)();
    DateTime? earliest;
    for (final message in state.superChats) {
      final expiry = message.expiresAt;
      if (expiry != null && (earliest == null || expiry.isBefore(earliest))) {
        earliest = expiry;
      }
    }
    if (earliest != null) {
      final delay = earliest.difference(now);
      _superChatExpiryTimer = Timer(
        delay > Duration.zero ? delay : Duration.zero,
        _pruneExpiredSuperChats,
      );
    }
  }
}
