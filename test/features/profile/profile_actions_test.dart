import 'dart:async';

import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/profile/application/profile_controller.dart';
import 'package:bilisail/features/profile/domain/profile_repository.dart';
import 'package:bilisail/features/profile/presentation/profile_screen.dart';
import 'package:bilisail/features/video/application/video_author_controller.dart';
import 'package:bilisail/features/video/domain/video_actions_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/follow_repository_fake.dart';
import '../messages/message_fakes.dart';

void main() {
  late AuthFake auth;
  late FollowRepositoryFake follow;
  setUp(() {
    auth = AuthFake();
    follow = FollowRepositoryFake()..accountScope = 'user:1';
  });
  tearDown(() async => auth.stream.close());

  Future<void> mount(
    WidgetTester tester, {
    double width = 900,
    double scale = 1,
    bool dark = false,
    UserId id = const UserId('2'),
    ValueChanged<UserProfile>? onMessage,
    VoidCallback? onLogin,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          profileRepositoryProvider.overrideWithValue(_ProfileRepository()),
          videoAuthorRepositoryProvider.overrideWithValue(follow),
        ],
        child: MaterialApp(
          theme: dark ? BiliTheme.dark() : BiliTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child ?? const SizedBox(),
          ),
          home: Scaffold(
            body: ProfileScreen(id: id, onMessage: onMessage, onLogin: onLogin),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 375.0, 900.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'profile actions fit $width in dark=$dark at twice text size',
        (tester) async {
          UserProfile? recipient;
          await mount(
            tester,
            width: width,
            scale: 2,
            dark: dark,
            onMessage: (value) => recipient = value,
          );
          expect(tester.takeException(), isNull);
          final message = find.byKey(const ValueKey('profile-message'));
          expect(message.hitTestable(), findsOneWidget);
          await tester.tap(message);
          expect(recipient?.id, const UserId('2'));
          expect(follow.writes, isEmpty);
          await tester.tap(
            find.descendant(
              of: find.byKey(const ValueKey('profile-follow')),
              matching: find.text('关注'),
            ),
          );
          await tester.pumpAndSettle();
          expect(follow.writes, [('2', true)]);
          expect(find.text('已关注'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('own profile hides both actions without a follow read', (
    tester,
  ) async {
    await mount(tester, id: const UserId('1'));
    expect(find.byKey(const ValueKey('profile-follow')), findsNothing);
    expect(find.byKey(const ValueKey('profile-message')), findsNothing);
    expect(follow.reads, 0);
  });
  testWidgets('guest actions request login without writes', (tester) async {
    auth.emit(const AuthState());
    follow.accountScope = 'guest';
    var logins = 0;
    await mount(
      tester,
      onLogin: () => logins++,
      onMessage: (_) => fail('Guest must sign in first'),
    );
    await tester.tap(find.byKey(const ValueKey('profile-message')));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('profile-follow')),
        matching: find.byType(TextButton),
      ),
    );
    expect(logins, 2);
    expect(follow.writes, isEmpty);
  });
  testWidgets('follow menu supports groups and explicit unfollow', (
    tester,
  ) async {
    follow.following = true;
    await mount(tester, width: 320, scale: 2);
    await tester.tap(find.text('已关注'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置分组'));
    await tester.pumpAndSettle();
    expect(find.text('测试分组'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已关注'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消关注'));
    await tester.pumpAndSettle();
    expect(follow.writes, [('2', false)]);
  });
  testWidgets('busy and uncertain follow never replay; narrow refresh wraps', (
    tester,
  ) async {
    final pending = follow.pending = Completer<void>();
    await mount(tester, width: 320, scale: 2);
    final button = find.descendant(
      of: find.byKey(const ValueKey('profile-follow')),
      matching: find.byType(TextButton),
    );
    await tester.tap(button);
    await tester.pump();
    await tester.tap(button);
    expect(follow.writes, [('2', true)]);
    pending.completeError(const UnknownWriteOutcome());
    await tester.pumpAndSettle();
    expect(find.text('刷新状态'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('刷新状态'));
    await tester.pumpAndSettle();
    expect(follow.writes, [('2', true)]);
    expect(tester.takeException(), isNull);
  });
}

class _ProfileRepository implements ProfileRepository {
  @override
  String get accountScope => 'user:1';
  @override
  int get sessionEpoch => 0;
  @override
  Future<UserProfile> loadProfile(
    UserId id, {
    required RequestCancellation cancellation,
  }) async => UserProfile(
    id: id,
    name: '较长的用户名称与主页操作按钮',
    signature: '用户简介在窄窗口中自然换行。',
    followingCount: 12,
    followerCount: 50000,
  );
  @override
  Future<ProfileLiveRoom?> loadLiveRoom(
    UserId id, {
    required RequestCancellation cancellation,
  }) async => null;
  @override
  Future<ProfilePage> loadEntries(
    UserId id,
    ProfileSection section, {
    required int page,
    String? cursor,
    String order = 'pubdate',
    String keyword = '',
    String? folderId,
    required RequestCancellation cancellation,
  }) async => const ProfilePage(items: [], hasMore: false);
}
