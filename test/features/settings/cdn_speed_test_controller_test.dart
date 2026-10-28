import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/media_cdn.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/settings/application/cdn_speed_test_controller.dart';
import 'package:bilisail/features/settings/domain/cdn_speed_test_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _Repository repository;
  late ProviderContainer container;
  late CdnSpeedTestController controller;
  setUp(() {
    repository = _Repository();
    container = ProviderContainer(
      overrides: [cdnSpeedTestRepositoryProvider.overrideWithValue(repository)],
    );
    container.listen(cdnSpeedTestControllerProvider, (_, _) {});
    controller = container.read(cdnSpeedTestControllerProvider.notifier);
  });
  tearDown(() => container.dispose());

  test(
    'serial probes share identical addresses and isolate unavailable nodes',
    () async {
      repository.failHost = MediaCdnPreference.ali.host;
      await controller.start();
      final state = container.read(cdnSpeedTestControllerProvider);
      expect(state.running, isFalse);
      expect(state.message, '测速完成');
      expect(state.results, hasLength(MediaCdnPreference.values.length));
      expect(state.results[MediaCdnPreference.ali]?.message, '连接失败');
      expect(
        state.results[MediaCdnPreference.cos]?.measurement?.mebibytesPerSecond,
        2,
      );
      expect(repository.urls.toSet(), hasLength(repository.urls.length));
      expect(repository.maxActive, 1);
    },
  );

  test(
    'stop prevents a late sample from starting probes; retry starts fresh',
    () async {
      repository.pendingSample = Completer<CdnSpeedSample>();
      final first = controller.start();
      final cancelled = repository.cancellations.single;
      controller.stop();
      expect(cancelled.isCancelled, isTrue);
      repository.pendingSample?.complete(repository.sample);
      await first;
      expect(repository.urls, isEmpty);
      expect(container.read(cdnSpeedTestControllerProvider).message, '测速已停止');
      repository.pendingSample = null;
      await controller.start();
      expect(container.read(cdnSpeedTestControllerProvider).message, '测速完成');
    },
  );

  test(
    'restart and disposal reject delayed results from old generations',
    () async {
      repository.pendingMeasurement = Completer<CdnSpeedMeasurement>();
      final first = controller.start();
      await Future<void>.delayed(Duration.zero);
      final oldSignal = repository.cancellations.first;
      final pending = repository.pendingMeasurement;
      repository.pendingMeasurement = null;
      await controller.start();
      expect(oldSignal.isCancelled, isTrue);
      pending?.complete(
        const CdnSpeedMeasurement(
          bytes: 1,
          elapsed: Duration(days: 1),
          host: 'old',
        ),
      );
      await first;
      expect(
        container
            .read(cdnSpeedTestControllerProvider)
            .results
            .values
            .every((r) => r.measurement?.host != 'old'),
        isTrue,
      );

      repository.pendingSample = Completer<CdnSpeedSample>();
      final finalRun = controller.start();
      final finalSignal = repository.cancellations.last;
      container.dispose();
      expect(finalSignal.isCancelled, isTrue);
      repository.pendingSample?.complete(repository.sample);
      await finalRun;
      // This container has already been disposed.
      container = ProviderContainer();
    },
  );

  test(
    'sample failure and account changes leave no rows stuck in progress',
    () async {
      repository.sampleFailure = const AppFailure(
        AppFailureKind.network,
        '无法获取测速视频',
      );
      await controller.start();
      var state = container.read(cdnSpeedTestControllerProvider);
      expect(state.message, '无法获取测速视频');
      expect(state.results.values.every((r) => r.message == '未测速'), isTrue);
      repository.sampleFailure = null;
      repository.measurementFailure = const AppFailure(
        AppFailureKind.cancelled,
        '取消',
      );
      await controller.start();
      state = container.read(cdnSpeedTestControllerProvider);
      expect(state.message, '账号已变化，请重新测速');
      expect(state.running, isFalse);
      expect(state.results.values.every((r) => r.message == '未测速'), isTrue);
    },
  );
}

final class _Repository implements CdnSpeedTestRepository {
  final sample = CdnSpeedSample([
    Uri.parse(
      'https://upos-sz-mirrorhw.bilivideo.com/upgcxcode/v.m4s?key=fixture',
    ),
  ], sessionEpoch: 7);
  final cancellations = <RequestCancellation>[];
  final urls = <Uri>[];
  Completer<CdnSpeedSample>? pendingSample;
  Completer<CdnSpeedMeasurement>? pendingMeasurement;
  AppFailure? sampleFailure, measurementFailure;
  String? failHost;
  int active = 0, maxActive = 0;

  @override
  Future<CdnSpeedSample> loadSample({
    required RequestCancellation cancellation,
  }) async {
    cancellations.add(cancellation);
    if (sampleFailure case final failure?) throw failure;
    return pendingSample?.future ?? sample;
  }

  @override
  Future<CdnSpeedMeasurement> measure(
    Uri url, {
    required int sessionEpoch,
    required RequestCancellation cancellation,
  }) async {
    expect(sessionEpoch, 7);
    urls.add(url);
    active++;
    if (active > maxActive) maxActive = active;
    try {
      if (measurementFailure case final failure?) throw failure;
      if (url.host == failHost) {
        throw const AppFailure(AppFailureKind.network, '连接失败');
      }
      return await (pendingMeasurement?.future ??
          Future.value(
            CdnSpeedMeasurement(
              bytes: 1024 * 1024,
              elapsed: const Duration(milliseconds: 500),
              host: url.host,
            ),
          ));
    } finally {
      active--;
    }
  }
}
