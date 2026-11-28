import 'dart:async';

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/video/application/video_actions_controller.dart';
import 'package:bilisail/features/video/application/video_author_controller.dart';
import 'package:bilisail/features/video/domain/video_author_repository.dart';
import 'package:bilisail/features/video/presentation/featured_video_overlay.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/desktop_windowing.dart';
import '../../support/follow_repository_fake.dart';
import '../../support/material_tooltip_finder.dart';
import 'video_actions_bar_test.dart' show FakeActions, FakeAuth;

const _detail = VideoDetail(
  summary: VideoSummary(
    id: VideoId('BV1234567890'),
    title: '当前稿件的标题',
    coverUrl: '',
    author: '精选 UP 主',
    duration: Duration(minutes: 1),
    authorId: UserId('81'),
  ),
  description: '稿件简介',
  parts: [],
  aid: '11',
  likeCount: 14000,
  coinCount: 215,
  favoriteCount: 326,
  replyCount: 47,
);

const _other = VideoDetail(
  summary: VideoSummary(
    id: VideoId('BV1234567891'),
    title: '下一条稿件',
    coverUrl: '',
    author: '另一位 UP 主',
    duration: Duration(minutes: 1),
    authorId: UserId('82'),
  ),
  description: '',
  parts: [],
  aid: '12',
  likeCount: 8900,
);

void main() {
  testWidgets('separates UP stats from manuscript counts and reuses actions', (
    tester,
  ) async {
    enableDesktopWindowing(tester);
    final authors = _Authors();
    final actions = FakeActions();
    final detail = ValueNotifier(_detail);
    final controlsInset = ValueNotifier(80.0);
    addTearDown(detail.dispose);
    addTearDown(controlsInset.dispose);
    UserId? opened;
    var detailsShown = 0;
    var commentsShown = 0;

    await _pump(
      tester,
      detail: detail,
      controlsInset: controlsInset,
      authors: authors,
      actions: actions,
      signedIn: true,
      onOpenUser: (id) => opened = id,
      onShowDescription: () => detailsShown++,
      onShowComments: () => commentsShown++,
    );
    expect(authors.requests.map((request) => request.$1), ['81']);
    expect(find.text('2.1万粉丝 · 69.1万获赞'), findsOneWidget);
    for (final count in ['1.4万', '215', '326', '47']) {
      expect(find.text(count), findsOneWidget);
    }
    expect(
      tester.getCenter(find.text('1.4万')).dy,
      lessThan(tester.getCenter(find.text('215')).dy),
    );
    await tester.tap(find.text('精选 UP 主'));
    await tester.tap(find.text('当前稿件的标题'));
    await tester.tap(findMaterialTooltip('评论'));
    await tester.tap(find.text('关注'));
    await tester.pumpAndSettle();
    expect(opened, const UserId('81'));
    expect(detailsShown, 1);
    expect(commentsShown, 1);
    expect(authors.writes, [('81', true)]);

    await tester.tap(findMaterialTooltip('点赞'));
    await tester.pumpAndSettle();
    expect(findMaterialTooltip('已点赞'), findsOneWidget);
    await tester.tap(findMaterialTooltip('投币'));
    await tester.pumpAndSettle();
    expect(actions.calls, ['load', 'like:true']);
    await tester.tap(find.text('1 枚'));
    await tester.pumpAndSettle();
    expect(actions.calls, ['load', 'like:true', 'coin:1']);
    expect(findMaterialTooltip('已投 1 枚'), findsOneWidget);
  });

  testWidgets('keeps the overlay above measured controls in a short viewport', (
    tester,
  ) async {
    final authors = _Authors();
    final detail = ValueNotifier(_detail);
    final controlsInset = ValueNotifier(80.0);
    addTearDown(detail.dispose);
    addTearDown(controlsInset.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(
      tester,
      detail: detail,
      controlsInset: controlsInset,
      authors: authors,
      actions: FakeActions(),
      textScale: 2,
    );
    final likes = find.text('1.4万');
    final coins = find.text('215');
    expect(tester.getCenter(likes).dx, tester.getCenter(coins).dx);

    controlsInset.value = 190;
    await tester.pump();
    expect(tester.getCenter(likes).dy, tester.getCenter(coins).dy);
    expect(tester.getBottomRight(coins).dy, lessThan(210));
    expect(find.text('当前稿件的标题').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('discards the old UP read and omits unavailable author totals', (
    tester,
  ) async {
    final pending = Completer<VideoAuthor>();
    final authors = _Authors()..firstResult = pending.future;
    final detail = ValueNotifier(_detail);
    final controlsInset = ValueNotifier(80.0);
    addTearDown(detail.dispose);
    addTearDown(controlsInset.dispose);
    await _pump(
      tester,
      detail: detail,
      controlsInset: controlsInset,
      authors: authors,
      actions: FakeActions(),
      settle: false,
    );
    expect(authors.requests.single.$1, '81');
    expect(find.textContaining('获赞'), findsNothing);

    detail.value = _other;
    await tester.pumpAndSettle();
    expect(authors.requests.map((request) => request.$1), ['81', '82']);
    expect(authors.requests.first.$2.isCancelled, isTrue);
    pending.complete(const VideoAuthor(following: false, likeCount: 100));
    await tester.pumpAndSettle();
    expect(find.text('0粉丝'), findsOneWidget);
    expect(find.textContaining('获赞'), findsNothing);
    expect(find.text('8900'), findsOneWidget);
    expect(find.text('1.4万'), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required ValueNotifier<VideoDetail> detail,
  required ValueNotifier<double> controlsInset,
  required _Authors authors,
  required FakeActions actions,
  bool signedIn = false,
  bool settle = true,
  double textScale = 1,
  ValueChanged<UserId>? onOpenUser,
  VoidCallback? onShowDescription,
  VoidCallback? onShowComments,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuth(signedIn)),
        videoActionsRepositoryProvider.overrideWithValue(actions),
        videoAuthorRepositoryProvider.overrideWithValue(authors),
      ],
      child: MaterialApp(
        builder: AppNoticeHost.builder,
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: ValueListenableBuilder(
              valueListenable: detail,
              builder: (context, value, _) => FeaturedVideoOverlay(
                detail: value,
                controlsInset: controlsInset,
                onLogin: () {},
                onOpenUser: onOpenUser ?? (_) {},
                onShowDescription: onShowDescription ?? () {},
                onShowComments: onShowComments ?? () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

class _Authors extends FollowRepositoryFake {
  Future<VideoAuthor>? firstResult;
  final requests = <(String, RequestCancellation)>[];

  @override
  Future<VideoAuthor> load(
    VideoAuthorId id,
    RequestCancellation cancellation,
  ) async {
    requests.add((id.value, cancellation));
    if (id.value == '82') {
      return const VideoAuthor(following: false, followerCount: 0);
    }
    return firstResult ??
        VideoAuthor(
          following: following,
          followerCount: 21400,
          likeCount: 691000,
        );
  }
}
