import 'dart:async';

import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/live/application/live_controller.dart';
import 'package:bilisail/features/live/domain/live_chat_repository.dart';
import 'package:bilisail/features/live/domain/live_repository.dart';
import 'package:bilisail/features/live/domain/live_room.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const requested = RoomId('12'), canonical = RoomId('12345');
final now = DateTime.utc(2026, 10, 5, 12);
LiveChatMessage chat(String id, {String text = '新消息'}) =>
    LiveChatMessage(id: id, userName: '测试观众', text: text, timestamp: now);
LiveSuperChatMessage sc(String id) => LiveSuperChatMessage(
  id: id,
  userName: '测试观众',
  text: '醒目留言',
  price: 50,
  expiresAt: now.add(const Duration(minutes: 1)),
);

void main() {
  late _Repository repository;
  late _Auth auth;
  late ProviderContainer container;
  late LiveController controller;
  setUp(() async {
    repository = _Repository();
    auth = _Auth();
    container = ProviderContainer(
      overrides: [
        liveRepositoryProvider.overrideWithValue(repository),
        liveChatRepositoryProvider.overrideWithValue(repository),
        authRepositoryProvider.overrideWithValue(auth),
        liveClockProvider.overrideWithValue(() => now),
      ],
    );
    container.listen(liveControllerProvider(requested), (_, _) {});
    controller = container.read(liveControllerProvider(requested).notifier);
    await Future<void>.delayed(Duration.zero);
    controller.setActive(true);
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() async {
    container.dispose();
    await repository.events.close();
    await auth.events.close();
  });
  LiveState state() => container.read(liveControllerProvider(requested));

  test(
    'canonical room socket adds typed chat, SC and connection in one batch',
    () async {
      final screen = <LiveChatMessage>[];
      final sub = controller.receivedDanmaku.listen(screen.addAll);
      repository.events.add([
        const LiveConnectionChanged(LiveConnectionPhase.connected),
        LiveChatReceived(chat('live:1')),
        LiveSuperChatReceived(sc('55')),
      ]);
      expect(repository.watched, canonical);
      expect(state().connectionPhase, LiveConnectionPhase.connected);
      expect(state().messages, hasLength(1));
      expect(state().superChats.single.id, '55');
      expect(screen, hasLength(1));
      await sub.cancel();
    },
  );
  test(
    'history arriving after WS overlaps once and never enters overlay',
    () async {
      final screen = <LiveChatMessage>[];
      final sub = controller.receivedDanmaku.listen(screen.addAll);
      final pending = Completer<List<LiveChatMessage>>();
      repository.pendingHistory = pending;
      final read = controller.refreshChat();
      repository.events.add([LiveChatReceived(chat('live:1'))]);
      pending.complete([chat('historical:1')]);
      await read;
      expect(state().messages, hasLength(1));
      expect(screen, hasLength(1));
      await sub.cancel();
    },
  );
  test(
    'sparse late history retains socket profile and image metadata',
    () async {
      final image = LiveChatImage(
        url: Uri.parse('https://i0.hdslb.com/test.png'),
      );
      repository.events.add([
        LiveChatReceived(
          LiveChatMessage(
            id: 'live:1',
            userName: '测试观众',
            userId: const UserId('123'),
            text: '新消息',
            timestamp: now,
            emotes: {'新消息': image},
            sticker: image,
          ),
        ),
      ]);
      repository.history = [chat('history:1')];
      await controller.refreshChat();
      final message = state().messages.single;
      expect(message.userId, const UserId('123'));
      expect(message.emotes['新消息'], image);
      expect(message.sticker, image);
    },
  );
  test(
    'viewer count is isolated from popularity and stale connection events',
    () async {
      repository.events.add(const [
        LiveViewerCountChanged('123'),
        LivePopularityChanged(9999),
      ]);
      expect(state().viewerCountText, '123');
      expect(state().room?.popularity, 9999);
      controller.setActive(false);
      repository.events.add(const [LiveViewerCountChanged('456')]);
      expect(state().viewerCountText, '123');
      controller.setActive(true);
      repository.epoch++;
      repository.events.add(const [LiveViewerCountChanged('789')]);
      expect(state().viewerCountText, '123');
      auth.events.add(const AuthState(status: AuthStatus.signedIn));
      await Future<void>.delayed(Duration.zero);
      expect(state().viewerCountText, isNull);
    },
  );
  test('merging rich snapshots keeps the per-message image limit', () {
    final image = LiveChatImage(
      url: Uri.parse('https://i0.hdslb.com/fixture.png'),
    );
    final old = LiveChatMessage(
      userName: '观众',
      text: '文本',
      emotes: {for (var index = 0; index < 50; index++) 'old-$index': image},
    );
    final next = LiveChatMessage(
      userName: '观众',
      text: '文本',
      emotes: {for (var index = 0; index < 50; index++) 'new-$index': image},
    ).withFallbackMetadata(old);
    expect(next.emotes.length, 50);
    expect(() => next.emotes.clear(), throwsUnsupportedError);
  });
  test(
    'history before WS keeps one row and the new WS still reaches overlay',
    () async {
      repository.history = [chat('historical:1')];
      await controller.refreshChat();
      final screen = <LiveChatMessage>[];
      final sub = controller.receivedDanmaku.listen(screen.addAll);
      repository.events.add([LiveChatReceived(chat('live:1'))]);
      repository.events.add([LiveChatReceived(chat('live:1'))]);
      expect(state().messages, hasLength(1));
      expect(screen, hasLength(1));
      await sub.cancel();
    },
  );
  test(
    'late SC snapshot keeps newer insert and cannot resurrect deletion',
    () async {
      final pending = Completer<List<LiveSuperChatMessage>>();
      repository.pendingSc = pending;
      final read = controller.refreshSuperChats();
      repository.events.add([
        LiveSuperChatReceived(sc('new')),
        LiveSuperChatDeleted(['deleted']),
      ]);
      pending.complete([sc('deleted')]);
      await read;
      expect(state().superChats.map((m) => m.id), ['new']);
    },
  );
  test(
    'hidden and old epoch events never mutate chat or publish danmaku',
    () async {
      final screen = <LiveChatMessage>[];
      final sub = controller.receivedDanmaku.listen(screen.addAll);
      controller.setActive(false);
      repository.events.add([LiveChatReceived(chat('hidden'))]);
      expect(repository.cancellation?.isCancelled, true);
      expect(screen, isEmpty);
      controller.setActive(true);
      repository.epoch++;
      repository.scope = 'new-account';
      repository.events.add([LiveChatReceived(chat('old'))]);
      expect(screen, isEmpty);
      expect(state().messages, isEmpty);
      auth.events.add(const AuthState(status: AuthStatus.signedIn));
      await Future<void>.delayed(Duration.zero);
      expect(state().messages, isEmpty);
      await sub.cancel();
    },
  );
  test(
    'connection failure retains chat and explicit retry starts new session',
    () async {
      repository.events.add([
        LiveChatReceived(chat('one')),
        const LiveConnectionChanged(
          LiveConnectionPhase.failed,
          message: '网络中断',
        ),
      ]);
      expect(state().messages, hasLength(1));
      expect(state().room?.isLive, true);
      final old = repository.cancellation;
      controller.retryRealtime();
      expect(old?.isCancelled, true);
      expect(repository.watches, 2);
    },
  );
  test(
    'offline status stops messages and retained arrays remain bounded',
    () async {
      repository.events.add([
        for (var i = 0; i < 500; i++)
          LiveChatReceived(chat('$i', text: '消息$i')),
      ]);
      repository.events.add([
        for (var i = 500; i < 1000; i++)
          LiveChatReceived(chat('$i', text: '消息$i')),
      ]);
      expect(state().messages, hasLength(500));
      expect(state().messages.first.text, '消息500');
      repository.events.add([const LiveRoomStatusChanged(false)]);
      expect(state().connectionPhase, LiveConnectionPhase.offline);
      expect(state().room?.isLive, false);
      expect(repository.cancellation?.isCancelled, true);
    },
  );
  test('account invalidation immediately cancels tracked lifetime and unregisters safely', () {
    final requests = ApiRequests();
    final lifetime = RequestCancellation();
    final unregister = requests.trackLifetime(lifetime);
    requests.advanceSession();
    expect(lifetime.isCancelled, true);
    unregister();
    requests.advanceSession();
  });
}

final class _Repository implements LiveRepository, LiveChatRepository {
  final events = StreamController<List<LiveRealtimeEvent>>.broadcast(
    sync: true,
  );
  String scope = 'guest';
  int epoch = 0, watches = 0;
  RoomId? watched;
  RequestCancellation? cancellation;
  List<LiveChatMessage> history = [];
  Completer<List<LiveChatMessage>>? pendingHistory;
  Completer<List<LiveSuperChatMessage>>? pendingSc;
  @override
  String get accountScope => scope;
  @override
  int get sessionEpoch => epoch;
  @override
  Stream<List<LiveRealtimeEvent>> watchRoom(
    RoomId id, {
    required RequestCancellation cancellation,
  }) {
    watches++;
    watched = id;
    this.cancellation = cancellation;
    return events.stream;
  }

  @override
  Future<LiveRoom> loadRoom(
    RoomId id, {
    required RequestCancellation cancellation,
  }) async => const LiveRoom(
    id: canonical,
    title: '直播',
    anchorName: '主播',
    isLive: true,
  );
  @override
  Future<LivePlayInfo> loadPlayInfo(
    RoomId id, {
    int quality = 10000,
    required RequestCancellation cancellation,
  }) async => const LivePlayInfo(roomId: canonical, isLive: true, streams: []);
  @override
  Future<List<LiveChatMessage>> loadChatHistory(
    RoomId id, {
    required RequestCancellation cancellation,
  }) => pendingHistory?.future ?? Future.value(history);
  @override
  Future<List<LiveSuperChatMessage>> loadSuperChats(
    RoomId id, {
    required RequestCancellation cancellation,
  }) => pendingSc?.future ?? Future.value([]);
}

final class _Auth implements AuthRepository {
  final events = StreamController<AuthState>.broadcast(sync: true);
  @override
  AuthState get current => const AuthState();
  @override
  Stream<AuthState> get changes => events.stream;
  @override
  Future<void> restore() async {}
  @override
  Future<void> signIn() async {}
  @override
  Future<void> signOut() async {}
  @override
  void cancelSignIn() {}
}
