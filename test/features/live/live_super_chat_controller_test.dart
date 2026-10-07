import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/live/application/live_controller.dart';
import 'package:bilisail/features/live/domain/live_repository.dart';
import 'package:bilisail/features/live/domain/live_room.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const requested = RoomId('6');
const canonical = RoomId('7734200');
const room = LiveRoom(
  id: canonical,
  title: '测试房间',
  anchorName: '主播',
  isLive: true,
);

void main() {
  late _Repository repository;
  late _AuthRepository auth;
  late ProviderContainer container;
  late LiveController controller;
  late DateTime now;
  var containerDisposed = false;

  setUp(() async {
    containerDisposed = false;
    now = DateTime.utc(2026, 10, 5, 10);
    repository = _Repository();
    auth = _AuthRepository();
    container = ProviderContainer(
      overrides: [
        liveRepositoryProvider.overrideWithValue(repository),
        liveClockProvider.overrideWithValue(() => now),
        authRepositoryProvider.overrideWithValue(auth),
      ],
    );
    container.listen(liveControllerProvider(requested), (_, _) {});
    controller = container.read(liveControllerProvider(requested).notifier);
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() {
    if (!containerDisposed) container.dispose();
    auth.dispose();
  });

  LiveState current() => container.read(liveControllerProvider(requested));

  testWidgets('uses canonical ID, caps SC and expires it without a read', (
    tester,
  ) async {
    repository.superChats = List.generate(
      120,
      (index) => LiveSuperChatMessage(
        id: '$index',
        userName: '观众',
        text: '样本',
        price: 30,
        expiresAt: now.add(const Duration(seconds: 5)),
      ),
    );
    controller.setActive(true);
    await tester.pump();
    expect(repository.superChatId, canonical);
    expect(current().superChats, hasLength(100));
    expect(repository.superChatCalls, 1);

    now = now.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    expect(current().superChats, isEmpty);
    expect(repository.superChatCalls, 1);
    controller.setActive(false);
    container.dispose();
    containerDisposed = true;
  });

  test(
    'chat and SC failures stay independent and preserve prior data',
    () async {
      repository.chats = const [LiveChatMessage(userName: '观众', text: '聊天')];
      repository.superChats = const [
        LiveSuperChatMessage(id: '1', userName: '观众', text: '醒目留言', price: 50),
      ];
      controller.setActive(true);
      await Future<void>.delayed(Duration.zero);
      expect(current().messages.single.text, '聊天');
      expect(current().superChats.single.price, 50);

      repository.chatFailure = const AppFailure(
        AppFailureKind.network,
        '聊天网络中断',
      );
      await controller.refreshChat();
      expect(current().chatMessage, '聊天网络中断');
      expect(current().superChats.single.price, 50);

      repository.superChatFailure = const AppFailure(
        AppFailureKind.network,
        'SC 网络中断',
      );
      await controller.refreshSuperChats();
      expect(current().superChatMessage, 'SC 网络中断');
      expect(current().superChats.single.price, 50);
      expect(current().messages.single.text, '聊天');
    },
  );

  testWidgets(
    'duration-only SC expires once despite duplicate snapshots and failure',
    (tester) async {
      repository.superChats = const [
        LiveSuperChatMessage(
          id: 'duration',
          userName: '观众',
          text: '时长样本',
          price: 30,
          displayDuration: Duration(seconds: 5),
        ),
      ];
      controller.setActive(true);
      await tester.pump();
      final expiry = now.add(const Duration(seconds: 5));
      expect(current().superChats.single.expiresAt, expiry);
      now = now.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      await controller.refreshSuperChats();
      expect(current().superChats.single.expiresAt, expiry);
      repository.superChatFailure = const AppFailure(
        AppFailureKind.network,
        '暂不可用',
      );
      await controller.refreshSuperChats();
      now = expiry;
      await tester.pump(const Duration(seconds: 3));
      expect(current().superChats, isEmpty);
      repository.superChatFailure = null;
      await controller.refreshSuperChats();
      expect(current().superChats, isEmpty);
      controller.setActive(false);
      container.dispose();
      containerDisposed = true;
    },
  );

  testWidgets(
    'hidden time counts toward expiry and resume prunes immediately',
    (tester) async {
      repository.superChats = [
        LiveSuperChatMessage(
          id: 'hidden',
          userName: '观众',
          text: '样本',
          price: 30,
          expiresAt: now.add(const Duration(seconds: 3)),
        ),
      ];
      controller.setActive(true);
      await tester.pump();
      controller.setActive(false);
      now = now.add(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 4));
      controller.setActive(true);
      expect(current().superChats, isEmpty);
      await tester.pump();
      expect(current().superChats, isEmpty);
      controller.setActive(false);
      container.dispose();
      containerDisposed = true;
    },
  );

  testWidgets(
    'HTTP remaining time uses receipt instead of the original start',
    (tester) async {
      repository.superChats = [
        LiveSuperChatMessage(
          id: 'remaining',
          userName: '观众',
          text: '样本',
          price: 30,
          startedAt: now.subtract(const Duration(minutes: 10)),
          remainingDuration: const Duration(seconds: 3),
        ),
      ];
      controller.setActive(true);
      await tester.pump();
      final expiry = now.add(const Duration(seconds: 3));
      expect(current().superChats.single.expiresAt, expiry);
      now = expiry;
      await tester.pump(const Duration(seconds: 3));
      expect(current().superChats, isEmpty);
      controller.setActive(false);
      container.dispose();
      containerDisposed = true;
    },
  );

  test('hiding cancels an SC read and rejects its late response', () async {
    final pending = Completer<List<LiveSuperChatMessage>>();
    repository.pendingSuperChats = pending;
    controller.setActive(true);
    final signal = repository.superChatCancellation;
    controller.setActive(false);
    expect(signal?.isCancelled, true);
    pending.complete(const [
      LiveSuperChatMessage(id: 'old', userName: '旧观众', text: '迟到', price: 30),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(current().superChats, isEmpty);
    expect(current().superChatLoading, false);
  });

  test('account transition cancels SC and rejects the old epoch', () async {
    final pending = Completer<List<LiveSuperChatMessage>>();
    repository.pendingSuperChats = pending;
    controller.setActive(true);
    final signal = repository.superChatCancellation;

    repository.scope = 'account-b';
    repository.epoch++;
    repository.pendingSuperChats = null;
    repository.superChats = const [
      LiveSuperChatMessage(id: 'new', userName: '新观众', text: '新消息', price: 80),
    ];
    auth.emit(const AuthState(status: AuthStatus.signedIn));
    await Future<void>.delayed(Duration.zero);
    expect(signal?.isCancelled, true);
    pending.complete(const [
      LiveSuperChatMessage(id: 'old', userName: '旧观众', text: '旧消息', price: 30),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(current().superChats.single.id, 'new');
  });

  test(
    'failed room refresh clears cancelled SC loading and allows retry',
    () async {
      repository.superChats = const [
        LiveSuperChatMessage(id: '1', userName: '观众', text: '已有', price: 30),
      ];
      controller.setActive(true);
      await Future<void>.delayed(Duration.zero);
      final pending = Completer<List<LiveSuperChatMessage>>();
      repository.pendingSuperChats = pending;
      final oldRefresh = controller.refreshSuperChats();
      repository.roomFailure = const AppFailure(
        AppFailureKind.network,
        '房间暂不可用',
      );
      await controller.load();
      expect(current().superChatLoading, false);
      expect(current().superChats.single.id, '1');

      repository.pendingSuperChats = null;
      repository.roomFailure = null;
      repository.superChats = const [
        LiveSuperChatMessage(id: '2', userName: '观众', text: '重试', price: 50),
      ];
      await controller.refreshSuperChats();
      pending.complete(const [
        LiveSuperChatMessage(id: 'old', userName: '旧观众', text: '迟到', price: 30),
      ]);
      await oldRefresh;
      expect(current().superChats.single.id, '2');
    },
  );
}

final class _Repository implements LiveRepository {
  String scope = 'guest';
  int epoch = 0;
  List<LiveChatMessage> chats = const [];
  List<LiveSuperChatMessage> superChats = const [];
  Completer<List<LiveSuperChatMessage>>? pendingSuperChats;
  RequestCancellation? superChatCancellation;
  RoomId? superChatId;
  int superChatCalls = 0;
  AppFailure? chatFailure, superChatFailure;
  AppFailure? roomFailure;

  @override
  String get accountScope => scope;
  @override
  int get sessionEpoch => epoch;

  @override
  Future<LiveRoom> loadRoom(
    RoomId id, {
    required RequestCancellation cancellation,
  }) {
    if (roomFailure case final error?) return Future.error(error);
    return Future.value(room);
  }

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
  }) {
    if (chatFailure case final error?) return Future.error(error);
    return Future.value(chats);
  }

  @override
  Future<List<LiveSuperChatMessage>> loadSuperChats(
    RoomId id, {
    required RequestCancellation cancellation,
  }) {
    superChatId = id;
    superChatCancellation = cancellation;
    superChatCalls++;
    if (superChatFailure case final error?) return Future.error(error);
    return pendingSuperChats?.future ?? Future.value(superChats);
  }
}

final class _AuthRepository implements AuthRepository {
  final StreamController<AuthState> _changes = StreamController.broadcast();
  AuthState _current = const AuthState();

  void emit(AuthState state) {
    _current = state;
    _changes.add(state);
  }

  void dispose() => _changes.close();

  @override
  Stream<AuthState> get changes => _changes.stream;
  @override
  AuthState get current => _current;
  @override
  Future<void> restore() async {}
  @override
  Future<void> signIn() async {}
  @override
  Future<void> signOut() async {}
  @override
  void cancelSignIn() {}
}
