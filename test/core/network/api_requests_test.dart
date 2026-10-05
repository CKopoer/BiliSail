import 'dart:async';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'session advance cancels an old response even if transport errors',
    () async {
      final requests = ApiRequests();
      final pending = Completer<void>();
      final started = Completer<void>();
      final operation = requests.run((context) async {
        started.complete();
        await pending.future;
        throw const ApiFailure(ApiFailureCategory.network, 'fake');
      });
      await started.future;
      requests.advanceSession();
      pending.complete();
      await expectLater(
        operation,
        throwsA(
          isA<AppFailure>().having(
            (error) => error.kind,
            'kind',
            AppFailureKind.cancelled,
          ),
        ),
      );
    },
  );

  test('pre-cancelled request does not start operation', () async {
    final requests = ApiRequests();
    final cancellation = RequestCancellation()..cancel();
    var called = false;
    await expectLater(
      requests.run((_) async {
        called = true;
        return 1;
      }, cancellation: cancellation),
      throwsA(
        isA<AppFailure>().having(
          (error) => error.kind,
          'kind',
          AppFailureKind.cancelled,
        ),
      ),
    );
    expect(called, isFalse);
  });
}
