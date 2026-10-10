import 'package:bili_api/bili_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/app_failure.dart';
import '../../domain/request_cancellation.dart';

/// Read the current account-session generation without exposing ApiRequests.
final sessionEpochProvider = Provider<int Function()>(
  (ref) =>
      () => 0,
);

/// Process-owned cancellation scope. Every account transition invalidates reads.
class ApiRequests implements ApiSessionProvider {
  int _epoch = 0;
  final Set<ApiCancellation> _active = {};
  final Set<RequestCancellation> _lifetimes = {};

  /// Long-lived transports must be cancelled at the same instant as HTTP reads.
  void Function() trackLifetime(RequestCancellation cancellation) {
    _lifetimes.add(cancellation);
    return () => _lifetimes.remove(cancellation);
  }

  @override
  int get sessionEpoch => _epoch;

  void advanceSession() {
    _epoch++;
    for (final lifetime in _lifetimes.toList()) {
      lifetime.cancel();
    }
    _lifetimes.clear();
    for (final operation in _active.toList()) {
      operation.cancel();
    }
    _active.clear();
  }

  Future<T> run<T>(
    Future<T> Function(ApiRequestContext) operation, {
    RequestCancellation? cancellation,
  }) async {
    final epoch = _epoch;
    final signal = ApiCancellation();
    cancellation?.onCancel(signal.cancel);
    _active.add(signal);
    try {
      if (signal.isCancelled) {
        throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
      }
      final result = await operation(
        ApiRequestContext(
          cancellation: signal,
          sessionEpoch: epoch,
          deadline: DateTime.now().add(const Duration(seconds: 25)),
        ),
      );
      if (signal.isCancelled || epoch != _epoch) {
        throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
      }
      return result;
    } on ApiFailure catch (error) {
      if (signal.isCancelled || epoch != _epoch) {
        throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
      }
      throw mapApiFailure(error);
    } finally {
      _active.remove(signal);
    }
  }
}

AppFailure mapApiFailure(ApiFailure error) => switch (error.category) {
  ApiFailureCategory.cancelled => const AppFailure(
    AppFailureKind.cancelled,
    '请求已取消',
  ),
  ApiFailureCategory.timeout => const AppFailure(
    AppFailureKind.timeout,
    '连接超时，请稍后重试',
  ),
  ApiFailureCategory.network => const AppFailure(
    AppFailureKind.network,
    '暂时无法连接哔哩哔哩，请检查网络后重试',
  ),
  ApiFailureCategory.http =>
    error.httpStatus == 404
        ? const AppFailure(AppFailureKind.notFound, '请求的内容不存在')
        : (error.httpStatus ?? 0) >= 500
        ? const AppFailure(AppFailureKind.network, '服务暂时不可用，请稍后重试')
        : const AppFailure(AppFailureKind.protocol, '服务返回了暂不支持的状态，请稍后重试'),
  ApiFailureCategory.authentication => const AppFailure(
    AppFailureKind.authentication,
    '需要登录，或当前登录已失效',
  ),
  ApiFailureCategory.permission => AppFailure(
    AppFailureKind.permission,
    switch (error.videoAccessKind) {
      ApiVideoAccessKind.chargingExclusive =>
        '这是充电专属视频，当前账号未取得完整播放内容。请登录已开通对应充电档位的账号，或在哔哩哔哩官网开通后重试；试看请前往官网。',
      ApiVideoAccessKind.paid =>
        '这是付费视频，当前账号未取得完整播放内容。请登录已购买的账号，或在哔哩哔哩官网购买后重试；试看请前往官网。',
      _ => '当前账号没有观看权限，或内容存在地区限制',
    },
  ),
  ApiFailureCategory.rateLimited => const AppFailure(
    AppFailureKind.rateLimited,
    '服务暂时限制了请求，请稍后再试',
  ),
  ApiFailureCategory.notFound => const AppFailure(
    AppFailureKind.notFound,
    '视频不存在或已被删除',
  ),
  ApiFailureCategory.protocol => const AppFailure(
    AppFailureKind.protocol,
    '服务返回了暂不支持的数据，请稍后重试',
  ),
  ApiFailureCategory.unavailable => const AppFailure(
    AppFailureKind.playback,
    '当前内容暂不可用，请稍后重试',
  ),
};
