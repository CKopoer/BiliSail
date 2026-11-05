import 'dart:async';

import 'package:bilisail/core/platform/external_links.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/profile/application/profile_actions_controller.dart';
import 'package:bilisail/features/profile/application/profile_controller.dart';
import 'package:bilisail/features/profile/domain/profile_repository.dart';
import 'package:bilisail/features/profile/domain/profile_report.dart';
import 'package:bilisail/features/profile/presentation/profile_screen.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:bilisail/features/video/application/video_author_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../messages/message_fakes.dart';
import '../../support/follow_repository_fake.dart';

const _id = UserId('2');
void main() {
  late AuthFake auth;
  late _Repository repo;
  late ProviderContainer container;
  var disposed = false;
  final provider = profileActionsControllerProvider(_id);
  final opened = <Uri>[];
  setUp(() {
    auth = AuthFake();
    repo = _Repository();
    disposed = false;
    opened.clear();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        videoAuthorRepositoryProvider.overrideWithValue(
          FollowRepositoryFake()..accountScope = 'user:1',
        ),
        profileRepositoryProvider.overrideWithValue(repo),
        webLinkOpenerProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return true;
        }),
      ],
    );
    container.listen(provider, (_, _) {});
  });
  tearDown(() async {
    if (!disposed) container.dispose();
    await auth.stream.close();
  });
  Future<void> ready() => Future<void>.delayed(Duration.zero);
  ProfileActionsController controller() => container.read(provider.notifier);
  test('blacklist writes are explicit, serialized, and reconciled after uncertainty', () async {
    await ready();
    expect(container.read(provider).blocked, false);
    expect(repo.writes, isEmpty);
    final pending = repo.write = Completer<void>();
    final write = controller().setBlocked(true);
    await controller().setBlocked(true);
    expect(repo.writes, [true]);
    pending.completeError(const AppFailure(AppFailureKind.timeout, '超时'));
    await write;
    expect(container.read(provider).blocked, isNull);
    await controller().setBlocked(true);
    expect(repo.writes, [true]);
    repo.blocked = true;
    await controller().refresh();
    expect(container.read(provider).blocked, true);
    repo.write = null;
    await controller().setBlocked(false);
    expect(repo.writes, [true, false]);
  });
  for (final write in [false, true]) {
    test(
      'closing profile cancels and ignores late ${write ? 'write' : 'read'}',
      () async {
        Future<void>? task;
        if (write) {
          await ready();
          repo.write = Completer<void>();
          task = controller().setBlocked(true);
        } else {
          repo.read = Completer<bool>();
          await ready();
        }
        final cancellation = repo.signals.last;
        container.dispose();
        disposed = true;
        expect(cancellation.isCancelled, true);
        if (write) {
          repo.write!.complete();
          await task;
        } else {
          repo.read!.complete(false);
          await ready();
        }
      },
    );
  }
  test(
    'account switch isolates late state and never writes as a guest',
    () async {
      repo.read = Completer<bool>();
      await ready();
      final signal = repo.signals.last;
      repo.accountScope = 'guest';
      repo.sessionEpoch++;
      auth.emit(const AuthState());
      await ready();
      expect(signal.isCancelled, true);
      repo.read!.complete(true);
      await ready();
      expect(container.read(provider).blocked, isNull);
      await controller().setBlocked(true);
      expect(repo.writes, isEmpty);
    },
  );
  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: AppNoticeHost.builder,
          home: const Scaffold(body: ProfileScreen(id: _id, isSelf: false)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> menu(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const ValueKey('profile-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'blacklist requires confirmation and report stays inside the app',
    (tester) async {
      await mount(tester);
      await menu(tester, '加入黑名单');
      expect(repo.writes, isEmpty);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(repo.writes, isEmpty);
      await menu(tester, '加入黑名单');
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(repo.writes, [true]);
      await menu(tester, '举报');
      expect(find.text('举报 UP 主'), findsOneWidget);
      expect(repo.reports, isEmpty);
      await tester.tap(find.text('头像违规'));
      await tester.pump();
      await tester.tap(find.text('提交举报'));
      await tester.pumpAndSettle();
      expect(repo.reports.single.contents, {ProfileReportContent.avatar});
      expect(find.text('举报已提交'), findsOneWidget);
      expect(opened, isEmpty);
    },
  );
  testWidgets('confirmation does not cross a changed session epoch', (
    tester,
  ) async {
    await mount(tester);
    await menu(tester, '加入黑名单');
    repo.sessionEpoch++;
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(repo.writes, isEmpty);
  });
}

final class _Repository
    implements
        ProfileRepository,
        ProfileActionsRepository,
        ProfileReportRepository {
  @override
  String accountScope = 'user:1';
  @override
  int sessionEpoch = 1;
  bool blocked = false;
  Completer<bool>? read;
  Completer<void>? write;
  final writes = <bool>[];
  final signals = <RequestCancellation>[];
  final reports = <ProfileReport>[];
  @override
  Future<void> report(
    UserId id,
    ProfileReport report, {
    required RequestCancellation cancellation,
  }) async {
    reports.add(report);
  }

  @override
  Future<bool> loadBlocked(
    UserId id, {
    required RequestCancellation cancellation,
  }) async {
    signals.add(cancellation);
    return read == null ? blocked : read!.future;
  }

  @override
  Future<void> setBlocked(
    UserId id,
    bool value, {
    required RequestCancellation cancellation,
  }) async {
    signals.add(cancellation);
    writes.add(value);
    if (write case final pending?) await pending.future;
    blocked = value;
  }

  @override
  Future<UserProfile> loadProfile(
    UserId id, {
    required RequestCancellation cancellation,
  }) async => UserProfile(id: id, name: '目标用户');
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
  }) async => const ProfilePage(items: [], hasMore: false);
}
