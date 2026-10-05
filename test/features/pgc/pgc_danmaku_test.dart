import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/pgc/application/pgc_danmaku_controller.dart';
import 'package:bilisail/features/pgc/domain/pgc_danmaku_repository.dart';
import 'package:bilisail/features/pgc/domain/pgc_repository.dart';
import 'package:bilisail/features/pgc/presentation/pgc_danmaku_composer.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/content_playback.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _episode = PgcEpisode(
  id: PgcEpisodeId('7'),
  title: '第 1 集',
  bvid: 'BV1234567890',
  cid: '101',
);
const _target = (episodeId: '7', video: VideoId('BV1234567890'), cid: '101');

void main() {
  test(
    'writes only after explicit action and fixes target, text and milliseconds',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final controller = harness.controller;
      expect(harness.repository.calls, 0);
      expect(await controller.send(' ', mode: 1, color: 0xffffff), false);
      harness.repository.pending = Completer<void>();
      final sending = controller.send('  你好 & + %  ', mode: 5, color: 0x123456);
      expect(harness.repository.calls, 1);
      expect(harness.repository.target, _target);
      expect(harness.repository.text, '你好 & + %');
      expect(harness.repository.position, const Duration(milliseconds: 12345));
      expect(harness.repository.mode, 5);
      expect(harness.repository.color, 0x123456);
      expect(
        await controller.send('duplicate', mode: 1, color: 0xffffff),
        false,
      );
      harness.repository.pending!.complete();
      expect(await sending, true);
      expect(harness.state.busy, false);
      expect(harness.state.message, '弹幕已发送');
    },
  );

  test(
    'wrong episode, unresolved media and source account reject before write',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.session.contentTarget = const PgcPlaybackTarget('8', cid: '101');
      expect(
        await harness.controller.send(
          'wrong episode',
          mode: 1,
          color: 0xffffff,
        ),
        false,
      );
      harness.session.contentTarget = const PgcPlaybackTarget('7', cid: '101');
      harness.session.isResolving = true;
      expect(
        await harness.controller.send('not ready', mode: 1, color: 0xffffff),
        false,
      );
      harness.session.isResolving = false;
      harness.session.sourceAccountScope = 'user:2';
      expect(
        await harness.controller.send('old account', mode: 1, color: 0xffffff),
        false,
      );
      expect(harness.repository.calls, 0);
    },
  );

  test(
    'source changes cancel one pending write and reject its late result',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.repository.pending = Completer<void>();
      final sending = harness.controller.send(
        'old source',
        mode: 1,
        color: 0xffffff,
      );
      final cancellation = harness.repository.cancellation!;
      harness.session.switchEpisode('8', '102');
      expect(cancellation.isCancelled, true);
      expect(harness.state.busy, false);
      harness.repository.pending!.complete();
      expect(await sending, false);
      expect(harness.state.message, isNull);
      expect(harness.repository.calls, 1);
    },
  );

  test('same account epoch change invalidates pending send', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.repository.pending = Completer<void>();
    final sending = harness.controller.send(
      'old epoch',
      mode: 1,
      color: 0xffffff,
    );
    harness.repository.sessionEpoch++;
    harness.auth.emit(const AuthState(status: AuthStatus.signedIn, mid: '1'));
    await Future<void>.delayed(Duration.zero);
    expect(harness.repository.cancellation!.isCancelled, true);
    harness.repository.pending!.complete();
    expect(await sending, false);
    expect(harness.state.message, isNull);
  });

  test('unknown write outcome never retries or claims success', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.repository.failure = const PgcDanmakuWriteUncertain();
    expect(
      await harness.controller.send('maybe sent', mode: 1, color: 0xffffff),
      false,
    );
    expect(harness.state.uncertain, true);
    expect(harness.state.message, contains('未自动重试'));
    expect(
      await harness.controller.send('maybe sent', mode: 1, color: 0xffffff),
      false,
    );
    expect(harness.repository.calls, 1);
  });

  testWidgets('guest composer requests login without writing', (tester) async {
    final harness = _Harness(signedIn: false);
    addTearDown(harness.dispose);
    var logins = 0;
    await _pumpComposer(tester, harness, onLogin: () => logins++);
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.text('发送'));
    await tester.pump();
    expect(logins, 1);
    expect(harness.repository.calls, 0);
  });

  testWidgets(
    'composer retains failed draft and clears only confirmed success',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await _pumpComposer(tester, harness);
      harness.repository.failure = const AppFailure(
        AppFailureKind.permission,
        '当前集禁止发送弹幕',
      );
      await tester.enterText(find.byType(TextField), 'draft');
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'draft',
      );
      expect(find.text('当前集禁止发送弹幕'), findsOneWidget);
      harness.repository.failure = null;
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.text('弹幕已发送'), findsOneWidget);
    },
  );

  for (final width in [320.0, 800.0]) {
    testWidgets('PGC composer fits width $width with large text', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final harness = _Harness();
      addTearDown(harness.dispose);
      await _pumpComposer(tester, harness, textScale: 2);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pumpComposer(
  WidgetTester tester,
  _Harness harness, {
  VoidCallback? onLogin,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: MaterialApp(
        builder: AppNoticeHost.builder,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            backgroundColor: Colors.black,
            body: PgcDanmakuComposer(
              episode: _episode,
              onLogin: onLogin ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _Harness {
  _Harness({bool signedIn = true}) {
    auth = _Auth(signedIn);
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        pgcDanmakuRepositoryProvider.overrideWithValue(repository),
        playbackSessionProvider.overrideWithValue(session),
      ],
    );
    container.listen(pgcDanmakuControllerProvider(_target), (_, _) {});
  }
  final repository = _Repository();
  final session = _Session();
  late final _Auth auth;
  late final ProviderContainer container;
  PgcDanmakuController get controller =>
      container.read(pgcDanmakuControllerProvider(_target).notifier);
  PgcDanmakuState get state =>
      container.read(pgcDanmakuControllerProvider(_target));
  void dispose() {
    container.dispose();
    session.dispose();
    auth.dispose();
  }
}

final class _Repository implements PgcDanmakuRepository {
  @override
  String accountScope = 'user:1';
  @override
  int sessionEpoch = 1;
  int calls = 0;
  PgcDanmakuTarget? target;
  String? text;
  Duration? position;
  int? mode, color;
  RequestCancellation? cancellation;
  Completer<void>? pending;
  Object? failure;
  @override
  Future<void> send(
    PgcDanmakuTarget target,
    String text,
    Duration position, {
    required int mode,
    required int color,
    required RequestCancellation cancellation,
  }) async {
    calls++;
    this.target = target;
    this.text = text;
    this.position = position;
    this.mode = mode;
    this.color = color;
    this.cancellation = cancellation;
    if (failure case final error?) throw error;
    await pending?.future;
  }
}

final class _Session extends ChangeNotifier implements PlaybackSession {
  @override
  int sourceGeneration = 1;
  @override
  String sourceAccountScope = 'user:1';
  @override
  bool isResolving = false;
  @override
  ContentPlaybackTarget? contentTarget = const PgcPlaybackTarget(
    '7',
    cid: '101',
  );
  @override
  String? get danmakuCid => (contentTarget as PgcPlaybackTarget?)?.cid;
  @override
  PlaybackMedia? media = const PlaybackMedia(
    video: PlaybackTrack(urls: [], codec: '', bandwidth: 0),
    audio: PlaybackTrack(urls: [], codec: '', bandwidth: 0),
    quality: 80,
    qualities: [80],
    duration: Duration(minutes: 20),
    headers: {},
  );
  @override
  final snapshots = ValueNotifier(
    const PlaybackSnapshot(
      phase: PlaybackPhase.paused,
      generation: 1,
      position: Duration(milliseconds: 12345),
      duration: Duration(minutes: 20),
    ),
  );
  void switchEpisode(String id, String cid) {
    sourceGeneration++;
    contentTarget = PgcPlaybackTarget(id, cid: cid);
    notifyListeners();
  }

  @override
  void dispose() {
    snapshots.dispose();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Auth implements AuthRepository {
  _Auth(bool signedIn)
    : current = AuthState(
        status: signedIn ? AuthStatus.signedIn : AuthStatus.guest,
        mid: signedIn ? '1' : null,
      );
  final _changes = StreamController<AuthState>.broadcast(sync: true);
  @override
  AuthState current;
  @override
  Stream<AuthState> get changes => _changes.stream;
  void emit(AuthState value) {
    current = value;
    _changes.add(value);
  }

  void dispose() => unawaited(_changes.close());
  @override
  void cancelSignIn() {}
  @override
  Future<void> restore() async {}
  @override
  Future<void> signIn() async {}
  @override
  Future<void> signOut() async => emit(const AuthState());
}
