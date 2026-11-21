import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/downloads/data/mobile_download_execution.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const system = IosBackgroundTransfer();
  const channel = MobileDownloadExecution.channel;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('an iOS transfer hands off once on the way into the background', (
    tester,
  ) async {
    var handoffs = 0;
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final dispose = system.onHide(() => handoffs++);
    try {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(handoffs, 0);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(system.inBackground, isTrue);
      expect(handoffs, 1);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(system.inBackground, isFalse);
      expect(handoffs, 1);
    } finally {
      dispose();
    }
  });

  test('manual pause cancels the matching system HTTP request', () async {
    final pending = Completer<Map<String, Object?>>();
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'fetch') return pending.future;
      if (call.method == 'cancel') {
        pending.completeError(PlatformException(code: 'network'));
      }
      return null;
    });
    final cancel = RequestCancellation();
    final response = system.fetch(
      Uri.https('example.com', '/media'),
      {},
      cancel,
      null,
    );
    final failure = expectLater(
      response,
      throwsA(
        isA<AppFailure>().having(
          (e) => e.kind,
          'kind',
          AppFailureKind.cancelled,
        ),
      ),
    );
    cancel.cancel();
    await failure;
    expect(calls.map((c) => c.method), ['fetch', 'cancel']);
    expect(calls.last.arguments, (calls.first.arguments as Map)['id']);
  });
}
