import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../domain/app_failure.dart';
import 'file_access_service.dart';

final class LogArchiveStorage {
  const LogArchiveStorage({this.android, this.defaultDownloadDirectory});
  final bool? android;
  final Future<String> Function()? defaultDownloadDirectory;
  bool get _android => android ?? Platform.isAndroid;
  static const channel = MethodChannel('bilisail/log_export');

  Future<String> save(Uint8List bytes, String name) async {
    if (!RegExp(r'^BiliSail-logs-\d+-\d+\.zip$').hasMatch(name)) {
      throw const AppFailure(AppFailureKind.storage, '日志文件名无效');
    }
    if (_android) {
      final location = await channel.invokeMethod<String>('save', {
        'bytes': bytes,
        'name': name,
      });
      if (location == null || location.isEmpty) {
        throw const AppFailure(AppFailureKind.storage, '未取得日志保存位置');
      }
      return location;
    }
    final downloads =
        await (defaultDownloadDirectory ??
            const FileAccessService().defaultDownloadDirectory)();
    final directory = Directory(p.join(p.dirname(downloads), 'exported_logs'));
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, name));
    final temporary = File('${file.path}.partial');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
      return file.path;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<Map<String, Object?>> deviceInfo() async {
    if (!_android) return const {};
    try {
      final info = await channel
          .invokeMapMethod<String, Object?>('deviceInfo')
          .timeout(const Duration(seconds: 3));
      return info ?? const {};
    } on PlatformException {
      return const {'deviceInfoUnavailable': true};
    } on MissingPluginException {
      return const {'deviceInfoUnavailable': true};
    } on TimeoutException {
      return const {'deviceInfoUnavailable': true};
    }
  }
}
