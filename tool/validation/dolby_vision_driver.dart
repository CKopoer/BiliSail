import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/common.dart';

Future<void> main() async {
  final driver = await FlutterDriver.connect();
  late Response response;
  try {
    response = Response.fromJson(
      await driver.requestData(null, timeout: const Duration(minutes: 5)),
    );
  } finally {
    await driver.close();
  }
  final output = Directory('build/validation/android-dolby-vision');
  final data = response.data;
  if (data != null) {
    final rows = data['dovi'];
    if (rows is List<Object?>) {
      for (final row in rows) {
        if (row is Map<String, Object?>) {
          final png = row.remove('texturePng');
          if (png is String && row['mode'] is String) {
            await File('${output.path}/texture-${row['mode']}.png')
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
