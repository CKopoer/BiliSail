import 'dart:io';

import 'package:bilisail/core/logging/playback_diagnostic_log.dart';
import 'package:bili_player/bili_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bili_playback_logs_');
  });
  tearDown(() async => directory.delete(recursive: true));

  PlayerDiagnosticEvent event() => PlayerDiagnosticEvent(
    kind: PlayerDiagnosticKind.nativeError,
    snapshot: const PlaybackSnapshot(
      phase: PlaybackPhase.playing,
      generation: 1,
    ),
    nativeError: NativeErrorSummary.classify(
      'HTTP error 403: https://cdn.example/video?token=SECRET',
    ),
  );

  test('rotation is bounded and stores only sanitized evidence', () async {
    final log = PlaybackDiagnosticLog(directory, maxBytes: 1024);
    for (var i = 0; i < 30; i++) {
      log.record(event());
      await log.flush();
    }
    await log.close();
    final files = await directory
        .list()
        .where((item) => item is File)
        .cast<File>()
        .toList();
    expect(files, hasLength(2));
    for (final file in files) {
      expect(await file.length(), lessThanOrEqualTo(1024));
      final text = await file.readAsString();
      expect(text, contains('403'));
      expect(text, isNot(contains('SECRET')));
      expect(text, isNot(contains('cdn.example')));
    }
  });

  test('flood drops queued events and reports the dropped count', () async {
    final log = PlaybackDiagnosticLog(directory);
    for (var i = 0; i < 200; i++) {
      log.record(event());
    }
    await log.flush();
    log.record(event());
    await log.close();
    final file = await directory
        .list()
        .where((item) => item is File)
        .cast<File>()
        .single;
    final lines = await file.readAsLines();
    expect(lines, hasLength(65));
    expect(lines.last, contains('"droppedEvents":136'));
  });

  test(
    'unwritable diagnostic destination does not propagate to playback',
    () async {
      final blocker = File('${directory.path}/file');
      await blocker.writeAsString('occupied');
      final log = PlaybackDiagnosticLog(Directory('${blocker.path}/logs'));
      log.record(event());
      await log.close();
      expect(await blocker.readAsString(), 'occupied');
    },
  );
}
