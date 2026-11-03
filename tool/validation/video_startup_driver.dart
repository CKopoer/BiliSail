import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/common.dart';

Future<void> main() async {
  final driver = await FlutterDriver.connect();
  late Response response;
  try {
    response = Response.fromJson(
      await driver.requestData(null, timeout: const Duration(minutes: 3)),
    );
  } finally {
    await driver.close();
  }
  final output = Directory(
    Platform.environment['STARTUP_OUTPUT'] ??
        'build/validation/android-video-startup',
  );
  await output.create(recursive: true);
  final data = response.data;
  if (data != null) {
    if (data['startup'] case final List<Object?> rows) {
      for (final row in rows) {
        if (row is Map<String, Object?>) {
          if (row.remove('flashPng') case final String png) {
            await File('${output.path}/flash-${row['mode']}.png')
                .writeAsBytes(base64Decode(png));
          }
        }
      }
    }
    await File('${output.path}/results.json').writeAsString(
      const JsonEncoder.withIndent('  ')
          .convert({'allTestsPassed': response.allTestsPassed, ...data}),
    );
  }
  if (!response.allTestsPassed) {
    stderr.writeln(response.formattedFailureDetails);
  }
  exitCode = response.allTestsPassed ? 0 : 1;
}
