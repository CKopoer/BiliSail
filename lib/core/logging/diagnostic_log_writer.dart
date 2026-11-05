import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

enum DiagnosticLogChannel { core, playback }

/// Bounded local JSONL storage. Callers supply structured, sanitized data.
final class DiagnosticLogWriter {
  DiagnosticLogWriter(
    this.directory,
    this.channel, {
    this.maxBytes = 256 * 1024,
  }) : _name = '${channel.name}-${DateTime.now().microsecondsSinceEpoch}-$pid';

  final Directory directory;
  final DiagnosticLogChannel channel;
  final int maxBytes;
  final String _name;
  Future<void> _writes = Future.value();
  int _pending = 0, _dropped = 0;
  bool _closed = false, _unavailable = false;

  Future<void> initialize() async {
    await directory.create(recursive: true);
    await _prune(keep: 4);
  }

  void record(Map<String, Object?> event) {
    if (_closed || _unavailable) return;
    if (_pending >= 64) {
      _dropped++;
      return;
    }
    final line =
        '${jsonEncode({...event, if (_dropped > 0) 'droppedEvents': _dropped})}\n';
    _dropped = 0;
    if (utf8.encode(line).length > maxBytes) {
      _dropped++;
      return;
    }
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
        // Logging must not break otherwise healthy application operations.
        _unavailable = true;
      } finally {
        _pending--;
      }
    });
  }

  Future<void> _prune({required int keep}) async {
    final files = <(File, DateTime)>[];
    final pattern = RegExp('^${channel.name}-\\d+-\\d+(\\.previous)?\\.log\$');
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && pattern.hasMatch(p.basename(entity.path))) {
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
