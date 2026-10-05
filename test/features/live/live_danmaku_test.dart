import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/live/application/live_controller.dart';
import 'package:bilisail/features/live/application/live_danmaku_controller.dart';
import 'package:bilisail/features/live/domain/live_danmaku_repository.dart';
import 'package:bilisail/features/live/domain/live_room.dart';
import 'package:bilisail/features/live/presentation/live_danmaku_composer.dart';
import 'package:bilisail/features/live/presentation/live_screen.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _requested = RoomId('12');
const _room = LiveRoom(
  id: RoomId('12345'),
  title: '直播间',
  anchorName: '主播',
  isLive: true,
);
const _sticker = LiveEmoticon(
  unique: 'room_12345_1',
  text: '[干杯]',
  isSticker: true,
  allowed: true,
);
const _locked = LiveEmoticon(
  unique: 'locked',
  text: '[锁定]',
  isSticker: true,
  unlockHint: '需要等级',
);
const _textEmote = LiveEmoticon(unique: 'text', text: '[笑]', allowed: true);

void main() {
  test(
    'one explicit write fixes canonical room and locks both composers',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.controller.setDraft('  中文 &+=%  ');
      expect(h.repository.posts, 0);
      h.repository.pending = Completer<void>();
      final sending = h.controller.send();
      expect(h.repository.sentRoom, _room.id);
      expect(h.repository.text, '中文 &+=%');
      expect(h.state.busy, true);
      expect(await h.controller.send(), false);
      h.controller.setDraft('cannot overwrite pending');
      expect(h.state.draft, '  中文 &+=%  ');
      h.repository.pending!.complete();
      expect(await sending, true);
      expect(h.state.draft, '');
      expect(h.repository.posts, 1);
    },
  );

  test(
    'emoticons load once, locks reject and stickers require explicit send',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.controller.loadEmoticons();
      await h.controller.loadEmoticons();
      expect(h.repository.reads, 1);
      h.controller.chooseEmoticon(_locked);
      expect(h.state.selected, isNull);
      h.controller.setDraft('你好');
      h.controller.chooseEmoticon(_textEmote);
      expect(h.state.draft, '你好[笑]');
      expect(h.state.selected, isNull);
      h.controller.chooseEmoticon(_sticker);
      expect(h.repository.posts, 0);
      expect(await h.controller.send(), true);
      expect(h.repository.emoticon, _sticker.unique);
      expect(h.state.selected, isNull);
    },
  );

  test(
    'uncertain outcomes retain draft and block repeats until acknowledged',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.controller.setDraft('hello');
      h.repository.error = const LiveDanmakuWriteUncertain();
      expect(await h.controller.send(), false);
      expect(h.state.uncertain, true);
      expect(h.state.draft, 'hello');
      expect(await h.controller.send(), false);
      expect(h.repository.posts, 1);
      h.controller.acknowledgeUncertain();
      h.repository.error = const AppFailure(
        AppFailureKind.permission,
        'fixture',
      );
      expect(await h.controller.send(), false);
      expect(h.state.uncertain, false);
      expect(h.state.message, contains('发送被拒绝'));
      expect(h.state.draft, 'hello');
    },
  );

  test(
    'room and account changes cancel old operations and ignore late success',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.controller.setDraft('old room');
      h.repository.pending = Completer<void>();
      final sending = h.controller.send();
      final token = h.repository.cancellation!;
      h.room.change(
        const LiveRoom(
          id: RoomId('999'),
          title: '新房间',
          anchorName: '主播',
          isLive: true,
        ),
      );
      expect(h.state.busy, false);
      expect(token.isCancelled, true);
      h.controller.setDraft('new room');
      h.repository.pending!.complete();
      expect(await sending, false);
      expect(h.state.draft, 'new room');
      h.repository.pending = Completer<void>();
      final next = h.controller.send();
      final nextToken = h.repository.cancellation!;
      h.repository.sessionEpoch++;
      h.auth.emit(const AuthState());
      expect(h.state.signedIn, false);
      expect(nextToken.isCancelled, true);
      h.repository.pending!.complete();
      expect(await next, false);
      expect(h.state.message, isNull);
      expect(await h.controller.send(), false);
    },
  );

  test('guest, offline room and blank drafts never send', () async {
    final h = _Harness(signedIn: false);
    addTearDown(h.dispose);
    h.controller.setDraft('hello');
    expect(await h.controller.send(), false);
    await h.controller.loadEmoticons();
    expect(h.repository.reads, 0);
    h.auth.emit(const AuthState(status: AuthStatus.signedIn, mid: '1'));
    expect(await h.controller.send(), false);
    h.controller.setDraft('hello');
    h.room.change(
      const LiveRoom(
        id: RoomId('12345'),
        title: '',
        anchorName: '',
        isLive: false,
      ),
    );
    expect(await h.controller.send(), false);
    expect(h.repository.posts, 0);
  });

  testWidgets(
    'player and sidebar share drafts, emoji selection and pending send',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: MaterialApp(
            builder: AppNoticeHost.builder,
            home: Scaffold(
              body: Column(
                children: [
                  SizedBox(
                    width: 300,
                    child: LiveDanmakuComposer(
                      roomId: _requested,
                      onLogin: () {},
                      playerStyle: true,
                    ),
                  ),
                  SizedBox(
                    width: 300,
                    child: LiveDanmakuComposer(
                      roomId: _requested,
                      onLogin: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final player = find.byKey(const ValueKey('live-player-danmaku-input'));
      final sidebar = find.byKey(const ValueKey('live-sidebar-danmaku-input'));
      await tester.enterText(player, 'hello');
      await tester.pump();
      expect(tester.widget<TextField>(sidebar).controller?.text, 'hello');
      await tester.tap(find.byTooltip('直播表情包').last);
      await tester.pumpAndSettle();
      expect(find.text('房间表情'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.byKey(const ValueKey('live-emoticon-text')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('live-emoticon-locked')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(h.state.draft, 'hello');
      await tester.tap(find.text('默认表情'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('live-emoticon-locked')), findsNothing);
      expect(find.byKey(const ValueKey('live-emoticon-text')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('live-emoticon-text')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(player).controller?.text, 'hello[笑]');
      expect(tester.widget<TextField>(sidebar).controller?.text, 'hello[笑]');
      await tester.tap(find.byTooltip('直播表情包').first);
      await tester.pumpAndSettle();
      expect(h.repository.posts, 0);
      await tester.tap(
        find.byKey(const ValueKey('live-emoticon-room_12345_1')),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(player).controller?.text, '[干杯]');
      expect(tester.widget<TextField>(sidebar).controller?.text, '[干杯]');
      h.repository.pending = Completer<void>();
      await tester.tap(find.text('发送').last);
      await tester.pump();
      expect(find.text('发送中'), findsNWidgets(2));
      expect(tester.widget<TextField>(player).enabled, false);
      h.repository.pending!.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(player).controller?.text, '');
      expect(tester.widget<TextField>(sidebar).controller?.text, '');
      expect(h.repository.posts, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'sidebar composer stays available on chat and SC in compact layouts',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: MaterialApp(
            home: Scaffold(
              body: LiveScreen(
                roomId: '12',
                playerBuilder: (_, _) => const SizedBox(),
                composerBuilder: (_, roomId) =>
                    LiveDanmakuComposer(roomId: roomId, onLogin: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('live-sidebar-danmaku-input')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('live-tab-1')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('live-sidebar-danmaku-input')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

final class _Harness {
  _Harness({bool signedIn = true}) : auth = _Auth(signedIn) {
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        liveDanmakuRepositoryProvider.overrideWithValue(repository),
        liveControllerProvider.overrideWith2(_RoomController.new),
      ],
    );
    subscription = container.listen(
      liveDanmakuControllerProvider(_requested),
      (_, _) {},
    );
  }
  final _Auth auth;
  final repository = _Repository();
  late final ProviderContainer container;
  late final ProviderSubscription<LiveDanmakuState> subscription;
  LiveDanmakuState get state =>
      container.read(liveDanmakuControllerProvider(_requested));
  LiveDanmakuController get controller =>
      container.read(liveDanmakuControllerProvider(_requested).notifier);
  _RoomController get room =>
      container.read(liveControllerProvider(_requested).notifier)
          as _RoomController;
  void dispose() {
    subscription.close();
    container.dispose();
    unawaited(auth.changesController.close());
  }
}

final class _RoomController extends LiveController {
  _RoomController(super.requestedId);
  @override
  LiveState build() => const LiveState(room: _room);
  @override
  void setActive(bool active) {}
  void change(LiveRoom room) => state = LiveState(room: room);
}

final class _Repository implements LiveDanmakuRepository {
  @override
  String get accountScope => 'user:1';
  @override
  int sessionEpoch = 1;
  int posts = 0, reads = 0;
  RoomId? sentRoom;
  String? text, emoticon;
  RequestCancellation? cancellation;
  Completer<void>? pending;
  Object? error;
  @override
  Future<List<LiveEmoticonPackage>> loadEmoticons(
    RoomId room, {
    required RequestCancellation cancellation,
  }) async {
    reads++;
    return [
      LiveEmoticonPackage('房间表情', [_sticker, _locked]),
      LiveEmoticonPackage('默认表情', [_textEmote]),
    ];
  }

  @override
  Future<void> send(
    RoomId room,
    String text, {
    String? emoticonUnique,
    required RequestCancellation cancellation,
  }) async {
    posts++;
    sentRoom = room;
    this.text = text;
    emoticon = emoticonUnique;
    this.cancellation = cancellation;
    if (error case final error?) throw error;
    if (pending case final pending?) await pending.future;
  }
}

final class _Auth implements AuthRepository {
  _Auth(bool signedIn)
    : current = AuthState(
        status: signedIn ? AuthStatus.signedIn : AuthStatus.guest,
        mid: signedIn ? '1' : null,
      );
  final changesController = StreamController<AuthState>.broadcast(sync: true);
  @override
  AuthState current;
  @override
  Stream<AuthState> get changes => changesController.stream;
  void emit(AuthState value) {
    current = value;
    changesController.add(value);
  }

  @override
  void cancelSignIn() {}
  @override
  Future<void> restore() async {}
  @override
  Future<void> signIn() async {}
  @override
  Future<void> signOut() async => emit(const AuthState());
}
