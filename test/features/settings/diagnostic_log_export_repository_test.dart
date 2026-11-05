import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bilisail/core/logging/core_diagnostic_log.dart';
import 'package:bilisail/features/settings/data/diagnostic_log_export_repository.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('export_logs_');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Future<void> write(String name, String text) =>
      File(p.join(directory.path, name)).writeAsString(text);

  Map<String, Object?> manifest(Archive archive) =>
      jsonDecode(utf8.decode(archive.findFile('diagnostics.json')!.content))
          as Map<String, Object?>;

  test('ZIP includes both log channels and rotations, excludes private and unrelated files', () async {
    await write('core-1-2.log', '{"event":"startup"}\n');
    await write('playback-1-2.log', '{"event":"openReady"}\n');
    await write('playback-1-2.previous.log', '{"event":"openStarted"}\n');
    await write('credentials.json', 'SECRET');
    await write('app.sqlite', 'SECRET');
    await write('other.log', 'SECRET');
    final nested = await Directory(p.join(directory.path, 'private')).create();
    await File(p.join(nested.path, 'core-3-4.log')).writeAsString('SECRET');
    final bytes = await buildDiagnosticArchive(directory.path, {
      'appVersion': '1.2.6+7',
    });
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    expect(
      archive.map((f) => f.name),
      unorderedEquals([
        'logs/core-1-2.log',
        'logs/playback-1-2.log',
        'logs/playback-1-2.previous.log',
        'diagnostics.json',
        'README.txt',
      ]),
    );
    expect(manifest(archive)['logFiles'], 3);
    expect(manifest(archive)['appVersion'], '1.2.6+7');
    for (final file in archive) {
      expect(utf8.decode(file.content), isNot(contains('SECRET')));
    }
  });

  test('snapshot flushes pending writes, compresses off-isolate and deduplicates exports', () async {
    final log = CoreDiagnosticLog(directory);
    log.record(CoreDiagnosticEvent.ready);
    Uint8List? saved;
    var saves = 0;
    final repository = DiagnosticLogExportRepository(
      logDirectory: () async => directory,
      flush: log.flush,
      metadata: () async => {'platform': 'test'},
      clock: () => DateTime.utc(2026, 11, 6),
      save: (bytes, name) async {
        saves++;
        saved = bytes;
        expect(name, matches(r'^BiliSail-logs-20261106000000000-\d+\.zip$'));
        return 'Downloads/BiliSail/logs/test.zip';
      },
    );
    final first = repository.export();
    final second = repository.export();
    expect(identical(first, second), isTrue);
    expect(await first, 'Downloads/BiliSail/logs/test.zip');
    expect(saves, 1);
    final archive = ZipDecoder().decodeBytes(saved!, verify: true);
    expect(manifest(archive)['logFiles'], 1);
    expect(manifest(archive)['exportedAt'], '2026-11-06T00:00:00.000Z');
    expect(utf8.decode(archive.files.first.content), contains('ready'));
    await second;
    await log.close();
  });

  test(
    'empty logs still produce a valid archive with explicit counts',
    () async {
      final archive = ZipDecoder().decodeBytes(
        await buildDiagnosticArchive(p.join(directory.path, 'missing'), {}),
        verify: true,
      );
      expect(manifest(archive)['logFiles'], 0);
      expect(archive.findFile('README.txt'), isNotNull);
    },
  );

  test(
    'oversized files, total bytes and file count are bounded and reported',
    () async {
      await write('core-1-1.log', 'a' * 21);
      await write('core-2-1.log', 'b' * 10);
      await write('playback-1-1.log', 'c' * 10);
      final archive = ZipDecoder().decodeBytes(
        await buildDiagnosticArchive(
          directory.path,
          {},
          maxFileBytes: 20,
          maxTotalBytes: 10,
          maxFiles: 1,
        ),
      );
      expect(manifest(archive)['logFiles'], 1);
      expect(manifest(archive)['skippedLogFiles'], 2);
      expect(manifest(archive)['uncompressedLogBytes'], 10);
    },
  );

  test('permission failure is actionable and retry is allowed', () async {
    var calls = 0;
    final repository = DiagnosticLogExportRepository(
      logDirectory: () async => directory,
      flush: () async {},
      metadata: () async => {},
      save: (_, _) async {
        if (++calls == 1) {
          throw PlatformException(code: 'permission_denied', message: 'SECRET');
        }
        return 'saved.zip';
      },
    );
    await expectLater(
      repository.export(),
      throwsA(
        isA<AppFailure>().having(
          (e) => e.message,
          'message',
          isNot(contains('SECRET')),
        ),
      ),
    );
    expect(await repository.export(), 'saved.zip');
  });
}
