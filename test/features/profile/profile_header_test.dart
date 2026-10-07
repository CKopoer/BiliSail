import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/profile/domain/profile_repository.dart';
import 'package:bilisail/features/profile/presentation/profile_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const profile = UserProfile(
  id: UserId('3493276401272849'),
  name: '这是一个较长的用户名称用于验证放大文字与窄窗口',
  signature: '这里是用户简介，放大文字时应当自然换行并保留完整内容。',
  level: 6,
  verifyType: 0,
  verifyDescription: '个人认证信息',
  vipLabel: '年度大会员',
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
}) async {
  await tester.binding.setSurfaceSize(Size(width, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: BiliTheme.light(),
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
    testWidgets('toolbar fits one row at width $width and text scale $scale', (
      tester,
    ) async {
      final keyword = TextEditingController();
      addTearDown(keyword.dispose);
      String? order, searched;
      await pumpLayout(
        tester,
        ProfileVideoToolbar(
          order: 'pubdate',
          keywordController: keyword,
          onOrderChanged: (value) => order = value,
          onSearch: (value) => searched = value,
        ),
        width: width,
        scale: scale,
      );
      expect(tester.takeException(), isNull);
      final search = find.byKey(const ValueKey('profile-video-search'));
      final sort = find.byKey(const ValueKey('profile-video-sort'));
      final searchRect = tester.getRect(search);
      final sortRect = tester.getRect(sort);
      expect(searchRect.center.dy, closeTo(sortRect.center.dy, .01));
      expect(searchRect.right, width - 16);
      expect(searchRect.left, greaterThanOrEqualTo(sortRect.right + 12));
      expect(searchRect.width, lessThanOrEqualTo(260));
      expect(searchRect.width, greaterThan(80));
      if (width <= 375) {
        expect(searchRect.width, lessThan(260));
        expect(searchRect.left, closeTo(sortRect.right + 12, .01));
      }
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
    });
  }

  testWidgets('wide toolbar places search at the trailing edge', (
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
    expect(search.right, 884);
    expect(search.left, greaterThan(sort.right + 100));
    expect(search.center.dy, closeTo(sort.center.dy, .01));
    expect(tester.takeException(), isNull);
  });
}
