import 'dart:async';

import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';

import '../../support/memory_settings_repository.dart';

import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/video/application/video_actions_controller.dart';
import 'package:bilisail/features/video/domain/video_actions_repository.dart';
import 'package:bilisail/features/video/presentation/video_danmaku_composer.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'video_actions_bar_test.dart'
    show FakeActions, FakeAuth, testDetail, testPart;

void main() {
  testWidgets(
    'a slower style save keeps a newer global choice from another page',
    (tester) async {
      final settings = MemorySettingsRepository()
        ..pendingWrite = Completer<void>();
      final session = FakeComposerSession();
      addTearDown(session.dispose);
      await pumpComposer(
        tester,
        FakeActions(),
        session: session,
        settings: settings,
      );
      await tester.tap(find.byTooltip('发送弹幕样式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('顶部'));
      await tester.tap(find.byTooltip('粉色'));
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(VideoDanmakuComposer)),
      );
      const newer = (mode: 4, color: 0x123456, colorful: false);
      final newerSave = container
          .read(settingsControllerProvider.notifier)
          .setDanmakuSendStyle(newer);
      settings.pendingWrite!.complete();
      await newerSave;
      await tester.pumpAndSettle();
      expect(settings.value.danmakuSendStyle, newer);
      expect(session.danmakuSendStyle.value, newer);
    },
  );

  testWidgets(
    'failed global style save keeps the previous selection and can retry',
    (tester) async {
      final settings = MemorySettingsRepository()..failWrites = true;
      final session = FakeComposerSession();
      addTearDown(session.dispose);
      await pumpComposer(
        tester,
        FakeActions(),
        session: session,
        settings: settings,
      );
      await tester.enterText(find.byType(TextField), '保留草稿');
      Future<void> choose() async {
        await tester.tap(find.byTooltip('发送弹幕样式'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('顶部'));
        await tester.tap(find.byTooltip('粉色'));
        await tester.tap(find.text('完成'));
        await tester.pumpAndSettle();
      }

      await choose();
      expect(session.danmakuSendStyle.value, (
        mode: 1,
        color: 0xffffff,
        colorful: false,
      ));
      expect(settings.value.danmakuSendStyle, (
        mode: 1,
        color: 0xffffff,
        colorful: false,
      ));
      expect(find.text('弹幕样式保存失败，请重试'), findsOneWidget);
      expect(find.text('保留草稿'), findsOneWidget);
      settings.failWrites = false;
      await choose();
      expect(session.danmakuSendStyle.value, (
        mode: 5,
        color: 0xff6699,
        colorful: false,
      ));
      expect(settings.value.danmakuSendStyle, (
        mode: 5,
        color: 0xff6699,
        colorful: false,
      ));
    },
  );

  testWidgets(
    'send style survives composer replacement and reaches local echo',
    (tester) async {
      final repo = FakeActions();
      final session = FakeComposerSession();
      addTearDown(session.dispose);
      await pumpComposer(tester, repo, session: session);
      await tester.tap(find.byTooltip('发送弹幕样式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('顶部'));
      await tester.tap(find.byTooltip('粉色'));
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      await pumpComposer(
        tester,
        repo,
        session: session,
        composerKey: const ValueKey('fullscreen'),
      );
      await tester.tap(find.byTooltip('发送弹幕样式'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '顶部'))
            .selected,
        isTrue,
      );
      expect(find.text('预览 · 顶部 · #FF6699'), findsOneWidget);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'styled message');
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('send:${testPart.cid}:5:${0xff6699}'));
      expect(session.sent, [
        (
          id: '9007199254740993',
          text: 'styled message',
          mode: 5,
          color: 0xff6699,
        ),
      ]);
    },
  );

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
  VideoActionsRepository repo, {
  bool signedIn = true,
  VoidCallback? onLogin,
  double textScale = 1,
  FakeComposerSession? session,
  bool vip = false,
  MemorySettingsRepository? settings,
  Key? composerKey,
}) async {
  final playback = session ?? FakeComposerSession();
  if (session == null) addTearDown(playback.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuth(signedIn, vip: vip)),
        videoActionsRepositoryProvider.overrideWithValue(repo),
        playbackSessionProvider.overrideWithValue(playback),
        settingsRepositoryProvider.overrideWithValue(
          settings ?? MemorySettingsRepository(),
        ),
      ],
      child: MaterialApp(
        builder: AppNoticeHost.builder,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            backgroundColor: Colors.black,
            body: VideoDanmakuComposer(
              key: composerKey,
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
  int get sourceGeneration => 1;
  @override
  final danmakuSendStyle =
      ValueNotifier<({int mode, int color, bool colorful})>((
        mode: 1,
        color: 0xffffff,
        colorful: false,
      ));
  @override
  void setDanmakuSendStyle(({int mode, int color, bool colorful}) style) =>
      danmakuSendStyle.value = style;
  final sentColorful = <bool>[];
  final sent = <({String? id, String text, int mode, int color})>[];
  @override
  void showSentDanmaku({
    required String cid,
    required int generation,
    required String text,
    required Duration position,
    required int mode,
    required int color,
    bool colorful = false,
    String? id,
  }) {
    sentColorful.add(colorful);
    sent.add((id: id, text: text, mode: mode, color: color));
  }

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
    danmakuSendStyle.dispose();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
