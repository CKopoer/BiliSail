import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Local structured diagnostics only: no URLs, headers, account IDs or raw logs.
final class PlaybackDiagnosticLog {
  PlaybackDiagnosticLog(this.directory, {this.maxBytes = 256 * 1024})
    : _name = 'playback-${DateTime.now().microsecondsSinceEpoch}-$pid';

  final Directory directory;
  final int maxBytes;
  final String _name;
  Future<void> _writes = Future.value();
  int _pending = 0;
  int _dropped = 0;
  bool _closed = false;
  bool _unavailable = false;

  static Future<PlaybackDiagnosticLog?> create() async {
    try {
      final support = await getApplicationSupportDirectory();
      final log = PlaybackDiagnosticLog(
        Directory(p.join(support.path, 'logs')),
      );
      await log.directory.create(recursive: true);
      await log._prune(keep: 4);
      return log;
    } on FileSystemException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  void record(PlayerDiagnosticEvent event) {
    if (_closed || _unavailable) return;
    // Bound both disk and pending work if a decoder floods the event stream.
    if (_pending >= 64) {
      _dropped++;
      return;
    }
    final line =
        '${jsonEncode({...event.toJson(), if (_dropped > 0) 'droppedEvents': _dropped})}\n';
    _dropped = 0;
    _pending++;
    _writes = _writes.then((_) async {
      try {
        if (_unavailable) return;
        await directory.create(recursive: true);
        final file = File(p.join(directory.path, '$_name.log'));
        if (await file.exists() &&
            await file.length() + utf8.encode(line).length > maxBytes) {
          final previous = File(p.join(directory.path, '$_name.previous.log'));
          if (await previous.exists()) await previous.delete();
          await file.rename(previous.path);
          await _prune(keep: 5);
        }
        await file.writeAsString(line, mode: FileMode.append, flush: true);
      } on FileSystemException {
        // Diagnostic storage failure must not stop otherwise healthy playback.
        _unavailable = true;
      } finally {
        _pending--;
      }
    });
  }

  Future<void> _prune({required int keep}) async {
    final files = <(File, DateTime)>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File &&
          RegExp(r'^playback-\d+-\d+(\.previous)?\.log$')
              .hasMatch(p.basename(entity.path))) {
        files.add((entity, (await entity.stat()).modified));
      }
    }
    files.sort((a, b) => b.$2.compareTo(a.$2));
    for (final entry in files.skip(keep)) {
      await entry.$1.delete();
    }
  }

  Future<void> flush() => _writes;

  Future<void> close() async {
    _closed = true;
    await flush();
  }
}
