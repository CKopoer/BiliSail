import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/app_update.dart';

final appUpdateRepositoryProvider = Provider<AppUpdateRepository>(
  (ref) =>
      throw UnimplementedError('AppUpdateRepository must be provided by app'),
);
final updateCheckStoreProvider = Provider<UpdateCheckStore>(
  (ref) => throw UnimplementedError('UpdateCheckStore must be provided by app'),
);
final appUpdateLinkOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      throw UnimplementedError('Update link opener must be provided by app'),
);
final updateClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
final installedAppVersionProvider = FutureProvider<AppVersion>(
  (ref) => ref.watch(appUpdateRepositoryProvider).installedVersion(),
);
final appUpdateControllerProvider =
    NotifierProvider<AppUpdateController, AppUpdateState>(
      AppUpdateController.new,
    );

final class AppUpdateState {
  const AppUpdateState({
    this.checking = false,
    this.message,
    this.failure,
    this.pendingRelease,
  });
  final bool checking;
  final String? message;
  final AppFailureKind? failure;
  final AppRelease? pendingRelease;
}

final class AppUpdateController extends Notifier<AppUpdateState> {
  Future<void>? _inFlight;
  RequestCancellation? _cancellation;
  bool _manualRequested = false;
  bool _startupStarted = false;

  @override
  AppUpdateState build() {
    ref.onDispose(() => _cancellation?.cancel());
    return const AppUpdateState();
  }

  Future<void> checkOnStartup() {
    if (_startupStarted) return _inFlight ?? Future<void>.value();
    _startupStarted = true;
    return _check(automatic: true);
  }

  Future<void> checkManually() => _check(automatic: false);

  Future<void> _check({required bool automatic}) {
    if (_inFlight case final active?) {
      if (!automatic) _manualRequested = true;
      return active;
    }
    _manualRequested = !automatic;
    final cancellation = RequestCancellation();
    _cancellation = cancellation;
    state = AppUpdateState(
      checking: true,
      pendingRelease: state.pendingRelease,
    );
    final operation = _run(automatic, cancellation);
    final future = operation.whenComplete(() {
      _inFlight = null;
      _cancellation = null;
    });
    _inFlight = future;
    return future;
  }

  Future<void> _run(bool automatic, RequestCancellation cancellation) async {
    try {
      await (() async {
        if (automatic) {
          final now = ref.read(updateClockProvider)().toLocal();
          final day =
              '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
          final claimed = await ref
              .read(updateCheckStoreProvider)
              .claimStartupDay(day);
          if (!claimed && !_manualRequested) {
            if (ref.mounted) state = const AppUpdateState();
            return;
          }
        }
        if (!ref.mounted || cancellation.isCancelled) return;
        if (ref.read(installedAppVersionProvider).hasError) {
          ref.invalidate(installedAppVersionProvider);
        }
        final installed = await ref.read(installedAppVersionProvider.future);
        if (!ref.mounted || cancellation.isCancelled) return;
        final release = await ref
            .read(appUpdateRepositoryProvider)
            .latestRelease(cancellation);
        if (!ref.mounted || cancellation.isCancelled) return;
        final newer =
            release != null && release.version.compareTo(installed) > 0;
        state = AppUpdateState(
          pendingRelease: newer ? release : null,
          message: !_manualRequested
              ? null
              : newer
              ? '发现新版本 ${release.version.label}'
              : release == null
              ? '暂无已发布版本'
              : '当前已是最新版本（${installed.label}）',
        );
      })().timeout(const Duration(seconds: 20));
    } catch (error) {
      if (!ref.mounted) return;
      final failure = error is AppFailure
          ? error
          : error is TimeoutException
          ? const AppFailure(AppFailureKind.timeout, '检查更新超时，请稍后重试')
          : const AppFailure(AppFailureKind.unknown, '检查更新失败，请稍后重试');
      final cancelled =
          cancellation.isCancelled || failure.kind == AppFailureKind.cancelled;
      cancellation.cancel();
      state = AppUpdateState(
        message: _manualRequested && !cancelled ? failure.message : null,
        failure: _manualRequested && !cancelled ? failure.kind : null,
      );
    }
  }

  AppRelease? takePendingRelease() {
    final release = state.pendingRelease;
    state = AppUpdateState(
      checking: state.checking,
      message: state.message,
      failure: state.failure,
    );
    return release;
  }

  Future<bool> openRepository() => _open(AppUpdateLinks.repository);
  Future<bool> openRelease(AppRelease release) => _open(release.url);

  Future<bool> _open(Uri uri) async {
    try {
      return await ref.read(appUpdateLinkOpenerProvider)(uri);
    } catch (_) {
      return false;
    }
  }
}
