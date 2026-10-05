import 'dart:async';

import 'package:bili_lite/domain/app_failure.dart';
import 'package:bili_lite/domain/request_cancellation.dart';
import 'package:bili_lite/core/presentation/workspace_activity.dart';
import 'package:bili_lite/features/auth/application/auth_controller.dart';
import 'package:bili_lite/features/auth/domain/auth_repository.dart';
import 'package:bili_lite/features/live/application/live_controller.dart';
import 'package:bili_lite/features/live/domain/live_repository.dart';
import 'package:bili_lite/features/live/domain/live_room.dart';
import 'package:bili_lite/features/live/presentation/live_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const requested = RoomId('12');
const canonical = RoomId('12345');
const room = LiveRoom(
  id: canonical,
  title: '测试直播间',
  anchorName: '主播甲',
  isLive: true,
  description: '直播间简介',
  areaName: '游戏',
  popularity: 18000,
);

void main() {
  late _Repository repository;
  late _AuthRepository auth;
  late ProviderContainer container;
  late LiveController controller;

  setUp(() async {
    repository = _Repository();
    auth = _AuthRepository();
    container = ProviderContainer(
      overrides: [
        liveRepositoryProvider.overrideWithValue(repository),
        authRepositoryProvider.overrideWithValue(auth),
      ],
    );
    container.listen(liveControllerProvider(requested), (_, _) {});
    controller = container.read(liveControllerProvider(requested).notifier);
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() {
    container.dispose();
    auth.dispose();
  });

  LiveState current() => container.read(liveControllerProvider(requested));

  test('uses canonical room ID for chat and caps retained messages', () async {
    repository.messages = List.generate(
      520,
      (index) => LiveChatMessage(userName: '观众', text: '$index', id: '$index'),
    );
    controller.setActive(true);
    await Future<void>.delayed(Duration.zero);
    expect(repository.chatId, canonical);
    expect(current().messages.length, 500);
    expect(current().messages.first.text, '20');
    await controller.refreshChat();
    expect(current().messages.length, 500);
  });

  test('new room request cancels and rejects an older response', () async {
    final pending = Completer<LiveRoom>();
    repository.pendingRoom = pending;
    final old = controller.load();
    final oldSignal = repository.roomCancellation;
    repository.pendingRoom = null;
    await controller.load();
    expect(oldSignal?.isCancelled, true);
    pending.complete(
      const LiveRoom(
        id: RoomId('99'),
        title: '过期直播间',
        anchorName: '旧主播',
        isLive: false,
      ),
    );
    await old;
    expect(current().room?.id, canonical);
  });

  test('hidden page cancels chat and ignores its late response', () async {
    final pending = Completer<List<LiveChatMessage>>();
    repository.pendingChat = pending;
    controller.setActive(true);
    final oldSignal = repository.chatCancellation;
    controller.setActive(false);
    expect(oldSignal?.isCancelled, true);
    pending.complete(const [LiveChatMessage(userName: '旧观众', text: '迟到')]);
    await Future<void>.delayed(Duration.zero);
    expect(current().messages, isEmpty);
    expect(current().chatLoading, false);
  });

  test(
    'account transition clears room and rejects old chat response',
    () async {
      final pending = Completer<List<LiveChatMessage>>();
      repository.pendingChat = pending;
      controller.setActive(true);
      final oldSignal = repository.chatCancellation;
      repository.epoch++;
      repository.scope = 'account-b';
      repository.pendingChat = null;
      auth.emit(const AuthState(status: AuthStatus.signedIn));
      await Future<void>.delayed(Duration.zero);
      expect(oldSignal?.isCancelled, true);
      pending.complete(const [LiveChatMessage(userName: '旧观众', text: '旧消息')]);
      await Future<void>.delayed(Duration.zero);
      expect(current().messages, isEmpty);
      expect(current().room?.id, canonical);
    },
  );

  test('chat failure keeps previously loaded messages', () async {
    repository.messages = const [
      LiveChatMessage(userName: '观众', text: '已加载', id: '1'),
    ];
    controller.setActive(true);
    await Future<void>.delayed(Duration.zero);
    repository.failure = const AppFailure(AppFailureKind.network, '网络中断');
    await controller.refreshChat();
    expect(current().messages.single.text, '已加载');
    expect(current().chatMessage, '网络中断');
  });

  testWidgets('responsive room page shows real room details and player', (
    tester,
  ) async {
    var playerBuilds = 0;
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: LiveScreen(
              roomId: requested.value,
              playerBuilder: (_, _) {
                playerBuilds++;
                return const ColoredBox(color: Colors.black);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('测试直播间'), findsOneWidget);
    expect(find.text('房间号 12345'), findsOneWidget);
    expect(find.text('历史消息 · 定时刷新'), findsOneWidget);
    expect(playerBuilds, greaterThan(0));
    final readsBeforeTick = repository.chatCalls;
    await tester.pump(const Duration(seconds: 20));
    await tester.pump();
    expect(repository.chatCalls, readsBeforeTick + 1);
    await tester.binding.setSurfaceSize(const Size(390, 800));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('crossing compact threshold preserves player State', (
    tester,
  ) async {
    var initialized = 0;
    var disposed = 0;
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: LiveScreen(
              roomId: requested.value,
              playerBuilder: (_, _) => _PlayerProbe(
                onInitialize: () => initialized++,
                onDispose: () => disposed++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(initialized, 1);
    expect(disposed, 0);
    final originalState = tester.state(find.byType(_PlayerProbe));

    await tester.binding.setSurfaceSize(const Size(390, 800));
    await tester.pump();
    expect(tester.state(find.byType(_PlayerProbe)), same(originalState));
    expect(initialized, 1);
    expect(disposed, 0);

    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pump();
    expect(tester.state(find.byType(_PlayerProbe)), same(originalState));
    expect(initialized, 1);
    expect(disposed, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden workspace stops chat and offline room omits player', (
    tester,
  ) async {
    repository.loadedRoom = const LiveRoom(
      id: canonical,
      title: '已下播直播间',
      anchorName: '主播甲',
      isLive: false,
    );
    await controller.load();
    final pending = Completer<List<LiveChatMessage>>();
    repository.pendingChat = pending;
    var playerBuilds = 0;
    Widget screen(bool active) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: WorkspaceActivity(
          active: active,
          child: Scaffold(
            body: LiveScreen(
              roomId: requested.value,
              playerBuilder: (_, _) {
                playerBuilds++;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(screen(true));
    await tester.pump();
    expect(find.text('主播尚未开播'), findsOneWidget);
    expect(playerBuilds, 0);
    final signal = repository.chatCancellation;
    final readsBeforeHide = repository.chatCalls;
    await tester.pumpWidget(screen(false));
    await tester.pump();
    expect(signal?.isCancelled, true);
    await tester.pump(const Duration(seconds: 45));
    expect(repository.chatCalls, readsBeforeHide);
    pending.complete(const [LiveChatMessage(userName: '旧观众', text: '迟到')]);
    await tester.pump();
    expect(current().messages, isEmpty);
  });
}

final class _Repository implements LiveRepository {
  String scope = 'guest';
  int epoch = 0;
  Completer<LiveRoom>? pendingRoom;
  Completer<List<LiveChatMessage>>? pendingChat;
  RequestCancellation? roomCancellation, chatCancellation;
  List<LiveChatMessage> messages = const [];
  LiveRoom loadedRoom = room;
  RoomId? chatId;
  int chatCalls = 0;
  AppFailure? failure;

  @override
  String get accountScope => scope;
  @override
  int get sessionEpoch => epoch;

  @override
  Future<LiveRoom> loadRoom(
    RoomId id, {
    required RequestCancellation cancellation,
  }) {
    roomCancellation = cancellation;
    return pendingRoom?.future ?? Future.value(loadedRoom);
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
    chatCalls++;
    chatId = id;
    chatCancellation = cancellation;
    if (failure case final error?) return Future.error(error);
    return pendingChat?.future ?? Future.value(messages);
  }

  @override
  Future<List<LiveSuperChatMessage>> loadSuperChats(
    RoomId id, {
    required RequestCancellation cancellation,
  }) async => const [];
}

final class _PlayerProbe extends StatefulWidget {
  const _PlayerProbe({required this.onInitialize, required this.onDispose});

  final VoidCallback onInitialize, onDispose;

  @override
  State<_PlayerProbe> createState() => _PlayerProbeState();
}

final class _PlayerProbeState extends State<_PlayerProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInitialize();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black);
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
