import 'dart:async';

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/video/application/video_actions_controller.dart';
import 'package:bilisail/features/video/application/video_author_controller.dart';
import 'package:bilisail/features/video/domain/video_author_repository.dart';
import 'package:bilisail/features/video/presentation/featured_video_overlay.dart';
import 'package:bilisail/features/video/presentation/video_actions_bar.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:bilisail/shared/ui/network_avatar.dart';
import 'package:bilisail/shared/ui/featured_paging_scope.dart';
import 'package:bilisail/shared/ui/user_follow_button.dart';
import 'package:flutter/services.dart';
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
  shareCount: 68,
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
    final controlsGeometry = FeaturedControlsGeometry()..showAudioToolbar(80);
    addTearDown(detail.dispose);
    addTearDown(controlsGeometry.dispose);
    UserId? opened;
    var detailsShown = 0;
    var commentsShown = 0;

    await _pump(
      tester,
      detail: detail,
      controlsGeometry: controlsGeometry,
      authors: authors,
      actions: actions,
      signedIn: true,
      onOpenUser: (id) => opened = id,
      onShowDescription: () => detailsShown++,
      onShowComments: () => commentsShown++,
    );
    expect(authors.requests.map((request) => request.$1), ['81']);
    expect(find.text('2.1万粉丝 · 69.1万获赞'), findsOneWidget);
    final avatar = find.byType(NetworkAvatar);
    expect(tester.getSize(avatar), const Size.square(32));
    final avatarTarget = find
        .ancestor(of: avatar, matching: find.byType(InkWell))
        .first;
    expect(tester.getSize(avatarTarget), const Size.square(38));
    expect(tester.getSize(find.byType(UserFollowButton)).width, lessThan(80));
    expect(
      tester.widget<Text>(find.text(_detail.summary.title)).style?.fontSize,
      14,
    );
    for (final count in ['1.4万', '215', '326', '47', '68']) {
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

  testWidgets('guest shares the currently visible video after paging', (
    tester,
  ) async {
    final detail = ValueNotifier(_detail);
    final geometry = FeaturedControlsGeometry();
    final actions = FakeActions();
    addTearDown(detail.dispose);
    addTearDown(geometry.dispose);
    final copied = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await _pump(
      tester,
      detail: detail,
      controlsGeometry: geometry,
      authors: _Authors(),
      actions: actions,
    );
    for (final video in [_detail, _other]) {
      detail.value = video;
      await tester.pumpAndSettle();
      final share = findMaterialTooltip('分享');
      final caption = video.shareCount?.toString() ?? '—';
      expect(
        find.descendant(of: share, matching: find.text(caption)),
        findsOneWidget,
      );
      await tester.tap(share);
      await tester.pump();
      expect(
        copied.last,
        'https://www.bilibili.com/video/${video.summary.id.value}',
      );
      expect(find.text('视频链接已复制'), findsOneWidget);
    }
    expect(copied, hasLength(2));
    expect(actions.calls, isEmpty);
  });

  testWidgets('keeps the overlay above measured controls in a short viewport', (
    tester,
  ) async {
    final authors = _Authors();
    final detail = ValueNotifier(_detail);
    final controlsGeometry = FeaturedControlsGeometry()..showAudioToolbar(60);
    addTearDown(detail.dispose);
    addTearDown(controlsGeometry.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(
      tester,
      detail: detail,
      controlsGeometry: controlsGeometry,
      authors: authors,
      actions: FakeActions(),
      textScale: 2,
    );
    final likes = find.text('1.4万');
    final coins = find.text('215');
    expect(tester.getCenter(likes).dx, tester.getCenter(coins).dx);

    controlsGeometry.height.value = 190;
    await tester.pump();
    expect(
      tester.getCenter(likes).dy,
      moreOrLessEquals(tester.getCenter(coins).dy),
    );
    expect(tester.getBottomRight(coins).dy, lessThan(210));
    final title = find.text(_detail.summary.title);
    final card = find
        .ancestor(
          of: title,
          matching: find.byWidgetPredicate(
            (widget) => widget is Material && widget.color == Colors.black54,
          ),
        )
        .first;
    final actions = find.byType(FeaturedVideoActions);
    expect(tester.getRect(card).bottom, lessThan(tester.getRect(actions).top));
    expect(title.hitTestable(), findsOneWidget);
    expect(findMaterialTooltip('分享').hitTestable(), findsOneWidget);
    expect(findMaterialTooltip('更多').hitTestable(), findsOneWidget);
    tester.view.physicalSize = const Size(700, 360);
    await tester.pump();
    expect(
      tester.getCenter(likes).dy,
      moreOrLessEquals(tester.getCenter(coins).dy),
    );
    expect(
      tester.getRect(card).bottom,
      moreOrLessEquals(tester.getRect(actions).bottom),
    );
    expect(tester.getRect(card).right, lessThan(tester.getRect(actions).left));
    expect(title.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('discards the old UP read and omits unavailable author totals', (
    tester,
  ) async {
    final pending = Completer<VideoAuthor>();
    final authors = _Authors()..firstResult = pending.future;
    final detail = ValueNotifier(_detail);
    final controlsGeometry = FeaturedControlsGeometry()..showAudioToolbar(80);
    addTearDown(detail.dispose);
    addTearDown(controlsGeometry.dispose);
    await _pump(
      tester,
      detail: detail,
      controlsGeometry: controlsGeometry,
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
  required FeaturedControlsGeometry controlsGeometry,
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
                controlsGeometry: controlsGeometry,
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
