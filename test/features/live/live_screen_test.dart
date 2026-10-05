import 'dart:async';

import 'package:bili_lite/domain/app_failure.dart';
import 'package:bili_lite/domain/request_cancellation.dart';
import 'package:bili_lite/domain/user.dart';
import 'package:bili_lite/features/auth/application/auth_controller.dart';
import 'package:bili_lite/features/auth/domain/auth_repository.dart';
import 'package:bili_lite/features/live/application/live_controller.dart';
import 'package:bili_lite/features/live/domain/live_repository.dart';
import 'package:bili_lite/features/live/domain/live_chat_repository.dart';
import 'package:bili_lite/features/live/domain/live_room.dart';
import 'package:bili_lite/features/live/presentation/live_screen.dart';
import 'package:bili_lite/features/live/presentation/live_player_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const room = LiveRoom(
  id: RoomId('12'),
  title: '直播间标题',
  anchorName: '主播甲',
  anchorId: UserId('123'),
  description: '这里是完整的直播间简介',
  isLive: true,
  popularity: 34000,
);
const superChats = [
  LiveSuperChatMessage(
    id: 'sc-1',
    userName: '观众甲',
    userId: UserId('456'),
    text: '第一条完整的 SC 内容',
    price: 50,
  ),
  LiveSuperChatMessage(
    id: 'sc-2',
    userName: '观众乙',
    text: '第二条完整的 SC 内容',
    price: 100,
  ),
];

