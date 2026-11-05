import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/profile/application/profile_controller.dart';
import 'package:bilisail/features/profile/domain/profile_repository.dart';
import 'package:bilisail/features/profile/presentation/profile_header.dart';
import 'package:bilisail/features/profile/presentation/profile_screen.dart';
import 'package:bilisail/shared/ui/playback_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../messages/message_fakes.dart';

const _id = UserId('1');
const _profile = UserProfile(id: _id, name: '我的个人空间');

void main() {
  late AuthFake auth;
  late _ProfileRepository repository;
  late ProviderContainer container;

  setUp(() {
    auth = AuthFake();
    repository = _ProfileRepository();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(repository),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await auth.stream.close();
  });

  Future<void> mount(
    WidgetTester tester, {
    ProfileSection section = ProfileSection.videos,
    VoidCallback? onBack,
  }) async {
    repository.pending = Completer<UserProfile>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: PlaybackNavigation(
              onBack: onBack ?? () {},
              onHome: () {},
              child: ProfileScreen(id: _id, initialSection: section),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  void expectNoPartialPage() {
    expect(find.byType(ProfileHeader), findsNothing);
    expect(find.byType(ProfileSectionNavigation), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('暂无公开内容'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  }

  testWidgets(
    'back remains available before load and after a profile failure',
    (tester) async {
      var backs = 0;
      await mount(tester, onBack: () => backs++);
      await tester.tap(find.byKey(const ValueKey('profile-back')));
      expect(backs, 1);
      repository.pending.completeError(
        const AppFailure(AppFailureKind.network, '资料加载失败'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-back')));
      expect(backs, 2);
    },
  );

  testWidgets('fast profile opens without a partial page or loading flash', (
    tester,
  ) async {
    await mount(tester);
    expectNoPartialPage();
    await tester.pump(const Duration(milliseconds: 100));
    expectNoPartialPage();
    expect(find.byType(CircularProgressIndicator), findsNothing);

    repository.pending.complete(_profile);
    await tester.pumpAndSettle();
    expect(find.text('我的个人空间'), findsOneWidget);
    expect(find.byType(ProfileSectionNavigation), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('slow profile shows feedback only after the loading delay', (
    tester,
  ) async {
    await mount(tester);
    await tester.pump(const Duration(milliseconds: 299));
    expectNoPartialPage();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expectNoPartialPage();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repository.pending.complete(_profile);
    await tester.pumpAndSettle();
    expect(find.byType(ProfileHeader), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('direct section entry waits for the header and keeps selection', (
    tester,
  ) async {
    await mount(tester, section: ProfileSection.followers);
    await tester.pump();
    expectNoPartialPage();
    repository.pending.complete(_profile);
    await tester.pumpAndSettle();
    expect(
      container.read(profileControllerProvider(_id)).section,
      ProfileSection.followers,
    );
    expect(find.text('followers列表内容'), findsOneWidget);
    expect(find.text('videos列表内容'), findsNothing);
  });

  testWidgets('profile failure preserves content and supports retry', (
    tester,
  ) async {
    await mount(tester);
    repository.pending.completeError(
      const AppFailure(AppFailureKind.network, '资料加载失败'),
    );
    await tester.pumpAndSettle();
    expect(find.text('资料加载失败'), findsOneWidget);
    expect(find.text('videos列表内容'), findsOneWidget);

    repository.pending = Completer<UserProfile>();
    await tester.tap(find.text('重试'));
    await tester.pump(const Duration(milliseconds: 100));
    expectNoPartialPage();
    repository.pending.complete(_profile);
    await tester.pumpAndSettle();
    expect(find.byType(ProfileHeader), findsOneWidget);
    expect(find.text('资料加载失败'), findsNothing);
  });

  testWidgets('refresh retains the loaded profile while waiting for updates', (
    tester,
  ) async {
    await mount(tester);
    repository.pending.complete(_profile);
    await tester.pumpAndSettle();
    final header = tester.getRect(find.byType(ProfileHeader));
    repository.pending = Completer<UserProfile>();
    final refresh = container
        .read(profileControllerProvider(_id).notifier)
        .loadProfile();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getRect(find.byType(ProfileHeader)), header);
    expect(find.text('videos列表内容'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    repository.pending.complete(_profile);
    await refresh;
    await tester.pumpAndSettle();
  });

  testWidgets('closing the page cancels the delayed loading feedback', (
    tester,
  ) async {
    await mount(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    repository.pending.complete(_profile);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

class _ProfileRepository implements ProfileRepository {
  late Completer<UserProfile> pending;

  @override
  String get accountScope => 'user:1';
  @override
  int get sessionEpoch => 0;

  @override
  Future<UserProfile> loadProfile(
    UserId id, {
    required RequestCancellation cancellation,
  }) => pending.future;

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
    ProfileCollectionId? collection,
    required RequestCancellation cancellation,
  }) async => ProfilePage(
    items: [
      ProfileEntry(
        id: section.name,
        kind: ProfileEntryKind.user,
        title: '${section.name}列表内容',
      ),
    ],
    hasMore: false,
  );
}
