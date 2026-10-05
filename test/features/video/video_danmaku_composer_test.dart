import 'dart:async';

import 'package:bili_lite/features/auth/application/auth_controller.dart';
import 'package:bili_lite/features/playback/application/playback_session.dart';
import 'package:bili_lite/features/playback/domain/playback_repository.dart';
import 'package:bili_lite/features/video/application/video_actions_controller.dart';
import 'package:bili_lite/features/video/presentation/video_danmaku_composer.dart';
import 'package:bili_lite/domain/video.dart';
import 'package:bili_lite/shared/ui/app_notice.dart';
import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'video_actions_bar_test.dart'
    show FakeActions, FakeAuth, testDetail, testPart;

void main() {
  for (final width in [320.0, 800.0, 1920.0]) {
    testWidgets('composer fits width $width at large text', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpComposer(tester, FakeActions(), textScale: 2);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('guest send requests login without read or write', (
    tester,
  ) async {
    final repo = FakeActions();
    var logins = 0;
    await pumpComposer(tester, repo, signedIn: false, onLogin: () => logins++);
    await tester.enterText(find.byType(TextField), 'guest');
    await tester.tap(find.text('发送'));
    await tester.pump();
    expect(logins, 1);
    expect(repo.calls, isEmpty);
  });
  testWidgets(
    'blank input does not send; successful send clears text and busy prevents duplicates',
    (tester) async {
      final repo = FakeActions();
      await pumpComposer(tester, repo);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('发送'));
      await tester.pump();
      expect(repo.calls, ['load']);
      repo.pending = Completer<void>();
      await tester.enterText(find.byType(TextField), '  hello world  ');
      await tester.tap(find.text('发送'));
      await tester.pump();
      expect(repo.sentText, 'hello world');
      expect(repo.sentPosition, const Duration(seconds: 12));
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '发送中'))
            .onPressed,
        isNull,
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      repo.pending!.complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.text('弹幕已发送'), findsOneWidget);
      expect(repo.calls.where((v) => v.startsWith('send:')), hasLength(1));
    },
  );
  testWidgets('failed send retains draft and reports failure', (tester) async {
    final repo = FakeActions()..fail = true;
    await pumpComposer(tester, repo);
    await tester.enterText(find.byType(TextField), 'keep draft');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'keep draft',
    );
    expect(find.text('操作失败，请稍后重试'), findsOneWidget);
  });
}

Future<void> pumpComposer(
  WidgetTester tester,
  FakeActions repo, {
  bool signedIn = true,
  VoidCallback? onLogin,
  double textScale = 1,
}) async {
  final session = FakeComposerSession();
  addTearDown(session.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuth(signedIn)),
        videoActionsRepositoryProvider.overrideWithValue(repo),
        playbackSessionProvider.overrideWithValue(session),
      ],
      child: MaterialApp(
        builder: AppNoticeHost.builder,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            backgroundColor: Colors.black,
            body: VideoDanmakuComposer(
              detail: testDetail,
              part: testPart,
              onLogin: onLogin ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class FakeComposerSession extends ChangeNotifier implements PlaybackSession {
  @override
  VideoDetail? get detail => testDetail;
  @override
  VideoPart? get part => testPart;
  @override
  PlaybackMedia? get media => const PlaybackMedia(
    video: PlaybackTrack(urls: [], codec: '', bandwidth: 0),
    audio: PlaybackTrack(urls: [], codec: '', bandwidth: 0),
    quality: 80,
    qualities: [80],
    duration: Duration(minutes: 2),
    headers: {},
  );
  @override
  final snapshots = ValueNotifier(
    const PlaybackSnapshot(
      phase: PlaybackPhase.paused,
      generation: 1,
      position: Duration(seconds: 12),
      duration: Duration(minutes: 2),
    ),
  );
  @override
  void dispose() {
    snapshots.dispose();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
