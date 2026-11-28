import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'diagnostic_log_writer.dart';

enum LiveRecoveryOutcome {
  roomLive,
  roomOffline,
  statusUnavailable,
  retryLimit,
}

/// Local structured diagnostics only: no URLs, headers, account IDs or raw logs.
final class PlaybackDiagnosticLog {
  PlaybackDiagnosticLog(Directory directory, {int maxBytes = 256 * 1024})
    : _writer = DiagnosticLogWriter(
        directory,
        DiagnosticLogChannel.playback,
        maxBytes: maxBytes,
      );

  final DiagnosticLogWriter _writer;
  Directory get directory => _writer.directory;
  int get maxBytes => _writer.maxBytes;

  static Future<PlaybackDiagnosticLog?> create() async {
    try {
      final support = await getApplicationSupportDirectory();
      final log = PlaybackDiagnosticLog(
        Directory(p.join(support.path, 'logs')),
      );
      await log._writer.initialize();
      return log;
    } on FileSystemException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  void record(PlayerDiagnosticEvent event, {String backend = 'media_kit'}) =>
      _writer.record({
        ...event.toJson(),
        'backend': backend,
      }, lowPriority: event.kind == PlayerDiagnosticKind.nativeLog);

  void recordLiveRecovery(
    int playerId,
    int generation,
    LiveRecoveryOutcome outcome,
  ) {
    _writer.record({
      'time': DateTime.now().toUtc().toIso8601String(),
      'event': 'liveRecovery',
      'playerId': playerId,
      'generation': generation,
      'outcome': outcome.name,
    });
  }

  Future<void> flush() => _writer.flush();
  Future<void> close() => _writer.close();
}