void main() {
  late _Repository repository;
  late _RealtimeRepository realtime;
  late ProviderContainer container;

  setUp(() {
    repository = _Repository();
    realtime = _RealtimeRepository();
    container = ProviderContainer(
      overrides: [
        liveRepositoryProvider.overrideWithValue(repository),
        liveChatRepositoryProvider.overrideWithValue(realtime),
        authRepositoryProvider.overrideWithValue(_AuthRepository()),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await realtime.events.close();
  });

  Future<void> showPage(
    WidgetTester tester, {
    double width = 1280,
    double height = 800,
    double textScale = 1,
    LivePlayerBuilder? playerBuilder,
    ValueChanged<UserId>? onOpenUser,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, height));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              body: LiveScreen(
                roomId: '12',
                onOpenUser: onOpenUser,
                playerBuilder: playerBuilder ?? (_, _) => const _PlayerProbe(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('unmount stops realtime even when the controller stays alive', (
    tester,
  ) async {
    await showPage(tester);
    final subscription = container.listen(
      liveControllerProvider(room.id),
      (_, _) {},
    );
    addTearDown(subscription.close);
    final controller = container.read(liveControllerProvider(room.id).notifier);
    final messages = container.read(liveControllerProvider(room.id)).messages;
    expect(realtime.events.hasListener, isTrue);
    expect(realtime.reads.single.isCancelled, isFalse);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Text('replacement')),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.isMounted, isTrue);
    expect(realtime.reads.single.isCancelled, isTrue);
    expect(realtime.events.hasListener, isFalse);
    expect(
      container.read(liveControllerProvider(room.id)).connectionPhase,
      LiveConnectionPhase.closed,
    );
    realtime.events.add(const [
      LiveChatReceived(LiveChatMessage(userName: 'late', text: 'late event')),
    ]);
    await tester.pump(const Duration(seconds: 21));
    expect(container.read(liveControllerProvider(room.id)).messages, messages);
    expect(realtime.opens, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'anchor and chat names open the correct profile and description is removed',
    (tester) async {
      repository.chatMessages = const [
        LiveChatMessage(
          userName: '可点击观众',
          userId: UserId('9007199254740993'),
          text: '普通聊天消息',
        ),
        LiveChatMessage(userName: '无UID观众', text: '匿名消息'),
      ];
      final opened = <UserId>[];
      await showPage(tester, onOpenUser: opened.add);
      expect(find.text('展开简介'), findsNothing);
      expect(find.text('收起简介'), findsNothing);
      expect(find.text(room.description), findsNothing);
      expect(find.byTooltip('查看主播主页'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('live-anchor-avatar')));
      await tester.tap(find.byKey(const ValueKey('live-anchor-name')));
      await tester.tap(find.text('可点击观众'));
      await tester.tap(find.text('无UID观众'));
      expect(opened, [
        const UserId('123'),
        const UserId('123'),
        const UserId('9007199254740993'),
      ]);

      await tester.tap(find.byKey(const ValueKey('live-sc-chip-sc-1')));
      await tester.pump();
      await tester.tap(find.text('观众甲'));
      expect(opened.last, const UserId('456'));
    },
  );

  testWidgets(
    'viewer display updates at the top right and popularity stays separate',
    (tester) async {
      await showPage(tester);
      expect(find.text('观看人数暂无数据'), findsOneWidget);
      expect(find.text('当前34000人在看'), findsNothing);
      final player = tester.state(find.byType(_PlayerProbe));
      realtime.events.add(const [
        LiveViewerCountChanged('2.3万'),
        LivePopularityChanged(99),
      ]);
      await tester.pump();
      expect(find.text('当前2.3万人在看'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('live-viewer-count'))).dx,
        greaterThan(
          tester
              .getTopRight(find.byKey(const ValueKey('live-anchor-avatar')))
              .dx,
        ),
      );
      expect(tester.state(find.byType(_PlayerProbe)), same(player));
      realtime.events.add(const [LiveViewerCountChanged('0')]);
      await tester.pump();
      expect(find.text('当前0人在看'), findsOneWidget);
    },
  );

  testWidgets('chat bubbles expand one SC and tab shows the same full cards', (
    tester,
  ) async {
    await showPage(tester);
    expect(find.text('历史消息 · 定时刷新'), findsOneWidget);
    expect(find.text('SC (2)'), findsOneWidget);
    expect(find.byKey(const ValueKey('live-sc-chip-sc-1')), findsOneWidget);

    final player = tester.state(find.byType(_PlayerProbe));
    await tester.tap(find.byKey(const ValueKey('live-sc-chip-sc-1')));
    await tester.pump();
    expect(find.text('第一条完整的 SC 内容'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('live-sc-chip-sc-2')));
    await tester.pump();
    expect(find.text('第一条完整的 SC 内容'), findsNothing);
    expect(find.text('第二条完整的 SC 内容'), findsOneWidget);
    await tester.tap(find.text('关闭 SC 详情'));
    await tester.pump();
    expect(find.text('第二条完整的 SC 内容'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('live-tab-1')));
    await tester.pump();
    expect(find.text('共 2 条 SC'), findsOneWidget);
    expect(find.text('第一条完整的 SC 内容'), findsOneWidget);
    expect(find.text('第二条完整的 SC 内容'), findsOneWidget);
    expect(tester.state(find.byType(_PlayerProbe)), same(player));

    await tester.tap(find.byTooltip('收起直播信息'));
    await tester.pump();
    expect(tester.state(find.byType(_PlayerProbe)), same(player));
    await tester.tap(find.byTooltip('展开直播信息'));
    await tester.pump();
    expect(find.text('共 2 条 SC'), findsOneWidget);
    expect(tester.state(find.byType(_PlayerProbe)), same(player));
  });

  testWidgets('320 px with large text keeps chat and SC reachable', (
    tester,
  ) async {
    await showPage(tester, width: 320, height: 740, textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('live-tab-0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('live-sc-chip-sc-1')));
    await tester.pump();
    expect(find.text('第一条完整的 SC 内容'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('live-tab-1')));
    await tester.pump();
    expect(find.text('共 2 条 SC'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsing the sidebar keeps chat scroll position', (
    tester,
  ) async {
    repository.chatMessages = List.generate(
      60,
      (index) => LiveChatMessage(userName: '观众', text: '聊天消息 $index'),
    );
    await showPage(tester);
    final chatList = find.byKey(const ValueKey('live-chat-list'));
    await tester.drag(chatList, const Offset(0, -280));
    await tester.pump();
    final scrollable = find.descendant(
      of: chatList,
      matching: find.byType(Scrollable),
    );
    final before = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(before, greaterThan(0));

    await tester.tap(find.byTooltip('收起直播信息'));
    await tester.pump();
    await tester.tap(find.byTooltip('展开直播信息'));
    await tester.pump();
    final after = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(after, before);

    await tester.tap(find.byKey(const ValueKey('live-sc-chip-sc-1')));
    await tester.pump();
    await tester.pump();
    expect(tester.state<ScrollableState>(scrollable).position.pixels, 0);
    expect(
      find.byKey(const ValueKey('live-sc-card-sc-1')).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('SC failure is visible in both tabs instead of an empty state', (
    tester,
  ) async {
    repository.superChatFailure = const AppFailure(
      AppFailureKind.network,
      'SC 暂时无法更新',
    );
    await showPage(tester);
    expect(find.text('SC 暂时无法更新'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('live-tab-1')));
    await tester.pump();
    expect(find.text('SC 暂时无法更新'), findsOneWidget);
    expect(find.text('暂无 SC'), findsNothing);
  });

  testWidgets('realtime status, explicit reconnect and background cleanup', (
    tester,
  ) async {
    await showPage(tester);
    expect(realtime.opens, 1);
    realtime.events.add(const [
      LiveConnectionChanged(LiveConnectionPhase.connected),
      LiveChatReceived(LiveChatMessage(userName: '观众丙', text: '实时收到的消息')),
    ]);
    await tester.pump();
    await tester.pump();
    expect(find.text('实时弹幕已连接'), findsOneWidget);
    expect(find.textContaining('实时收到的消息'), findsOneWidget);
    realtime.events.add(const [
      LiveConnectionChanged(LiveConnectionPhase.failed, message: '连接测试失败'),
    ]);
    await tester.pump();
    expect(find.text('连接测试失败'), findsOneWidget);
    await tester.tap(find.byTooltip('重新连接弹幕'));
    await tester.pump();
    expect(realtime.opens, 2);
    expect(realtime.reads.first.isCancelled, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    await tester.pump();
    expect(realtime.reads.last.isCancelled, isTrue);
    realtime.events.add(const [
      LiveChatReceived(LiveChatMessage(userName: '观众丙', text: '后台旧连接消息')),
    ]);
    await tester.pump();
    expect(find.textContaining('后台旧连接消息'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(realtime.opens, 3);
  });

  testWidgets('short room ID keeps player on the sidebar message controller', (
    tester,
  ) async {
    repository.canonicalRoom = const LiveRoom(
      id: RoomId('12345'),
      title: '真实房间',
      anchorName: '主播',
      isLive: true,
    );
    RoomId? requested;
    RoomId? canonical;
    await showPage(
      tester,
      playerBuilder: (context, room) {
        requested = LiveDanmakuRoomScope.requestedIdOf(context);
        canonical = room.id;
        return const _PlayerProbe();
      },
    );
    expect(requested, const RoomId('12'));
    expect(canonical, const RoomId('12345'));
    expect(realtime.opens, 1);
  });
}

final class _RealtimeRepository implements LiveChatRepository {
  final events = StreamController<List<LiveRealtimeEvent>>.broadcast(
    sync: true,
  );
  final reads = <RequestCancellation>[];
  int opens = 0;

  @override
  Stream<List<LiveRealtimeEvent>> watchRoom(
    RoomId id, {
    required RequestCancellation cancellation,
  }) {
    opens++;
    reads.add(cancellation);
    return events.stream;
  }
}

final class _Repository implements LiveRepository {
  AppFailure? superChatFailure;
  LiveRoom? canonicalRoom;
  List<LiveChatMessage> chatMessages = const [
    LiveChatMessage(userName: '普通观众', text: '普通聊天消息'),
  ];

  @override
  String get accountScope => 'guest';
  @override
  int get sessionEpoch => 0;

  @override
  Future<LiveRoom> loadRoom(
    RoomId id, {
    required RequestCancellation cancellation,
  }) async => canonicalRoom ?? room;

  @override
  Future<LivePlayInfo> loadPlayInfo(
    RoomId id, {
    int quality = 10000,
    required RequestCancellation cancellation,
  }) async =>
      const LivePlayInfo(roomId: RoomId('12'), isLive: true, streams: []);

  @override
  Future<List<LiveChatMessage>> loadChatHistory(
    RoomId id, {
    required RequestCancellation cancellation,
  }) async => chatMessages;

  @override
  Future<List<LiveSuperChatMessage>> loadSuperChats(
    RoomId id, {
    required RequestCancellation cancellation,
  }) async {
    if (superChatFailure case final failure?) throw failure;
    return superChats;
  }
}

final class _AuthRepository implements AuthRepository {
  @override
  Stream<AuthState> get changes => const Stream.empty();
  @override
  AuthState get current => const AuthState();
  @override
  Future<void> restore() async {}
  @override
  Future<void> signIn() async {}
  @override
  Future<void> signOut() async {}
  @override
  void cancelSignIn() {}
}

final class _PlayerProbe extends StatefulWidget {
  const _PlayerProbe();

  @override
  State<_PlayerProbe> createState() => _PlayerProbeState();
}

final class _PlayerProbeState extends State<_PlayerProbe> {
  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black);
}
