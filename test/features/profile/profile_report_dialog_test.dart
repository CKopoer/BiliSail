import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/profile/application/profile_controller.dart';
import 'package:bilisail/features/profile/domain/profile_report.dart';
import 'package:bilisail/features/profile/domain/profile_repository.dart';
import 'package:bilisail/features/profile/presentation/profile_report_dialog.dart';
import 'package:bilisail/shared/ui/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../messages/message_fakes.dart';
import 'profile_report_fakes.dart';

void main() {
  late AuthFake auth;
  late ProfileReportFake repo;
  bool? result;
  late RequestCancellation owner;
  setUp(() {
    auth = AuthFake();
    repo = ProfileReportFake();
    result = null;
    owner = RequestCancellation();
  });
  tearDown(() async => auth.stream.close());
  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(800, 900),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          profileRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showAppDialog<bool>(
                    context: context,
                    builder: (_) => ProfileReportDialog(
                      cancellation: owner,
                      profile: const UserProfile(
                        id: UserId('2'),
                        name: '较长的目标用户名称',
                      ),
                    ),
                  );
                },
                child: const Text('打开举报'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开举报'));
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester, Enum value) async {
    final target = find.byKey(switch (value) {
      ProfileReportContent value => ValueKey(value),
      ProfileReportReason value => ValueKey(value),
      _ => throw ArgumentError('Unknown report option'),
    });
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Finder submit() => find.byKey(const ValueKey('profile-report-submit'));
  testWidgets(
    'requires content, supports multiselect and a removable single reason',
    (tester) async {
      await mount(tester);
      expect(tester.widget<FilledButton>(submit()).onPressed, isNull);
      await select(tester, ProfileReportContent.avatar);
      await select(tester, ProfileReportContent.signature);
      await select(tester, ProfileReportReason.sexualContent);
      await select(tester, ProfileReportReason.illegalPromotion);
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const ValueKey(ProfileReportReason.sexualContent)),
            )
            .selected,
        false,
      );
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const ValueKey(ProfileReportReason.illegalPromotion)),
            )
            .selected,
        true,
      );
      await select(tester, ProfileReportReason.illegalPromotion);
      expect(repo.reports, isEmpty);
      await tester.tap(submit());
      await tester.pumpAndSettle();
      expect(result, true);
      expect(repo.reports.single.$1, const UserId('2'));
      expect(repo.reports.single.$2.contents, {
        ProfileReportContent.avatar,
        ProfileReportContent.signature,
      });
      expect(repo.reports.single.$2.reason, isNull);
    },
  );
  testWidgets('cancel before submitting never writes', (tester) async {
    await mount(tester);
    await select(tester, ProfileReportContent.nickname);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, false);
    expect(repo.reports, isEmpty);
  });
  testWidgets('closing a pending form cancels and ignores a late success', (
    tester,
  ) async {
    repo.pending = Completer<void>();
    await mount(tester);
    await select(tester, ProfileReportContent.avatar);
    await tester.tap(submit());
    await tester.pump();
    expect(tester.widget<FilledButton>(submit()).onPressed, isNull);
    expect(repo.reports.length, 1);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(repo.signal!.isCancelled, true);
    repo.pending!.complete();
    await tester.pumpAndSettle();
    expect(result, false);
    expect(tester.takeException(), isNull);
  });
  testWidgets('uncertain response remains visible and cannot be resubmitted', (
    tester,
  ) async {
    repo.failure = const AppFailure(AppFailureKind.timeout, '超时');
    await mount(tester);
    await select(tester, ProfileReportContent.avatar);
    await tester.tap(submit());
    await tester.pumpAndSettle();
    expect(find.text('举报结果未确认，请勿重复提交'), findsOneWidget);
    expect(tester.widget<FilledButton>(submit()).onPressed, isNull);
    expect(result, isNull);
  });
  testWidgets('changing session before confirmation never sends', (
    tester,
  ) async {
    await mount(tester);
    await select(tester, ProfileReportContent.avatar);
    repo.sessionEpoch++;
    await tester.tap(submit());
    await tester.pumpAndSettle();
    expect(repo.reports, isEmpty);
    expect(find.text('登录状态已变化，请关闭后重新发起举报'), findsOneWidget);
  });
  testWidgets('closing the owning page cancels its still-visible report', (
    tester,
  ) async {
    repo.pending = Completer<void>();
    await mount(tester);
    await select(tester, ProfileReportContent.avatar);
    await tester.tap(submit());
    await tester.pump();
    owner.cancel();
    await tester.pump();
    expect(repo.signal!.isCancelled, true);
    expect(tester.widget<FilledButton>(submit()).onPressed, isNull);
    repo.pending!.complete();
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });
  for (final size in [
    const Size(320, 568),
    const Size(600, 320),
    const Size(1200, 900),
  ]) {
    testWidgets('scrollable form fits $size with large text', (tester) async {
      await mount(tester, size: size, scale: 2);
      expect(tester.takeException(), isNull);
      await select(tester, ProfileReportContent.avatar);
      await select(tester, ProfileReportReason.illegalPromotion);
      expect(submit().hitTestable(), findsOneWidget);
      await tester.tap(submit());
      await tester.pumpAndSettle();
      expect(
        repo.reports.single.$2.reason,
        ProfileReportReason.illegalPromotion,
      );
      expect(result, true);
      expect(tester.takeException(), isNull);
    });
  }
}
