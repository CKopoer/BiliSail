import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/profile/application/profile_controller.dart';
import 'package:bilisail/features/profile/application/profile_report_controller.dart';
import 'package:bilisail/features/profile/domain/profile_report.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../messages/message_fakes.dart';
import 'profile_report_fakes.dart';

void main() {
  const id = UserId('2');
  final provider = profileReportControllerProvider(id);
  final report = ProfileReport(contents: {ProfileReportContent.avatar});
  late AuthFake auth;
  late ProfileReportFake repo;
  late ProviderContainer container;
  var disposed = false;
  setUp(() {
    auth = AuthFake();
    repo = ProfileReportFake();
    disposed = false;
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(repo),
      ],
    );
    container.listen(provider, (_, _) {});
  });
  tearDown(() async {
    if (!disposed) container.dispose();
    await auth.stream.close();
  });
  ProfileReportController controller() => container.read(provider.notifier);
  test('report contents are required and immutable', () {
    expect(() => ProfileReport(contents: {}), throwsArgumentError);
    final contents = {ProfileReportContent.avatar};
    final value = ProfileReport(contents: contents);
    contents.clear();
    expect(value.contents, {ProfileReportContent.avatar});
    expect(() => value.contents.clear(), throwsUnsupportedError);
  });
  test(
    'only explicit submission writes once while pending and after success',
    () async {
      expect(repo.reports, isEmpty);
      repo.pending = Completer<void>();
      final operation = controller().submit(report);
      await controller().submit(report);
      expect(repo.reports.length, 1);
      expect(container.read(provider).status, ProfileReportStatus.submitting);
      repo.pending!.complete();
      await operation;
      expect(container.read(provider).status, ProfileReportStatus.submitted);
      await controller().submit(report);
      expect(repo.reports.length, 1);
    },
  );
  for (final kind in [
    AppFailureKind.timeout,
    AppFailureKind.network,
    AppFailureKind.protocol,
  ]) {
    test('uncertain $kind cannot be submitted again', () async {
      repo.failure = AppFailure(kind, '失败');
      await controller().submit(report);
      expect(container.read(provider).status, ProfileReportStatus.uncertain);
      await controller().submit(report);
      expect(repo.reports.length, 1);
    });
  }
  test('definite rejection allows another explicit submission', () async {
    repo.failure = const AppFailure(AppFailureKind.playback, '不可用');
    await controller().submit(report);
    expect(container.read(provider).status, ProfileReportStatus.failed);
    expect(container.read(provider).message, '举报未被受理，请稍后重试');
    repo.failure = null;
    await controller().submit(report);
    expect(repo.reports.length, 2);
    expect(container.read(provider).status, ProfileReportStatus.submitted);
  });
  for (final pending in [false, true]) {
    test(
      'epoch change ${pending ? 'during' : 'before'} submission expires the form',
      () async {
        Future<void>? operation;
        if (pending) {
          repo.pending = Completer<void>();
          operation = controller().submit(report);
        }
        repo.sessionEpoch++;
        if (pending) {
          repo.pending!.complete();
          await operation;
        } else {
          await controller().submit(report);
        }
        expect(container.read(provider).status, ProfileReportStatus.expired);
        expect(repo.reports.length, pending ? 1 : 0);
      },
    );
  }
  test(
    'account transition cancels pending write and ignores late success',
    () async {
      repo.pending = Completer<void>();
      final operation = controller().submit(report);
      repo.accountScope = 'guest';
      repo.sessionEpoch++;
      auth.emit(const AuthState());
      await Future<void>.delayed(Duration.zero);
      expect(repo.signal!.isCancelled, true);
      expect(container.read(provider).status, ProfileReportStatus.expired);
      repo.pending!.complete();
      await operation;
      expect(container.read(provider).status, ProfileReportStatus.expired);
    },
  );
  test('disposing cancels pending write and ignores late errors', () async {
    repo.pending = Completer<void>();
    final operation = controller().submit(report);
    container.dispose();
    disposed = true;
    expect(repo.signal!.isCancelled, true);
    repo.pending!.completeError(const AppFailure(AppFailureKind.network, '失败'));
    await operation;
  });
  for (final own in [false, true]) {
    test('${own ? 'self' : 'guest'} cannot report', () async {
      auth.emit(
        own
            ? const AuthState(status: AuthStatus.signedIn, mid: '2')
            : const AuthState(),
      );
      repo.accountScope = own ? 'user:2' : 'guest';
      await controller().submit(report);
      expect(repo.reports, isEmpty);
    });
  }
}
