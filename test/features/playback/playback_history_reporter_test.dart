import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_history_reporter.dart';
import 'package:bilisail/features/playback/domain/playback_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _History repository;
  late PlaybackHistoryReporter reporter;
  late String scope;
  late int epoch;
  late Duration now;
  late List<AppFailure?> results;
  setUp(() {
    scope = 'user:1';
    epoch = 1;
    now = Duration.zero;
    results = [];
    repository = _History();
    reporter = PlaybackHistoryReporter(
      repository: repository,
      accountScope: () => scope,
      sessionEpoch: () => epoch,
      now: () => now,
      onResult: (_, failure) => results.add(failure),
    );
  });
  tearDown(() async {
    for (final call in repository.calls) {
      if (!call.gate.isCompleted) call.gate.complete();
    }
    reporter.clear();
    await reporter.close();
  });
  void submit(int second, {String cid = '1', bool force = true}) =>
      reporter.submit(
        PlaybackHistoryRecord(
          target: PlaybackHistoryTarget(const VideoId('BV1234567890'), cid),
          position: Duration(seconds: second),
          duration: const Duration(minutes: 2),
          completed: false,
        ),
        scope: scope,
        epoch: epoch,
        generation: 1,
        force: force,
      );

  test(
    'serializes writes and keeps only the newest unsent backward seek',
    () async {
      submit(20);
      await _flush();
      submit(60);
      submit(5);
      expect(repository.calls, hasLength(1));
      repository.calls.first.gate.complete();
      await _flush();
      expect(repository.calls, hasLength(2));
      expect(repository.calls.last.record.position.inSeconds, 5);
      repository.calls.last.gate.complete();
    },
  );
  test('rapid source changes retain at most eight pending parts', () async {
    submit(1);
    await _flush();
    for (var i = 2; i <= 15; i++) {
      submit(i, cid: '$i');
    }
    for (var i = 0; i < 9; i++) {
      repository.calls.last.gate.complete();
      await _flush();
    }
    expect(repository.calls.map((c) => c.record.target.cid), [
      '1',
      '8',
      '9',
      '10',
      '11',
      '12',
      '13',
      '14',
      '15',
    ]);
  });
  test(
    'network failure is consumed and only a new observation can be sent',
    () async {
      submit(1);
      await _flush();
      repository.calls.single.gate.completeError(
        const AppFailure(AppFailureKind.network, 'offline'),
      );
      await _flush();
      submit(1);
      await _flush();
      expect(repository.calls, hasLength(1));
      expect(results.single?.kind, AppFailureKind.network);
      now = const Duration(seconds: 15);
      submit(2, force: false);
      await _flush();
      expect(repository.calls, hasLength(2));
      repository.calls.last.gate.complete();
    },
  );
  test(
    'authentication failure suppresses writes until a new account epoch',
    () async {
      submit(1);
      await _flush();
      repository.calls.single.gate.completeError(
        const AppFailure(AppFailureKind.authentication, 'expired'),
      );
      await _flush();
      now = const Duration(minutes: 1);
      submit(60);
      await _flush();
      expect(repository.calls, hasLength(1));
      epoch++;
      submit(61);
      await _flush();
      expect(repository.calls, hasLength(2));
      repository.calls.last.gate.complete();
    },
  );
  test(
    'account change cancels in-flight and discards queued old-account records',
    () async {
      submit(1);
      await _flush();
      submit(9);
      scope = 'user:2';
      epoch++;
      submit(2);
      await _flush();
      expect(repository.calls.first.cancellation.isCancelled, isTrue);
      repository.calls.first.gate.complete();
      await _flush();
      expect(repository.calls, hasLength(2));
      expect(repository.calls.last.scope, 'user:2');
      expect(repository.calls.last.record.position.inSeconds, 2);
      expect(results, isEmpty);
      repository.calls.last.gate.complete();
    },
  );
  test(
    'rate limiting drops pending writes and cools down for one minute',
    () async {
      submit(1);
      await _flush();
      submit(9);
      repository.calls.single.gate.completeError(
        const AppFailure(AppFailureKind.rateLimited, 'limited'),
      );
      await _flush();
      now = const Duration(seconds: 59);
      submit(59);
      await _flush();
      expect(repository.calls, hasLength(1));
      now = const Duration(seconds: 60);
      submit(60);
      await _flush();
      expect(repository.calls, hasLength(2));
      repository.calls.last.gate.complete();
    },
  );
  test('guest cannot create a report', () async {
    scope = 'guest';
    submit(20);
    await _flush();
    expect(repository.calls, isEmpty);
  });

  test(
    'shutdown has a total budget and cancels without waiting for the network',
    () async {
      submit(1);
      await _flush();
      submit(9);
      await reporter.close(timeout: Duration.zero);
      expect(repository.calls.single.cancellation.isCancelled, isTrue);
      repository.calls.single.gate.complete();
      await _flush();
      expect(repository.calls, hasLength(1));
      expect(results, isEmpty);
    },
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

final class _History implements PlaybackHistoryRepository {
  final calls =
      <
        ({
          PlaybackHistoryRecord record,
          String scope,
          RequestCancellation cancellation,
          Completer<void> gate,
        })
      >[];
  @override
  Future<Duration?> read(
    PlaybackHistoryTarget target, {
    required String scope,
    required RequestCancellation cancellation,
  }) async => null;
  @override
  Future<void> report(
    PlaybackHistoryRecord record, {
    required String scope,
    required RequestCancellation cancellation,
  }) {
    final gate = Completer<void>();
    calls.add((
      record: record,
      scope: scope,
      cancellation: cancellation,
      gate: gate,
    ));
    return gate.future;
  }
}
