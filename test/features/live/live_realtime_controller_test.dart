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
var now = DateTime.utc(2026, 10, 5, 12);
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
    now = DateTime.utc(2026, 10, 5, 12);
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
    'ignored and unchanged events publish nothing and retain both windows',
    () {
      repository.events.add([
        LiveChatReceived(chat('one')),
        LiveSuperChatReceived(sc('one')),
        const LiveViewerCountChanged('42'),
        const LiveWatchedCountChanged('84'),
        const LiveConnectionChanged(LiveConnectionPhase.connected),
      ]);
      final before = state();
      var notifications = 0;
      final subscription = container.listen(
        liveControllerProvider(requested),
        (_, _) => notifications++,
      );
      for (var index = 0; index < 20; index++) {
        repository.events.add(const [
          LivePopularityChanged(1),
          LiveViewerCountChanged('42'),
          LiveWatchedCountChanged('84'),
          LiveConnectionChanged(LiveConnectionPhase.connected),
          LiveRoomStatusChanged(true),
        ]);
      }
      repository.events.add([LiveChatReceived(chat('one'))]);
      repository.events.add([LiveSuperChatReceived(sc('one'))]);
      repository.events.add([
        LiveSuperChatDeleted(['missing']),
      ]);
      expect(notifications, 0);
      expect(state(), same(before));
      expect(state().messages, same(before.messages));
      expect(state().superChats, same(before.superChats));
      subscription.close();
    },
  );

  test('each realtime field replaces only its own immutable window', () {
    final initial = state();
    repository.events.add(const [LiveViewerCountChanged('42')]);
    expect(state().messages, same(initial.messages));
    expect(state().superChats, same(initial.superChats));
    repository.events.add([LiveChatReceived(chat('one'))]);
    final withChat = state();
    expect(withChat.superChats, same(initial.superChats));
    expect(() => withChat.messages.clear(), throwsUnsupportedError);
    repository.events.add([LiveSuperChatReceived(sc('one'))]);
    expect(state().messages, same(withChat.messages));
    expect(() => state().superChats.clear(), throwsUnsupportedError);
    final withSc = state();
    repository.events.add(const [
      LiveConnectionChanged(LiveConnectionPhase.failed),
    ]);
    expect(state().messages, same(withChat.messages));
    expect(state().superChats, same(withSc.superChats));
  });

  test('SC batching preserves delete order and the newest 100 entries', () {
    repository.events.add([
      for (var index = 0; index < 120; index++)
        LiveSuperChatReceived(sc('$index')),
    ]);
    expect(state().superChats, hasLength(100));
    expect(state().superChats.first.id, '20');
    repository.events.add([
      LiveSuperChatReceived(sc('insert-delete')),
      LiveSuperChatDeleted(['insert-delete', 'delete-insert']),
      LiveSuperChatReceived(sc('delete-insert')),
    ]);
    expect(
      state().superChats.any((message) => message.id.contains('-')),
      false,
    );
    expect(state().superChats, hasLength(100));
    final previous = state();
    repository.events.add(const [LiveRoomStatusChanged(false)]);
    expect(state().room?.isLive, false);
    expect(state().connectionPhase, LiveConnectionPhase.offline);
    expect(repository.cancellation?.isCancelled, true);
    expect(state().messages, same(previous.messages));
    expect(state().superChats, same(previous.superChats));
  });

  testWidgets('unchanged expiry keeps its timer and earlier SC reschedules it', (
    tester,
  ) async {
    controller.setActive(false);
    controller.setActive(true);
    await tester.pump();
    LiveSuperChatMessage timed(String id, int seconds) => LiveSuperChatMessage(
      id: id,
      userName: '观众',
      text: 'SC',
      price: 30,
      expiresAt: now.add(Duration(seconds: seconds)),
    );
    var timers = 0;
    runZoned(
      () {
        // Register the stream listener here so timer creation stays observable.
        controller.retryRealtime();
        repository.events.add([LiveSuperChatReceived(timed('first', 5))]);
        repository.events.add([LiveSuperChatReceived(timed('later', 8))]);
        repository.events.add(const [LiveViewerCountChanged('42')]);
        repository.events.add([LiveChatReceived(chat('one'))]);
        expect(timers, 1);
        repository.events.add([LiveSuperChatReceived(timed('earlier', 2))]);
        expect(timers, 2);
      },
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          timers++;
          return parent.createTimer(zone, duration, callback);
        },
      ),
    );
    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(state().superChats.map((message) => message.id), ['first', 'later']);
    now = now.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    expect(state().superChats.single.id, 'later');
    controller.setActive(false);
  });

  testWidgets('socket duration expires without waiting for HTTP polling', (
    tester,
  ) async {
    // Register the stream listener inside the widget test's fake timer zone.
    controller.setActive(false);
    controller.setActive(true);
    await tester.pump();
    const message = LiveSuperChatMessage(
      id: 'timed',
      userName: '观众',
      text: 'SC',
      price: 30,
      displayDuration: Duration(seconds: 3),
    );
    repository.events.add([const LiveSuperChatReceived(message)]);
    final expiry = now.add(const Duration(seconds: 3));
    expect(state().superChats.single.expiresAt, expiry);
    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    repository.events.add([const LiveSuperChatReceived(message)]);
    expect(state().superChats.single.expiresAt, expiry);
    now = expiry;
    await tester.pump(const Duration(seconds: 1));
    expect(state().superChats, isEmpty);
    repository.events.add([const LiveSuperChatReceived(message)]);
    expect(state().superChats, isEmpty);
    controller.setActive(false);
  });

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
            medal: const LiveFanMedal(name: '哔帆', level: 25),
            userLevel: 42,
          ),
        ),
      ]);
      repository.history = [chat('history:1')];
      await controller.refreshChat();
      final message = state().messages.single;
      expect(message.userId, const UserId('123'));
      expect(message.emotes['新消息'], image);
      expect(message.sticker, image);
      expect(message.medal, const LiveFanMedal(name: '哔帆', level: 25));
      expect(message.userLevel, 42);
    },
  );
  test('watched and viewer counts stay independent and reject stale connection events', () async {
    repository.events.add(const [
      LiveViewerCountChanged('123'),
      LiveWatchedCountChanged('1.2万'),
      LivePopularityChanged(9999),
    ]);
    expect(state().viewerCountText, '123');
    expect(state().watchedCountText, '1.2万');
    expect(state().room?.popularity, isNull);
    repository.events.add(const [LiveWatchedCountChanged('1.3万')]);
    expect(state().viewerCountText, '123');
    expect(state().watchedCountText, '1.3万');
    repository.events.add(const [LiveViewerCountChanged('0')]);
    expect(state().viewerCountText, '0');
    expect(state().watchedCountText, '1.3万');
    controller.setActive(false);
    repository.events.add(const [
      LiveViewerCountChanged('456'),
      LiveWatchedCountChanged('2万'),
    ]);
    expect(state().viewerCountText, '0');
    expect(state().watchedCountText, '1.3万');
    controller.setActive(true);
    repository.epoch++;
    repository.events.add(const [
      LiveViewerCountChanged('789'),
      LiveWatchedCountChanged('3万'),
    ]);
    expect(state().viewerCountText, '0');
    expect(state().watchedCountText, '1.3万');
    auth.events.add(const AuthState(status: AuthStatus.signedIn));
    await Future<void>.delayed(Duration.zero);
    expect(state().viewerCountText, isNull);
    expect(state().watchedCountText, isNull);
  });
  test(
    'room popularity keeps its load snapshot through heartbeats and reconnects',
    () async {
      for (final popularity in <int?>[34000, 0, null]) {
        repository.roomPopularity = popularity;
        await controller.load();
        expect(state().room?.popularity, popularity);
        for (final heartbeat in [1, 0, 99999]) {
          repository.events.add([
            LivePopularityChanged(heartbeat),
            const LiveRoomStatusChanged(true),
            const LiveViewerCountChanged('123'),
            const LiveWatchedCountChanged('1.2万'),
          ]);
          expect(state().room?.popularity, popularity);
          expect(state().viewerCountText, '123');
          expect(state().watchedCountText, '1.2万');
        }
        controller.setActive(false);
        controller.setActive(true);
        repository.events.add(const [
          LiveConnectionChanged(LiveConnectionPhase.connected),
          LivePopularityChanged(1),
        ]);
        expect(state().room?.popularity, popularity);
      }
    },
  );
  test('reloading a room clears both audience counts', () async {
    repository.events.add(const [
      LiveViewerCountChanged('123'),
      LiveWatchedCountChanged('1.2万'),
    ]);
    await controller.load();
    expect(state().viewerCountText, isNull);
    expect(state().watchedCountText, isNull);
  });
  test('badge-only updates replace one row and identical metadata publishes nothing', () {
    LiveChatMessage message({int level = 1, int userLevel = 42}) =>
        LiveChatMessage(
          id: 'one',
          userName: '观众',
          text: '内容',
          timestamp: now,
          medal: LiveFanMedal(name: '哔帆', level: level),
          userLevel: userLevel,
        );
    repository.events.add([LiveChatReceived(message())]);
    final initial = state();
    repository.events.add([LiveChatReceived(message(level: 2))]);
    expect(state().messages, hasLength(1));
    expect(state().messages.single.medal?.level, 2);
    expect(state().messages, isNot(same(initial.messages)));
    repository.events.add([LiveChatReceived(message(level: 2, userLevel: 43))]);
    expect(state().messages.single.userLevel, 43);
    final updated = state();
    repository.events.add([LiveChatReceived(message(level: 2, userLevel: 43))]);
    expect(state(), same(updated));
  });

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
  int? roomPopularity;
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
  }) async => LiveRoom(
    id: canonical,
    title: '直播',
    anchorName: '主播',
    isLive: true,
    popularity: roomPopularity,
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
