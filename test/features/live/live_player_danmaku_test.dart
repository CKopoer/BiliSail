import 'dart:async';

import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:bili_lite/core/presentation/workspace_activity.dart';
import 'package:bili_lite/domain/request_cancellation.dart';
import 'package:bili_lite/features/auth/application/auth_controller.dart';
import 'package:bili_lite/features/auth/domain/auth_repository.dart';
import 'package:bili_lite/features/live/application/live_controller.dart';
import 'package:bili_lite/features/live/domain/live_chat_repository.dart';
import 'package:bili_lite/features/live/domain/live_repository.dart';
import 'package:bili_lite/features/live/domain/live_room.dart';
import 'package:bili_lite/features/live/presentation/live_player_danmaku.dart';
import 'package:bili_lite/features/settings/domain/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _Realtime realtime;
  late ProviderContainer container;
  const requested = RoomId('6');
  const canonical = RoomId('12345');

  setUp(() {
    realtime = _Realtime();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_Auth()),
        liveRepositoryProvider.overrideWithValue(_Rooms()),
        liveChatRepositoryProvider.overrideWithValue(realtime),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await realtime.events.close();
  });

  Future<void> show(
    WidgetTester tester, {
    bool active = true,
    double topMargin = 0,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: WorkspaceActivity(
              active: active,
              child: LiveDanmakuRoomScope(
                requestedId: requested,
                child: Center(
                  child: SizedBox(
                    width: 600,
                    height: 240,
                    child: LivePlayerDanmaku(
                      roomId: canonical,
                      settings: AppSettings(
                        danmakuBlockedWords: const ['屏蔽'],
                        danmakuTopEnabled: false,
                        danmakuTopMargin: topMargin,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  LiveDanmakuController drawing(WidgetTester tester) => tester
      .widget<LiveDanmakuOverlay>(find.byType(LiveDanmakuOverlay))
      .controller;

  testWidgets('live overlay applies top margin updates to new messages', (
    tester,
  ) async {
    await show(tester, topMargin: 40);
    final controller = container.read(
      liveControllerProvider(requested).notifier,
    );
    controller.setActive(true);
    await tester.pump();
    await tester.pump();
    for (final margin in [40.0, 80.0, 0.0]) {
      await show(tester, topMargin: margin);
      realtime.events.add([
        LiveChatReceived(
          LiveChatMessage(userName: '甲', text: '顶部距离', id: '$margin'),
        ),
      ]);
      await tester.pump();
      await tester.pump();
      expect(drawing(tester).frame().single.y, margin);
    }
    controller.setActive(false);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets(
    'short-room bridge paints new messages and filters history/modes',
    (tester) async {
      await show(tester);
      final controller = container.read(
        liveControllerProvider(requested).notifier,
      );
      controller.setActive(true);
      await tester.pump();
      await tester.pump();
      expect(realtime.rooms, [canonical]);
      expect(drawing(tester).pendingCount, 0);
      expect(drawing(tester).visibleCount, 0);
      realtime.events.add(const [
        LiveChatReceived(
          LiveChatMessage(userName: '甲', text: '实时新消息', id: 'new'),
        ),
        LiveChatReceived(
          LiveChatMessage(userName: '甲', text: '屏蔽这条', id: 'blocked'),
        ),
        LiveChatReceived(
          LiveChatMessage(userName: '甲', text: '顶部关闭', id: 'top', mode: 5),
        ),
      ]);
      await tester.pump();
      await tester.pump();
      final frame = drawing(tester).frame();
      expect(frame.map((item) => item.event.text), ['实时新消息']);
      expect(
        container.read(liveControllerProvider(requested)).messages.length,
        4,
      );
      controller.setActive(false);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('hidden overlay clears its clock and never replays the backlog', (
    tester,
  ) async {
    await show(tester);
    container.read(liveControllerProvider(requested).notifier).setActive(true);
    await tester.pump();
    realtime.events.add(const [
      LiveChatReceived(
        LiveChatMessage(userName: '甲', text: '显示中', id: 'visible'),
      ),
    ]);
    await tester.pump();
    await tester.pump();
    expect(drawing(tester).frame(), isNotEmpty);
    await show(tester, active: false);
    expect(drawing(tester).frame(), isEmpty);
    realtime.events.add(const [
      LiveChatReceived(
        LiveChatMessage(userName: '甲', text: '隐藏期间', id: 'hidden'),
      ),
    ]);
    await tester.pump();
    await show(tester);
    expect(drawing(tester).frame(), isEmpty);
    realtime.events.add(const [
      LiveChatReceived(
        LiveChatMessage(userName: '甲', text: '恢复后', id: 'resumed'),
      ),
    ]);
    await tester.pump();
    await tester.pump();
    expect(drawing(tester).frame().map((item) => item.event.text), ['恢复后']);
    container.read(liveControllerProvider(requested).notifier).setActive(false);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

final class _Realtime implements LiveChatRepository {
  final events = StreamController<List<LiveRealtimeEvent>>.broadcast(
    sync: true,
  );
  final rooms = <RoomId>[];
  @override
  Stream<List<LiveRealtimeEvent>> watchRoom(
    RoomId id, {
    required RequestCancellation cancellation,
  }) {
    rooms.add(id);
    return events.stream;
  }
}

final class _Rooms implements LiveRepository {
  @override
  String get accountScope => 'guest';
  @override
  int get sessionEpoch => 0;
  @override
  Future<LiveRoom> loadRoom(
    RoomId id, {
    required RequestCancellation cancellation,
  }) async => const LiveRoom(
    id: RoomId('12345'),
    title: '测试',
    anchorName: '主播',
    isLive: true,
  );
  @override
  Future<LivePlayInfo> loadPlayInfo(
    RoomId id, {
    int quality = 10000,
    required RequestCancellation cancellation,
  }) async =>
      const LivePlayInfo(roomId: RoomId('12345'), isLive: true, streams: []);
  @override
  Future<List<LiveChatMessage>> loadChatHistory(
    RoomId id, {
    required RequestCancellation cancellation,
  }) async => const [LiveChatMessage(userName: '历史', text: '历史不绘制')];
  @override
  Future<List<LiveSuperChatMessage>> loadSuperChats(
    RoomId id, {
    required RequestCancellation cancellation,
  }) async => const [];
}

final class _Auth implements AuthRepository {
  @override
  AuthState get current => const AuthState();
  @override
  Stream<AuthState> get changes => const Stream.empty();
  @override
  Future<void> restore() async {}
  @override
  Future<void> signIn() async {}
  @override
  Future<void> signOut() async {}
  @override
  void cancelSignIn() {}
}
