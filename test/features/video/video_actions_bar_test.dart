import 'dart:async';

import 'package:bili_lite/domain/request_cancellation.dart';
import 'package:bili_lite/domain/video.dart';
import 'package:bili_lite/features/auth/application/auth_controller.dart';
import 'package:bili_lite/features/auth/domain/auth_repository.dart';
import 'package:bili_lite/features/video/application/video_actions_controller.dart';
import 'package:bili_lite/features/video/domain/video_actions_repository.dart';
import 'package:bili_lite/features/video/presentation/video_actions_bar.dart';
import 'package:bili_lite/shared/ui/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const testPart = VideoPart(
  cid: '22',
  page: 1,
  title: 'part',
  duration: Duration(minutes: 2),
);
const testDetail = VideoDetail(
  summary: VideoSummary(
    id: VideoId('BV1234567890'),
    title: 'video',
    coverUrl: '',
    author: 'author',
    duration: Duration(minutes: 2),
  ),
  description: '',
  parts: [testPart],
  aid: '11',
  likeCount: 0,
  coinCount: 0,
  favoriteCount: 0,
);

void main() {
  for (final width in [320.0, 800.0, 1920.0]) {
    testWidgets('action bar fits width $width at large text', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpActions(tester, FakeActions(), signedIn: true, textScale: 2);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('watch later and reload are available only through more menu', (
    tester,
  ) async {
    final repo = FakeActions();
    var logins = 0;
    var reloads = 0;
    await pumpActions(
      tester,
      repo,
      onLogin: () => logins++,
      menuOnly: true,
      onReload: () => reloads++,
    );
    expect(find.text('稍后再看'), findsNothing);
    expect(find.text('重新加载'), findsNothing);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('稍后再看'));
    await tester.pumpAndSettle();
    expect(logins, 1);
    expect(repo.calls, isEmpty);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(reloads, 1);
  });
  testWidgets('guest actions request login without repository access', (
    tester,
  ) async {
    final repo = FakeActions();
    var logins = 0;
    await pumpActions(tester, repo, onLogin: () => logins++);
    for (final label in ['点赞 0', '投币 0', '收藏 0']) {
      final button = find.byTooltip(label);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
    }
    expect(logins, 3);
    expect(repo.calls, isEmpty);
  });
  testWidgets(
    'coin requires dialog choice and suppresses duplicate while busy',
    (tester) async {
      final repo = FakeActions()..pending = Completer<void>();
      await pumpActions(tester, repo, signedIn: true);
      await tester.tap(find.byTooltip('投币 0'));
      await tester.pumpAndSettle();
      expect(find.text('为视频投币'), findsOneWidget);
      expect(repo.calls, ['load']);
      await tester.tap(find.text('2 枚'));
      await tester.pumpAndSettle();
      expect(repo.calls, ['load', 'coin:2']);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == '投币 0',
              ),
            )
            .onPressed,
        isNull,
      );
      repo.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.byTooltip('已投 2 枚'), findsOneWidget);
    },
  );
  testWidgets('like feedback uses a transient notice', (tester) async {
    final repo = FakeActions();
    await pumpActions(tester, repo, signedIn: true);
    await tester.tap(find.byTooltip('点赞 0'));
    await tester.pump();
    expect(repo.calls, ['load', 'like:true']);
    expect(find.byTooltip('已点赞'), findsOneWidget);
    expect(find.text('操作成功'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('操作成功'), findsNothing);
  });
  testWidgets('favorite loads folders and only saves explicit selection', (
    tester,
  ) async {
    final repo = FakeActions();
    await pumpActions(tester, repo, signedIn: true);
    await tester.tap(find.byTooltip('收藏 0'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['load', 'folders']);
    await tester.tap(find.text('测试收藏夹'));
    await tester.pump();
    expect(repo.calls, ['load', 'folders']);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['load', 'folders', 'favorite:33:']);
    expect(find.byTooltip('已收藏'), findsOneWidget);
  });
}

Future<void> pumpActions(
  WidgetTester tester,
  FakeActions repo, {
  bool signedIn = false,
  VoidCallback? onLogin,
  double textScale = 1,
  bool menuOnly = false,
  VoidCallback? onReload,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuth(signedIn)),
        videoActionsRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        builder: AppNoticeHost.builder,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: VideoActionsBar(
              detail: testDetail,
              menuOnly: menuOnly,
              onReload: onReload,
              onLogin: onLogin ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class FakeAuth implements AuthRepository {
  FakeAuth(bool signedIn)
    : current = AuthState(
        status: signedIn ? AuthStatus.signedIn : AuthStatus.guest,
        mid: signedIn ? '1' : null,
      );
  @override
  final AuthState current;
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

class FakeActions implements VideoActionsRepository {
  final calls = <String>[];
  Completer<void>? pending;
  bool fail = false;
  String? sentText;
  Duration? sentPosition;
  @override
  String get accountScope => 'user:1';
  Future<void> write(String call) async {
    calls.add(call);
    if (pending != null) await pending!.future;
    if (fail) throw StateError('write failed');
  }

  @override
  Future<VideoInteraction> load(
    VideoActionTarget target,
    RequestCancellation cancellation,
  ) async {
    calls.add('load');
    return const VideoInteraction();
  }

  @override
  Future<List<FavoriteFolder>> folders(
    VideoActionTarget target,
    RequestCancellation cancellation,
  ) async {
    calls.add('folders');
    return const [
      FavoriteFolder(id: '33', title: '测试收藏夹', containsVideo: false),
    ];
  }

  @override
  Future<void> coin(
    VideoActionTarget target,
    int count,
    RequestCancellation cancellation,
  ) => write('coin:$count');
  @override
  Future<void> like(
    VideoActionTarget target,
    bool liked,
    RequestCancellation cancellation,
  ) => write('like:$liked');
  @override
  Future<void> favorite(
    VideoActionTarget target,
    List<String> add,
    List<String> remove,
    RequestCancellation cancellation,
  ) => write('favorite:${add.join(",")}:${remove.join(",")}');
  @override
  Future<void> watchLater(
    VideoActionTarget target,
    RequestCancellation cancellation,
  ) => write('watchLater');
  @override
  Future<void> sendDanmaku(
    VideoActionTarget target,
    String cid,
    String message,
    Duration position,
    int mode,
    int color,
    RequestCancellation cancellation,
  ) {
    sentText = message;
    sentPosition = position;
    return write('send:$cid:$mode:$color');
  }
}
