import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> sendAppLifecycleState(
  WidgetTester tester,
  AppLifecycleState state,
) async {
  final channel = SystemChannels.lifecycle;
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    channel.name,
    channel.codec.encodeMessage(state.toString()),
    null,
  );
}
