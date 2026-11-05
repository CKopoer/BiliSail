import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/live/domain/live_room.dart';
import 'package:bilisail/features/profile/domain/profile_repository.dart';
import 'package:bilisail/features/profile/presentation/profile_header.dart';
import 'package:bilisail/shared/ui/app_cover_image.dart';
import 'package:bilisail/shared/ui/bili_badges.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/input_test_app.dart';
import '../../support/text_selection.dart';

const profile = UserProfile(
  id: UserId('3493276401272849'),
  name: '这是一个较长的用户名称用于验证放大文字与窄窗口',
  signature: '这里是用户简介，放大文字时应当自然换行并保留完整内容。',
  level: 6,
  verifyType: 0,
  verifyDescription: '个人认证信息',
  vipLabel: '年度大会员',
  vipStatus: 1,
  followingCount: 14,
  followerCount: 51000,
  likeCount: 1165000,
  videoCount: 1492,
);

Future<void> pumpLayout(
  WidgetTester tester,
  Widget child, {
  double width = 900,
  double scale = 1,
  TargetPlatform? platform,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    InputTestApp(
      theme: BiliTheme.light().copyWith(platform: platform),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'header uses real user images and anchors certification on avatar',
    (tester) async {
      final decorated = UserProfile(
        id: profile.id,
        name: '装扮用户',
        bannerUrl: Uri.https('i0.hdslb.com', '/banner.png'),
        pendantUrl: Uri.https('i0.hdslb.com', '/pendant.png'),
        vipStatus: 1,
        vipLabel: '年度大会员',
        vipLabelImageUrl: Uri.https('i0.hdslb.com', '/vip.png'),
        verifyType: 0,
        level: 6,
      );
      var backs = 0;
      await pumpLayout(
        tester,
        ProfileHeader(
          profile: decorated,
          onSelectSection: (_) {},
          onBack: () => backs++,
        ),
      );
      expect(
        tester
            .widget<AppCoverImage>(
              find.byKey(const ValueKey('profile-avatar-pendant')),
            )
            .url,
        decorated.pendantUrl.toString(),
      );
      expect(
        tester
            .widget<AppCoverImage>(
              find.byKey(const ValueKey('profile-vip-image')),
            )
            .url,
        decorated.vipLabelImageUrl.toString(),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('profile-banner')),
          matching: find.byType(AppCoverImage),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('profile-avatar')),
          matching: find.byType(BiliVerifyBadge),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('profile-back')));
      expect(backs, 1);
    },
  );
  testWidgets('expired VIP does not show a membership badge', (tester) async {
    await pumpLayout(
      tester,
      ProfileHeader(
        profile: UserProfile(
          id: profile.id,
          name: '普通用户',
          vipStatus: 0,
          vipLabel: '年度大会员',
          vipLabelImageUrl: Uri.https('i0.hdslb.com', '/expired.png'),
        ),
        onSelectSection: (_) {},
      ),
    );
    expect(find.text('年度大会员'), findsNothing);
    expect(find.byKey(const ValueKey('profile-vip-image')), findsNothing);
  });
  testWidgets(
    'expanded biography survives switching between narrow and wide layouts',
    (tester) async {
      final longProfile = UserProfile(
        id: profile.id,
        name: profile.name,
        signature: List.filled(30, '这是一段需要展开阅读的简介。').join(),
      );
      await pumpLayout(
        tester,
        ProfileHeader(profile: longProfile, onSelectSection: (_) {}),
        width: 375,
      );
      await tester.tap(find.byKey(const ValueKey('profile-signature-toggle')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text(longProfile.signature)).maxLines,
        isNull,
      );
      await tester.binding.setSurfaceSize(const Size(1440, 1400));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('profile-header-wide')), findsOneWidget);
      expect(
        tester.widget<Text>(find.text(longProfile.signature)).maxLines,
        isNull,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('profile-signature-toggle')),
      );
      await tester.tap(find.byKey(const ValueKey('profile-signature-toggle')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text(longProfile.signature)).maxLines, 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('profile name UID signature and verification support drag copy', (
    tester,
  ) async {
    ProfileSection? selected;
    await pumpLayout(
      tester,
      ProfileHeader(
        profile: profile,
        onSelectSection: (value) => selected = value,
      ),
      width: 320,
      scale: 2,
      platform: TargetPlatform.windows,
    );
    await tester.tap(find.byKey(const ValueKey('profile-signature-toggle')));
    await tester.pumpAndSettle();
    for (final value in [
      profile.name,
      'UID ${profile.id.value}',
      profile.signature,
      '个人认证信息',
    ]) {
      expect(await selectAndCopyText(tester, find.text(value)), value);
    }
    await tester.ensureVisible(
      find.byKey(const ValueKey('profile-following-stat')),
    );
    await tester.tap(find.byKey(const ValueKey('profile-following-stat')));
    expect(selected, ProfileSection.following);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile UID supports touch long press and toolbar copy', (
    tester,
  ) async {
    await pumpLayout(
      tester,
      ProfileHeader(profile: profile, onSelectSection: (_) {}),
      platform: TargetPlatform.android,
    );
    expect(
      await selectAndCopyText(
        tester,
        find.text('UID ${profile.id.value}'),
        touch: true,
      ),
      profile.id.value,
    );
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 375.0, 900.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('profile header fits width $width at text scale $scale', (
        tester,
      ) async {
        ProfileSection? selected;
        await pumpLayout(
          tester,
          ProfileHeader(
            profile: profile,
            liveRoom: const ProfileLiveRoom(id: RoomId('1024'), isLive: true),
            onOpenLiveRoom: () {},
            isSelf: true,
            onSelectSection: (value) => selected = value,
          ),
          width: width,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.text(profile.name), findsOneWidget);
        expect(find.text(profile.signature), findsOneWidget);
        expect(find.text('UID ${profile.id.value}'), findsOneWidget);
        expect(find.text('我的主页'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('profile-following-stat')));
        expect(selected, ProfileSection.following);
        await tester.tap(find.byKey(const ValueKey('profile-followers-stat')));
        expect(selected, ProfileSection.followers);
      });
    }
  }

  testWidgets('profile statistics share a baseline and target height', (
    tester,
  ) async {
    await pumpLayout(
      tester,
      ProfileHeader(profile: profile, onSelectSection: (_) {}),
    );
    final statisticRects = [
      for (final name in ['following', 'followers', 'likes', 'videos'])
        tester.getRect(find.byKey(ValueKey('profile-$name-stat'))),
    ];
    for (final rect in statisticRects) {
      expect(rect.top, statisticRects.first.top);
      expect(rect.height, statisticRects.first.height);
      expect(rect.height, greaterThanOrEqualTo(44));
    }
  });
  for (final isLive in [false, true]) {
    testWidgets('profile live room entry supports live status $isLive', (
      tester,
    ) async {
      var opens = 0;
      await pumpLayout(
        tester,
        ProfileHeader(
          profile: profile,
          liveRoom: ProfileLiveRoom(id: const RoomId('1024'), isLive: isLive),
          onSelectSection: (_) {},
          onOpenLiveRoom: () => opens++,
        ),
      );
      expect(find.text(isLive ? '正在直播' : '直播间'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('profile-live-room')));
      expect(opens, 1);
    });
  }
  testWidgets('no room and invalid room do not offer navigation', (
    tester,
  ) async {
    for (final room in [
      null,
      const ProfileLiveRoom(id: RoomId('0'), isLive: true),
    ]) {
      await pumpLayout(
        tester,
        ProfileHeader(
          profile: profile,
          liveRoom: room,
          onSelectSection: (_) {},
          onOpenLiveRoom: () => fail('Invalid room must not navigate'),
        ),
      );
      expect(find.byKey(const ValueKey('profile-live-room')), findsNothing);
    }
  });

  testWidgets('enlarged narrow navigation can reach the followers tab', (
    tester,
  ) async {
    ProfileSection? selected;
    await pumpLayout(
      tester,
      ProfileSectionNavigation(
        section: ProfileSection.videos,
        onSelected: (value) => selected = value,
      ),
      width: 320,
      scale: 2,
    );
    expect(tester.takeException(), isNull);
    final navigation = find.byType(ProfileSectionNavigation);
    await tester.drag(
      find.descendant(
        of: navigation,
        matching: find.byType(SingleChildScrollView),
      ),
      const Offset(-650, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-tab-followers')));
    expect(selected, ProfileSection.followers);
  });

  for (final (width, scale) in [
    (320.0, 1.0),
    (320.0, 2.0),
    (375.0, 1.0),
    (375.0, 2.0),
    (500.0, 1.0),
  ]) {
    testWidgets(
      'narrow toolbar groups playback and sort above search at $width/$scale',
      (tester) async {
        final keyword = TextEditingController();
        addTearDown(keyword.dispose);
        String? order, searched;
        var plays = 0;
        await pumpLayout(
          tester,
          ProfileVideoToolbar(
            order: 'pubdate',
            keywordController: keyword,
            onOrderChanged: (value) => order = value,
            onSearch: (value) => searched = value,
            onPlayAll: () => plays++,
          ),
          width: width,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
        final search = find.byKey(const ValueKey('profile-video-search'));
        expect(search, findsNothing);
        await tester.tap(find.byKey(const ValueKey('profile-search-toggle')));
        await tester.pumpAndSettle();
        final sort = find.byKey(const ValueKey('profile-video-sort'));
        final searchRect = tester.getRect(search);
        final sortRect = tester.getRect(sort);
        final play = find.byKey(const ValueKey('profile-play-all'));
        final playRect = tester.getRect(play);
        expect(playRect.right, width - 16);
        expect(searchRect.left, 16);
        expect(searchRect.right, width - 16);
        expect(searchRect.top, greaterThanOrEqualTo(playRect.bottom + 8));
        expect(searchRect.top, greaterThanOrEqualTo(sortRect.bottom + 8));
        if (scale == 1) {
          expect(sortRect.left, 16);
          expect(playRect.center.dy, closeTo(sortRect.center.dy, .01));
        }
        await tester.tap(play);
        expect(plays, 1);
        await tester.tap(sort);
        await tester.pumpAndSettle();
        await tester.tap(find.text('最多播放').last);
        await tester.pumpAndSettle();
        expect(order, 'click');
        await tester.enterText(search, '测试投稿');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        expect(searched, '测试投稿');
        searched = null;
        await tester.tap(find.byTooltip('搜索投稿'));
        expect(searched, '测试投稿');
      },
    );
  }

  testWidgets('wide toolbar places play all at the trailing edge', (
    tester,
  ) async {
    final keyword = TextEditingController();
    addTearDown(keyword.dispose);
    await pumpLayout(
      tester,
      ProfileVideoToolbar(
        order: 'pubdate',
        keywordController: keyword,
        onOrderChanged: (_) {},
        onSearch: (_) {},
      ),
    );
    final search = tester.getRect(
      find.byKey(const ValueKey('profile-video-search')),
    );
    final sort = tester.getRect(
      find.byKey(const ValueKey('profile-video-sort')),
    );
    final play = tester.getRect(find.byKey(const ValueKey('profile-play-all')));
    expect(play.right, 884);
    expect(sort.left, 16);
    expect(play.left, greaterThanOrEqualTo(search.right + 12));
    expect(search.left, greaterThan(sort.right + 100));
    expect(search.center.dy, closeTo(sort.center.dy, .01));
    expect(search.center.dy, closeTo(play.center.dy, .01));
    expect(tester.takeException(), isNull);
  });

  for (final width in [375.0, 900.0]) {
    testWidgets(
      'playback loading keeps toolbar stable and search draft at $width',
      (tester) async {
        final keyword = TextEditingController();
        addTearDown(keyword.dispose);
        late StateSetter update;
        var loading = false;
        await pumpLayout(
          tester,
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return ProfileVideoToolbar(
                order: 'pubdate',
                keywordController: keyword,
                onOrderChanged: (_) {},
                onSearch: (_) {},
                onPlayAll: () {},
                playAllLoading: loading,
              );
            },
          ),
          width: width,
        );
        final play = find.byKey(const ValueKey('profile-play-all'));
        final sort = find.byKey(const ValueKey('profile-video-sort'));
        final search = find.byKey(const ValueKey('profile-video-search'));
        if (width < 600) {
          await tester.tap(find.byKey(const ValueKey('profile-search-toggle')));
          await tester.pumpAndSettle();
        }
        final before = [
          for (final finder in [play, sort, search]) tester.getRect(finder),
        ];
        await tester.enterText(search, '保留搜索草稿');
        update(() => loading = true);
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.widget<TextButton>(play).onPressed, isNull);
        expect(
          find.descendant(
            of: play,
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );
        expect([
          for (final finder in [play, sort, search]) tester.getRect(finder),
        ], before);
        await tester.binding.setSurfaceSize(
          Size(width < 600 ? 900 : 375, 1400),
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(keyword.text, '保留搜索草稿');
        expect(tester.widget<TextField>(search).controller, same(keyword));
        update(() => loading = false);
        await tester.pumpAndSettle();
        expect(tester.widget<TextButton>(play).onPressed, isNotNull);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
