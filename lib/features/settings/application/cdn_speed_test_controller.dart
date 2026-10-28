import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/media_cdn.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/cdn_speed_test_repository.dart';

final cdnSpeedTestRepositoryProvider = Provider<CdnSpeedTestRepository>(
  (ref) => throw UnimplementedError('CDN speed test must be provided by app'),
);

final cdnSpeedTestControllerProvider =
    NotifierProvider.autoDispose<CdnSpeedTestController, CdnSpeedTestState>(
      CdnSpeedTestController.new,
    );

final class CdnSpeedResult {
  const CdnSpeedResult({this.measurement, this.message = '等待测速'});
  final CdnSpeedMeasurement? measurement;
  final String message;
}

final class CdnSpeedTestState {
  const CdnSpeedTestState({
    this.running = false,
    this.results = const {},
    this.message,
  });
  final bool running;
  final Map<MediaCdnPreference, CdnSpeedResult> results;
  final String? message;
}

final class CdnSpeedTestController extends Notifier<CdnSpeedTestState> {
  RequestCancellation? _cancellation;

  @override
  CdnSpeedTestState build() {
    ref.onDispose(cancel);
    return const CdnSpeedTestState();
  }

  void cancel() {
    _cancellation?.cancel();
    _cancellation = null;
  }

  void stop() {
    cancel();
    state = CdnSpeedTestState(
      results: Map.unmodifiable({
        for (final entry in state.results.entries)
          entry.key:
              entry.value.measurement == null &&
                  ['等待测速', '正在测速…'].contains(entry.value.message)
              ? const CdnSpeedResult(message: '已停止')
              : entry.value,
      }),
      message: '测速已停止',
    );
  }

  Future<void> start() async {
    _cancellation?.cancel();
    final cancellation = RequestCancellation();
    _cancellation = cancellation;
    bool current() =>
        ref.mounted &&
        identical(_cancellation, cancellation) &&
        !cancellation.isCancelled;
    final results = {
      for (final choice in MediaCdnPreference.values)
        choice: const CdnSpeedResult(),
    };
    state = CdnSpeedTestState(
      running: true,
      results: Map.unmodifiable(results),
      message: '正在获取测速视频…',
    );
    try {
      final repository = ref.read(cdnSpeedTestRepositoryProvider);
      final sample = await repository.loadSample(cancellation: cancellation);
      if (!current()) return;
      final measured = <Uri, CdnSpeedResult>{};
      for (final choice in MediaCdnPreference.values) {
        if (!current()) return;
        final target = mediaCdnProbeUrl(sample.urls, choice);
        if (target == null) {
          results[choice] = const CdnSpeedResult(message: '此视频不支持该线路');
        } else if (measured[target] case final cached?) {
          results[choice] = cached;
        } else {
          results[choice] = const CdnSpeedResult(message: '正在测速…');
          state = CdnSpeedTestState(
            running: true,
            results: Map.unmodifiable(results),
          );
          CdnSpeedResult result;
          try {
            result = CdnSpeedResult(
              measurement: await repository.measure(
                target,
                sessionEpoch: sample.sessionEpoch,
                cancellation: cancellation,
              ),
            );
          } on AppFailure catch (failure) {
            if (failure.kind == AppFailureKind.cancelled) rethrow;
            result = CdnSpeedResult(message: failure.message);
          }
          if (!current()) return;
          results[choice] = result;
          measured[target] = result;
        }
        state = CdnSpeedTestState(
          running: true,
          results: Map.unmodifiable(results),
        );
      }
      if (current()) {
        state = CdnSpeedTestState(
          results: Map.unmodifiable(results),
          message: '测速完成',
        );
      }
    } on AppFailure catch (failure) {
      if (current()) {
        state = CdnSpeedTestState(
          results: _settledResults(results),
          message: failure.kind == AppFailureKind.cancelled
              ? '账号已变化，请重新测速'
              : failure.message,
        );
      }
    } catch (_) {
      if (current()) {
        state = CdnSpeedTestState(
          results: _settledResults(results),
          message: '测速失败，请重试',
        );
      }
    }
  }

  Map<MediaCdnPreference, CdnSpeedResult> _settledResults(
    Map<MediaCdnPreference, CdnSpeedResult> results,
  ) => Map.unmodifiable({
    for (final entry in results.entries)
      entry.key:
          entry.value.measurement == null &&
              ['等待测速', '正在测速…'].contains(entry.value.message)
          ? const CdnSpeedResult(message: '未测速')
          : entry.value,
  });
}
