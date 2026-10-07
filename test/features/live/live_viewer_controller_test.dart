import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
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

void main() {
  late _Rooms rooms;
  late _Viewers viewers;
  late _Auth auth;
  late ProviderContainer container;
  late LiveController controller;
  var now = DateTime.utc(2026, 10, 7);
  LiveState state() =>
      container.read(liveControllerProvider(const RoomId('7777')));
  Future<void> start(WidgetTester tester, {int? count}) async {
    now = DateTime.utc(2026, 10, 7);
    rooms = _Rooms();
    viewers = _Viewers()..count = count;
    auth = _Auth();
    container = ProviderContainer(
      overrides: [
        liveRepositoryProvider.overrideWithValue(rooms),
        liveChatRepositoryProvider.overrideWithValue(rooms),
        liveViewerRepositoryProvider.overrideWithValue(viewers),
        authRepositoryProvider.overrideWithValue(auth),
        liveClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await rooms.events.close();
      await auth.events.close();
    });
    container.listen(liveControllerProvider(const RoomId('7777')), (_, _) {});
    controller = container.read(
      liveControllerProvider(const RoomId('7777')).notifier,
    );
    await tester.pump();
    controller.setActive(true);
    await tester.pump();
  }

  testWidgets(
    'initial exact snapshot survives capped WS but not newer precise WS',
    (tester) async {
      await start(tester, count: 19357);
      expect(viewers.room, const RoomId('545068'));
      expect(viewers.anchor, const UserId('8739477'));
      expect(state().viewerCountText, '19357');
      rooms.events.add(const [
        LiveViewerCountChanged('9999'),
        LiveWatchedCountChanged('3万'),
        LivePopularityChanged(80000),
      ]);
      expect(state().viewerCountText, '19357');
      expect(state().watchedCountText, '3万');
      expect(state().room?.popularity, 80000);
      rooms.events.add(const [LiveViewerCountChanged('1万+')]);
      expect(state().viewerCountText, '19357');
      rooms.events.add(const [LiveViewerCountChanged('20100')]);
      expect(state().viewerCountText, '20100');
      controller.setActive(false);
    },
  );

  testWidgets(
    'periodic refresh is single flight and late snapshot preserves newer WS',
    (tester) async {
      await start(tester, count: 19357);
      final pending = Completer<int?>();
      viewers.pending = pending;
      await tester.pump(LiveController.chatRefreshInterval);
      expect(viewers.reads, 2);
      final sameRead = controller.refreshViewerCount();
      expect(viewers.reads, 2);
      rooms.events.add(const [LiveViewerCountChanged('20200')]);
      pending.complete(19400);
      await sameRead;
      await tester.pump();
      expect(state().viewerCountText, '20200');
      controller.setActive(false);
    },
  );

  testWidgets(
    'hidden/reloaded/offline room cancels and rejects late viewer reads',
    (tester) async {
      await start(tester, count: 19357);
      for (final transition in ['hidden', 'reload', 'offline']) {
        if (transition == 'reload') {
          controller.setActive(true);
          await tester.pump();
        }
        final pending = Completer<int?>();
        viewers.pending = pending;
        final read = controller.refreshViewerCount();
        final cancellation = viewers.cancellation;
        if (transition == 'hidden') controller.setActive(false);
        if (transition == 'reload') {
          viewers.pending = null;
          viewers.count = 20000;
          await controller.load();
        }
        if (transition == 'offline') {
          rooms.events.add(const [LiveRoomStatusChanged(false)]);
        }
        expect(cancellation?.isCancelled, true);
        pending.complete(999999);
        await read;
        expect(state().viewerCountText, isNot('999999'));
        viewers.pending = null;
      }
      controller.setActive(false);
    },
  );

  testWidgets('old account and session epoch cannot publish a late snapshot', (
    tester,
  ) async {
    await start(tester, count: 19357);
    final pending = Completer<int?>();
    viewers.pending = pending;
    final read = controller.refreshViewerCount();
    rooms.scope = 'new';
    rooms.epoch++;
    pending.complete(22222);
    await read;
    expect(state().viewerCountText, '19357');
    viewers.pending = null;
    viewers.count = null;
    auth.events.add(const AuthState(status: AuthStatus.signedIn));
    await tester.pump();
    expect(state().viewerCountText, isNull);
    controller.setActive(false);
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets(
    'higher realtime lower bound rejects a lower existing or delayed snapshot',
    (tester) async {
      await start(tester, count: 12000);
      final pending = Completer<int?>();
      viewers.pending = pending;
      final read = controller.refreshViewerCount();
      rooms.events.add(const [LiveViewerCountChanged('2万+')]);
      expect(state().viewerCountText, '2万+');
      pending.complete(12500);
      await read;
      expect(state().viewerCountText, '2万+');
      viewers.pending = null;
      viewers.count = 21000;
      await controller.refreshViewerCount();
      expect(state().viewerCountText, '21000');
      controller.setActive(false);
    },
  );

  testWidgets(
    'precise WS decrease invalidates protection from accepted and delayed HTTP',
    (tester) async {
      await start(tester, count: 19357);
      rooms.events.add(const [LiveViewerCountChanged('8000')]);
      rooms.events.add(const [LiveViewerCountChanged('9999+')]);
      expect(state().viewerCountText, '9999+');
      final pending = Completer<int?>();
      viewers.pending = pending;
      final read = controller.refreshViewerCount();
      rooms.events.add(const [LiveViewerCountChanged('8000')]);
      pending.complete(19357);
      await read;
      expect(state().viewerCountText, '8000');
      rooms.events.add(const [LiveViewerCountChanged('9999+')]);
      expect(state().viewerCountText, '9999+');
      controller.setActive(false);
    },
  );

  testWidgets(
    'new HTTP may replace an older WS lower bound and its own exact 9999',
    (tester) async {
      await start(tester);
      rooms.events.add(const [LiveViewerCountChanged('2万+')]);
      viewers.count = 19500;
      await controller.refreshViewerCount();
      expect(state().viewerCountText, '19500');
      viewers.count = 9999;
      await controller.refreshViewerCount();
      expect(state().viewerCountText, '9999');
      viewers.count = 9998;
      await controller.refreshViewerCount();
      expect(state().viewerCountText, '9998');
      controller.setActive(false);
    },
  );

  testWidgets(
    'failed optional count keeps WS value and rate limiting stops polling',
    (tester) async {
      await start(tester);
      rooms.events.add(const [LiveViewerCountChanged('1万+')]);
      viewers.failure = const AppFailure(AppFailureKind.network, '网络故障');
      await controller.refreshViewerCount();
      expect(state().viewerCountText, '1万+');
      viewers.failure = const AppFailure(AppFailureKind.rateLimited, '限流');
      await controller.refreshViewerCount();
      final reads = viewers.reads;
      await tester.pump(LiveController.chatRefreshInterval * 2);
      expect(viewers.reads, reads);
      expect(state().roomMessage, isNull);
      viewers.failure = null;
      viewers.count = 21000;
      await controller.load();
      expect(state().viewerCountText, '21000');
      controller.setActive(false);
    },
  );

  testWidgets(
    'zero remains valid and stale snapshot no longer masks capped WS',
    (tester) async {
      await start(tester, count: 0);
      expect(state().viewerCountText, '0');
      rooms.events.add(const [LiveViewerCountChanged('9999+')]);
      expect(state().viewerCountText, '9999+');
      viewers.count = 19000;
      await controller.refreshViewerCount();
      now = now.add(const Duration(seconds: 41));
      rooms.events.add(const [LiveViewerCountChanged('1万+')]);
      expect(state().viewerCountText, '1万+');
      controller.setActive(false);
    },
  );
}

final class _Viewers implements LiveViewerRepository {
  int? count;
  int reads = 0;
  Completer<int?>? pending;
  AppFailure? failure;
  RoomId? room;
  UserId? anchor;
  RequestCancellation? cancellation;
  @override
  Future<int?> loadViewerCount(
    RoomId id,
    UserId anchorId, {
    required RequestCancellation cancellation,
  }) async {
    reads++;
    room = id;
    anchor = anchorId;
    this.cancellation = cancellation;
    final error = failure;
    if (error != null) throw error;
    final response = pending;
    return response == null ? count : await response.future;
  }
}

final class _Rooms implements LiveRepository, LiveChatRepository {
  final events = StreamController<List<LiveRealtimeEvent>>.broadcast(
    sync: true,
  );
  String scope = 'guest';
  int epoch = 0;
  @override
  String get accountScope => scope;
  @override
  int get sessionEpoch => epoch;
  @override
  Stream<List<LiveRealtimeEvent>> watchRoom(
    RoomId id, {
    required RequestCancellation cancellation,
  }) => events.stream;
  @override
  Future<LiveRoom> loadRoom(
    RoomId id, {
    required RequestCancellation cancellation,
  }) async => const LiveRoom(
    id: RoomId('545068'),
    title: '直播',
    anchorName: '主播',
    anchorId: UserId('8739477'),
    isLive: true,
  );
  @override
  Future<LivePlayInfo> loadPlayInfo(
    RoomId id, {
    int quality = 10000,
    required RequestCancellation cancellation,
  }) async =>
      const LivePlayInfo(roomId: RoomId('545068'), isLive: true, streams: []);
  @override
  Future<List<LiveChatMessage>> loadChatHistory(
    RoomId id, {
    required RequestCancellation cancellation,
  }) async => [];
  @override
  Future<List<LiveSuperChatMessage>> loadSuperChats(
    RoomId id, {
    required RequestCancellation cancellation,
  }) async => [];
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
