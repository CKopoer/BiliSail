import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/profile_report.dart';
import 'profile_controller.dart';

final profileReportControllerProvider = NotifierProvider.autoDispose
    .family<ProfileReportController, ProfileReportState, UserId>(
      ProfileReportController.new,
    );

enum ProfileReportStatus {
  ready,
  submitting,
  submitted,
  failed,
  uncertain,
  expired,
}

final class ProfileReportState {
  const ProfileReportState({
    this.status = ProfileReportStatus.ready,
    this.message,
  });
  final ProfileReportStatus status;
  final String? message;
  bool get canSubmit =>
      status == ProfileReportStatus.ready ||
      status == ProfileReportStatus.failed;
}

class ProfileReportController extends Notifier<ProfileReportState> {
  ProfileReportController(this.id);
  final UserId id;
  late String _scope;
  late int _epoch;
  late RequestCancellation _cancellation;

  @override
  ProfileReportState build() {
    final repository = ref.read(profileRepositoryProvider);
    _scope = repository.accountScope;
    _epoch = repository.sessionEpoch;
    _cancellation = RequestCancellation();
    ref.onDispose(_cancellation.cancel);
    ref.listen(authControllerProvider, (_, _) {
      if (!_current()) _expire();
    });
    return const ProfileReportState();
  }

  bool _current() {
    if (!ref.mounted) return false;
    final repository = ref.read(profileRepositoryProvider);
    final auth = ref.read(authControllerProvider);
    return !_cancellation.isCancelled &&
        auth.isSignedIn &&
        auth.mid != id.value &&
        _scope == 'user:${auth.mid}' &&
        repository.accountScope == _scope &&
        repository.sessionEpoch == _epoch;
  }

  void _expire() {
    _cancellation.cancel();
    if (ref.mounted && state.status != ProfileReportStatus.expired) {
      state = const ProfileReportState(
        status: ProfileReportStatus.expired,
        message: '登录状态已变化，请关闭后重新发起举报',
      );
    }
  }

  void cancel() {
    _cancellation.cancel();
    // The owning page may cancel from dispose while Flutter locks its tree.
    Future<void>.microtask(() {
      if (ref.mounted && state.status != ProfileReportStatus.submitted) {
        state = const ProfileReportState(
          status: ProfileReportStatus.expired,
          message: '举报已取消，请关闭此窗口',
        );
      }
    });
  }

  Future<void> submit(ProfileReport report) async {
    if (!state.canSubmit) return;
    if (!_current()) {
      _expire();
      return;
    }
    final repository = ref.read(profileRepositoryProvider);
    if (repository is! ProfileReportRepository) {
      state = const ProfileReportState(
        status: ProfileReportStatus.expired,
        message: '暂时无法举报，请稍后重试',
      );
      return;
    }
    state = const ProfileReportState(status: ProfileReportStatus.submitting);
    try {
      await (repository as ProfileReportRepository).report(
        id,
        report,
        cancellation: _cancellation,
      );
      if (!_current()) {
        _expire();
        return;
      }
      state = const ProfileReportState(status: ProfileReportStatus.submitted);
    } on AppFailure catch (error) {
      if (!_current()) {
        _expire();
        return;
      }
      final uncertain = switch (error.kind) {
        AppFailureKind.network ||
        AppFailureKind.timeout ||
        AppFailureKind.protocol ||
        AppFailureKind.unknown => true,
        _ => false,
      };
      state = ProfileReportState(
        status: uncertain
            ? ProfileReportStatus.uncertain
            : ProfileReportStatus.failed,
        message: uncertain
            ? '举报结果未确认，请勿重复提交'
            : error.kind == AppFailureKind.playback
            ? '举报未被受理，请稍后重试'
            : error.message,
      );
    } catch (_) {
      if (!_current()) {
        _expire();
        return;
      }
      state = const ProfileReportState(
        status: ProfileReportStatus.uncertain,
        message: '举报结果未确认，请勿重复提交',
      );
    }
  }
}
