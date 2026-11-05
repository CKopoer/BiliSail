import 'dart:convert';
import 'dart:io';

import 'package:bilisail/core/logging/core_diagnostic_log.dart';
import 'package:bilisail/core/logging/diagnostic_log_writer.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bili_api/bili_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('core_logs_');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'core errors retain categories and safe locations, never raw secrets',
    () async {
      final log = CoreDiagnosticLog(directory);
      log.record(
        CoreDiagnosticEvent.frameworkError,
        error: const AppFailure(
          AppFailureKind.network,
          'Cookie: SESSDATA=SECRET https://cdn.test/a?token=SECRET',
        ),
        stack: StackTrace.fromString(
          '#0 request (package:bilisail/core/network/api_requests.dart:14:2)\n'
          '#1 secret (C:/Users/PrivatePerson/token=SECRET.dart:2:4)\n'
          '#2 other (https://example.test/SECRET:1:1)\n',
        ),
      );
      await log.close();
      final file = await directory
          .list()
          .where((e) => e is File)
          .cast<File>()
          .single;
      final text = await file.readAsString();
      final json = jsonDecode(text) as Map<String, Object?>;
      expect(json['failure'], 'network');
      expect(json['stack'], [
        'package:bilisail/core/network/api_requests.dart:14:2',
      ]);
      expect(text, isNot(contains('SECRET')));
      expect(text, isNot(contains('PrivatePerson')));
      expect(text, isNot(contains('Cookie')));
    },
  );

  test('API successes, errors and session transitions are included', () async {
    final log = CoreDiagnosticLog(directory);
    final requests = ApiRequests(diagnostics: log);
    expect(await requests.run((_) async => 42), 42);
    await expectLater(
      requests.run<void>((_) async {
        throw const ApiFailure(ApiFailureCategory.timeout, 'SECRET');
      }),
      throwsA(isA<AppFailure>()),
    );
    requests.advanceSession();
    await log.close();
    final file = await directory
        .list()
        .where((e) => e is File)
        .cast<File>()
        .single;
    final lines = await file.readAsLines();
    expect(lines, hasLength(3));
    expect(lines[0], contains('"outcome":"success"'));
    expect(lines[1], contains('"failure":"timeout"'));
    expect(lines[2], contains('sessionChanged'));
    expect(lines.join(), isNot(contains('SECRET')));
  });

  test(
    'rotation keeps both channels and bounds files across restarts',
    () async {
      for (var i = 0; i < 10; i++) {
        for (final channel in DiagnosticLogChannel.values) {
          final writer = DiagnosticLogWriter(directory, channel, maxBytes: 128);
          await writer.initialize();
          for (var j = 0; j < 10; j++) {
            writer.record({'event': 'bounded', 'value': j});
            await writer.flush();
          }
          await writer.close();
        }
      }
      final files = await directory
          .list()
          .where((e) => e is File)
          .cast<File>()
          .toList();
      for (final channel in DiagnosticLogChannel.values) {
        final own = files.where(
          (f) => p.basename(f.path).startsWith('${channel.name}-'),
        );
        expect(own.length, lessThanOrEqualTo(6));
        expect(own, isNotEmpty);
      }
      for (final file in files) {
        expect(await file.length(), lessThanOrEqualTo(128));
      }
    },
  );
}
