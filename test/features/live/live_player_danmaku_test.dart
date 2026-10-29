import 'dart:async';

import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:bili_player/bili_player.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/live/application/live_controller.dart';
import 'package:bilisail/features/live/domain/live_chat_repository.dart';
import 'package:bilisail/features/live/domain/live_repository.dart';
import 'package:bilisail/features/live/domain/live_room.dart';
import 'package:bilisail/features/live/presentation/live_player_danmaku.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/content_playback.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/playback/presentation/playback_panel.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/input_test_app.dart';
import '../../support/video_card_fake_engine.dart';

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
    AppSettings? settings,
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
                      builder: (_, overlay) => overlay,
                      settings:
                          settings ??
                          AppSettings(
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

  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> revealControls(WidgetTester tester) async {
    await tester.tapAt(
      tester.getTopLeft(
            find.byKey(const ValueKey('player-surface-tap-target')),
          ) +
          const Offset(130, 70),
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 216));
  }

  Future<void> showPlayer(
    WidgetTester tester,
    PlaybackSession session,
    _Window window, {
    bool active = true,
    AppSettings settings = const AppSettings.defaults(),
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ProviderScope(
          overrides: [playbackSessionProvider.overrideWithValue(session)],
          child: InputTestApp(
            home: Scaffold(
              body: WorkspaceActivity(
                active: active,
                child: LiveDanmakuRoomScope(
                  requestedId: requested,
                  child: Center(
                    child: SizedBox(
                      width: 600,
                      height: 300,
                      child: LivePlayerDanmaku(
                        roomId: canonical,
                        settings: settings,
                        builder: (_, overlay) => PlaybackPanel(
                          target: const LivePlaybackTarget('12345'),
                          settings: settings,
                          window: window,
                          onToggleComments: () {},
                          danmakuOverlayBuilder: (_) => overlay,
                        ),
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
    await pumpFrames(tester);
  }

  testWidgets(
    'live fullscreen round trips preserve arrivals and drawing state',
    (tester) async {
      final engine = _Engine();
      final session = PlaybackSession(
        engine: engine,
        repository: _UnusedPlayback(),
        contentRepository: _LivePlayback(),
        progress: _UnusedProgress(),
        accountScope: () => 'guest',
      );
      addTearDown(session.close);
      final window = _Window();
      await showPlayer(tester, session, window);
      await revealControls(tester);
      final live = container.read(liveControllerProvider(requested).notifier);
      live.setActive(true);
      await pumpFrames(tester);
      realtime.events.add(const [
        LiveChatReceived(
          LiveChatMessage(userName: '甲', text: 'scroll', id: 'scroll'),
        ),
        LiveChatReceived(
          LiveChatMessage(userName: '乙', text: 'top', id: 'top', mode: 5),
        ),
        LiveChatReceived(
          LiveChatMessage(userName: '丙', text: 'bottom', id: 'bottom', mode: 4),
        ),
      ]);
      await pumpFrames(tester);
      final original = drawing(tester);
      final events = original.frame().map((p) => p.event).toList();
      expect(events.map((e) => e.text), ['scroll', 'top', 'bottom']);
      final layouts = original.textLayoutBuildCount;
      final generation = session.sourceGeneration;

      void expectPreserved() {
        expect(drawing(tester), same(original));
        expect(original.frame().map((p) => p.event), events);
        expect(original.textLayoutBuildCount, layouts);
        expect(realtime.rooms, [canonical]);
        expect(engine.opens, 1);
        expect(session.sourceGeneration, generation);
        expect(find.byType(VideoSurface), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      for (var cycle = 0; cycle < 3; cycle++) {
        if (cycle == 1) {
          await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        } else {
          await tester.tap(find.byTooltip('全屏（F）'));
        }
        await pumpFrames(tester);
        expect(window.fullScreen, isTrue);
        expectPreserved();
        if (cycle == 1) {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        } else {
          await tester.tap(find.byTooltip('退出全屏（Esc）'));
        }
        await pumpFrames(tester);
        expect(window.fullScreen, isFalse);
        expectPreserved();
      }

      await showPlayer(tester, session, window, active: false);
      expect(original.frame(), isEmpty);
      realtime.events.add(const [
        LiveChatReceived(
          LiveChatMessage(userName: '甲', text: 'hidden', id: 'hidden'),
        ),
      ]);
      await pumpFrames(tester);
      await showPlayer(tester, session, window);
      expect(drawing(tester), same(original));
      expect(original.frame(), isEmpty);
      live.setActive(false);
      await tester.pumpWidget(const SizedBox());
      await pumpFrames(tester);
      expect(original.isAnimating, isFalse);
    },
  );

  testWidgets(
    'live messages received between fullscreen surfaces are retained',
    (tester) async {
      final session = PlaybackSession(
        engine: _Engine(),
        repository: _UnusedPlayback(),
        contentRepository: _LivePlayback(),
        progress: _UnusedProgress(),
        accountScope: () => 'guest',
      );
      addTearDown(session.close);
      final window = _Window();
      await showPlayer(tester, session, window);
      await revealControls(tester);
      final live = container.read(liveControllerProvider(requested).notifier);
      live.setActive(true);
      await pumpFrames(tester);
      final original = drawing(tester);
      final entering = Completer<void>();
      window.transition = entering;
      await tester.tap(find.byTooltip('全屏（F）'));
      await pumpFrames(tester);
      expect(find.byType(LiveDanmakuOverlay), findsNothing);
      realtime.events.add(const [
        LiveChatReceived(
          LiveChatMessage(userName: '甲', text: 'during entry', id: 'entry'),
        ),
      ]);
      await tester.pump();
      expect(original.pendingCount, 1);
      entering.complete();
      await pumpFrames(tester);
      expect(drawing(tester), same(original));
      expect(original.frame().single.event.text, 'during entry');

      final leaving = Completer<void>();
      window.transition = leaving;
      await tester.tap(find.byTooltip('退出全屏（Esc）'));
      await pumpFrames(tester);
      expect(find.byType(LiveDanmakuOverlay), findsNothing);
      realtime.events.add(const [
        LiveChatReceived(
          LiveChatMessage(userName: '乙', text: 'during exit', id: 'exit'),
        ),
      ]);
      await tester.pump();
      expect(original.pendingCount, 1);
      leaving.complete();
      await pumpFrames(tester);
      expect(drawing(tester), same(original));
      expect(original.frame().map((p) => p.event.text), [
        'during entry',
        'during exit',
      ]);
      expect(realtime.rooms, [canonical]);
      live.setActive(false);
      await tester.pumpWidget(const SizedBox());
      await pumpFrames(tester);
    },
  );

  testWidgets(
    'live bridge applies color blocking, duplicate merge and same-screen density',
    (tester) async {
      await show(
        tester,
        settings: AppSettings(
          danmakuBlockColored: true,
          danmakuMergeDuplicates: true,
          danmakuMaxOnScreen: 2,
          danmakuMaxPerSecond: 0,
        ),
      );
      final controller = container.read(
        liveControllerProvider(requested).notifier,
      );
      controller.setActive(true);
      await tester.pump();
      await tester.pump();
      realtime.events.add(const [
        LiveChatReceived(
          LiveChatMessage(
            userName: '甲',
            text: 'red',
            id: 'red',
            color: 0xffff0000,
          ),
        ),
        LiveChatReceived(
          LiveChatMessage(userName: '甲', text: 'same', id: 'one'),
        ),
        LiveChatReceived(
          LiveChatMessage(userName: '乙', text: 'same', id: 'two'),
        ),
        LiveChatReceived(
          LiveChatMessage(userName: '丙', text: 'other', id: 'three'),
        ),
        LiveChatReceived(
          LiveChatMessage(userName: '丁', text: 'extra', id: 'four'),
        ),
      ]);
      await tester.pump();
      await tester.pump();
      expect(drawing(tester).frame().map((p) => p.event.text), [
        'same',
        'other',
      ]);
      await show(
        tester,
        settings: AppSettings(
          danmakuBlockColored: false,
          danmakuMergeDuplicates: false,
          danmakuMaxOnScreen: 0,
          danmakuMaxPerSecond: 0,
        ),
      );
      expect(drawing(tester).frame(), isEmpty);
      realtime.events.add(const [
        LiveChatReceived(
          LiveChatMessage(
            userName: '甲',
            text: 'red new',
            id: 'red2',
            color: 0xffff0000,
          ),
        ),
      ]);
      await tester.pump();
      await tester.pump();
      expect(drawing(tester).frame().single.event.text, 'red new');
      controller.setActive(false);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

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
  testWidgets('live bridge applies row gaps including the five-pixel default', (
    tester,
  ) async {
    await show(tester);
    final controller = container.read(
      liveControllerProvider(requested).notifier,
    );
    controller.setActive(true);
    await tester.pump();
    await tester.pump();
    double? textHeight;
    var batch = 0;
    for (final gap in [0.0, 20.0, 0.0, 5.0]) {
      batch++;
      await show(tester, settings: AppSettings(danmakuLineSpacing: gap));
      realtime.events.add([
        LiveChatReceived(
          LiveChatMessage(userName: '甲', text: 'line', id: '$batch-one'),
        ),
        LiveChatReceived(
          LiveChatMessage(userName: '乙', text: 'line', id: '$batch-two'),
        ),
      ]);
      await tester.pump();
      await tester.pump();
      final frame = drawing(tester).frame();
      expect(frame, hasLength(2));
      final laneHeight = frame[1].y - frame[0].y;
      textHeight ??= laneHeight;
      expect(laneHeight, textHeight + gap);
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

final class _Window extends WindowService {
  bool fullScreen = false;
  Completer<void>? transition;
  @override
  Future<void> setFullScreen(
    bool value, {
    FullScreenOrientation? orientation,
  }) async {
    final pending = transition;
    transition = null;
    await pending?.future;
    fullScreen = value;
  }
}

final class _Engine extends CardFakeEngine {
  @override
  PlayerCapabilities get capabilities => const PlayerCapabilities(
    externalAudio: false,
    externalAudioHeaders: false,
  );
  @override
  Future<void> play() async =>
      publish(snapshot.copyWith(phase: PlaybackPhase.playing));
  @override
  Future<void> pause() async =>
      publish(snapshot.copyWith(phase: PlaybackPhase.paused));
  @override
  Future<void> setVolume(double volume) async =>
      publish(snapshot.copyWith(volume: volume));
  @override
  Future<void> setRate(double rate) async =>
      publish(snapshot.copyWith(rate: rate));
}

final class _UnusedPlayback extends Fake implements PlaybackRepository {}

final class _UnusedProgress extends Fake implements PlaybackProgressStore {}

final class _LivePlayback implements ContentPlaybackRepository {
  @override
  Future<PlaybackMedia> resolve(
    ContentPlaybackTarget target, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => PlaybackMedia(
    kind: PlaybackMediaKind.liveHls,
    video: PlaybackTrack(
      urls: [Uri.parse('https://example.test/live.m3u8')],
      codec: 'avc1',
      bandwidth: 1000,
    ),
    audio: null,
    quality: 80,
    qualities: const [80],
    duration: Duration.zero,
    headers: const {},
  );
}
