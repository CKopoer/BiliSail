import 'dart:convert';
import 'dart:io';

import 'package:bilisail/core/logging/core_diagnostic_log.dart';
import 'package:bilisail/features/downloads/data/android_public_download_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test('media scan results reach the core log with safe fields only', () async {
    final directory = await Directory.systemTemp.createTemp('scan_logs_');
    addTearDown(() => directory.delete(recursive: true));
    final log = CoreDiagnosticLog(directory);
    addTearDown(log.close);
    const storage = AndroidPublicDownloadStorage();
    storage.startMediaScanLogging(log);
    addTearDown(storage.stopMediaScanLogging);

    Future<void> report(String format, String result) =>
        binding.defaultBinaryMessenger.handlePlatformMessage(
          'dev.bilisail/download_storage',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('mediaScanFinished', {
              'format': format,
              'result': result,
              'path': '/private/folder/video.mp4',
              'uri': 'content://media/external/video/media/123',
            }),
          ),
          null,
        );

    await report('mp4', 'scanned');
    await report('mkv', 'noUri');
    await report('mp4', 'requestFailed');
    await report('mkv', 'timedOut');
    await report('/private/folder/video.mp4', 'scanned');
    await report('mp4', 'content://media/external/video/media/123');
    await log.flush();

    final file = await directory
        .list()
        .where((entry) => entry is File)
        .cast<File>()
        .single;
    final lines = await file.readAsLines();
    final events = lines.map(
      (line) => jsonDecode(line) as Map<String, Object?>,
    );
    expect(
      events.map(
        (e) =>
            (e['event'], e['mediaFormat'], e['mediaScanResult'], e['outcome']),
      ),
      [
        ('downloadMediaScan', 'mp4', 'scanned', 'success'),
        ('downloadMediaScan', 'mkv', 'noUri', 'failed'),
        ('downloadMediaScan', 'mp4', 'requestFailed', 'failed'),
        ('downloadMediaScan', 'mkv', 'timedOut', 'failed'),
      ],
    );
    expect(lines.join(), isNot(contains('/private/folder')));
    expect(lines.join(), isNot(contains('content://')));
  });
}
