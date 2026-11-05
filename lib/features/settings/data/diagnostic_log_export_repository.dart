import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../domain/app_failure.dart';
import '../domain/log_export_repository.dart';

final class DiagnosticLogExportRepository implements LogExportRepository {
  DiagnosticLogExportRepository({
    required this.logDirectory,
    required this.flush,
    required this.metadata,
    required this.save,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Future<Directory> Function() logDirectory;
  final Future<void> Function() flush;
  final Future<Map<String, Object?>> Function() metadata;
  final Future<String> Function(Uint8List bytes, String name) save;
  final DateTime Function() _clock;
  Future<String>? _inFlight;

  @override
  Future<String> export() => _inFlight ??= _export().whenComplete(() {
    _inFlight = null;
  });

  Future<String> _export() async {
    try {
      await flush();
      final directory = await logDirectory();
      final info = await metadata();
      final time = _clock().toUtc();
      final root = directory.path;
      final bytes = await Isolate.run(
        () => buildDiagnosticArchive(root, {
          ...info,
          'exportedAt': time.toIso8601String(),
        }),
      );
      final stamp = time.toIso8601String().replaceAll(RegExp(r'[^0-9]'), '');
      return await save(bytes, 'BiliSail-logs-$stamp-$pid.zip');
    } on AppFailure {
      rethrow;
    } on PlatformException {
      throw const AppFailure(AppFailureKind.storage, '日志导出失败，请检查保存位置或存储权限后重试');
    } on FileSystemException {
      throw const AppFailure(AppFailureKind.storage, '日志导出失败，请检查存储空间和目录权限后重试');
    }
  }
}

/// Runs in a worker isolate; only owned JSONL logs enter the archive.
Future<Uint8List> buildDiagnosticArchive(
  String directory,
  Map<String, Object?> metadata, {
  int maxFileBytes = 512 * 1024,
  int maxTotalBytes = 8 * 1024 * 1024,
  int maxFiles = 32,
}) async {
  final archive = Archive();
  final root = Directory(directory);
  final candidates = <(File, DateTime)>[];
  var skipped = 0, totalBytes = 0, included = 0;
  final pattern = RegExp(r'^(core|playback)-\d+-\d+(\.previous)?\.log$');
  if (await root.exists()) {
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File || !pattern.hasMatch(p.basename(entity.path))) {
        continue;
      }
      try {
        candidates.add((entity, (await entity.stat()).modified));
      } on FileSystemException {
        skipped++;
      }
    }
  }
  candidates.sort((a, b) => b.$2.compareTo(a.$2));
  for (final (file, _) in candidates) {
    if (included >= maxFiles) {
      skipped++;
      continue;
    }
    try {
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        skipped++;
        continue;
      }
      final handle = await file.open();
      late Uint8List bytes;
      try {
        bytes = await handle.read(maxFileBytes + 1);
      } finally {
        await handle.close();
      }
      if (bytes.length > maxFileBytes ||
          totalBytes + bytes.length > maxTotalBytes) {
        skipped++;
        continue;
      }
      archive.add(
        ArchiveFile.bytes(p.posix.join('logs', p.basename(file.path)), bytes),
      );
      totalBytes += bytes.length;
      included++;
    } on FileSystemException {
      skipped++;
    }
  }
  final manifest = utf8.encode(
    const JsonEncoder.withIndent('  ').convert({
      'formatVersion': 1,
      ...metadata,
      'logFiles': included,
      'skippedLogFiles': skipped,
      'uncompressedLogBytes': totalBytes,
      'maxFileBytes': maxFileBytes,
      'maxTotalBytes': maxTotalBytes,
    }),
  );
  archive.add(ArchiveFile.bytes('diagnostics.json', manifest));
  archive.add(
    ArchiveFile.string(
      'README.txt',
      'BiliSail 本地诊断日志\n包含核心运行、框架/异步异常、API 请求结果与耗时、账号切换事件、下载队列摘要和播放器事件。\n'
          '不包含账号标识、Cookie、Token、请求/响应正文、原始异常消息、完整 URL、数据库或离线媒体。\n'
          '日志有容量上限；diagnostics.json 记录导出时间、版本、平台、文件数及跳过数量。\n'
          '无日志或日志被截减时会如实记录；系统 logcat/bugreport 和持续性能采样不在本压缩包中。\n',
    ),
  );
  return ZipEncoder().encodeBytes(archive);
}
