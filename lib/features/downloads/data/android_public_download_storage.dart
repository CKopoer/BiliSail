import 'dart:async';

import 'package:flutter/services.dart';

import '../../../core/logging/core_diagnostic_log.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/download_models.dart';
import '../domain/public_download_storage.dart';

final class AndroidPublicDownloadStorage implements PublicDownloadStorage {
  const AndroidPublicDownloadStorage();
  static const _channel = MethodChannel('dev.bilisail/download_storage');

  void startMediaScanLogging(CoreDiagnosticLog diagnostics) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'mediaScanFinished') throw MissingPluginException();
      if (call.arguments
          case {'format': final String format, 'result': final String result}
          when (format == 'mp4' || format == 'mkv') &&
              (result == 'scanned' ||
                  result == 'noUri' ||
                  result == 'requestFailed' ||
                  result == 'timedOut')) {
        diagnostics.record(
          CoreDiagnosticEvent.downloadMediaScan,
          outcome: result == 'scanned'
              ? CoreDiagnosticOutcome.success
              : CoreDiagnosticOutcome.failed,
          mediaFormat: format,
          mediaScanResult: result,
        );
      }
    });
  }

  void stopMediaScanLogging() => _channel.setMethodCallHandler(null);

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw AppFailure(
        e.code == 'permission'
            ? AppFailureKind.permission
            : AppFailureKind.storage,
        e.message ?? '公共下载位置不可用，请重新授权或连接存储设备',
      );
    }
  }

  Map<String, Object?> _task(DownloadTask task) => {
    'id': task.id,
    'scope': task.scope,
    'destination': task.publicDestination,
    'uris': task.publicFiles,
  };

  @override
  Future<bool> hasDestination() async =>
      await _call<bool>('hasDestination') ?? false;

  @override
  Future<bool> requestDirectoryAccess() async =>
      await _call<bool>('requestAccess') ?? false;

  @override
  Future<DownloadFolderListing> listDirectories(String? directory) async {
    final value = await _call<Map<Object?, Object?>>('listDirectories', {
      'directory': directory,
    });
    DownloadFolder folder(Object? item) {
      if (item case {'path': final String path, 'name': final String name}) {
        return DownloadFolder(path: path, name: name);
      }
      throw const AppFailure(AppFailureKind.storage, '文件夹信息无效');
    }

    if (value case {'folders': final List<Object?> folders}) {
      return DownloadFolderListing(
        directory: value['directory'] == null
            ? null
            : folder(value['directory']),
        parent: value['parent'] as String?,
        folders: folders.map(folder).toList(),
        truncated: value['truncated'] == true,
      );
    }
    throw const AppFailure(AppFailureKind.storage, '无法读取文件夹');
  }

  @override
  Future<void> chooseDestination(String directory) =>
      _call<void>('choose', {'directory': directory});

  @override
  Future<String> destination() async {
    final value = await _call<String>('destination');
    if (value == null) {
      throw const AppFailure(AppFailureKind.permission, '请先选择公共下载保存位置');
    }
    return value;
  }

  @override
  Future<Map<String, String>> publish(
    DownloadTask task,
    Map<String, String> files,
    RequestCancellation cancellation,
  ) async {
    var finished = false;
    cancellation.onCancel(() {
      if (!finished) {
        unawaited(_call<void>('cancel', _task(task)).catchError((Object _) {}));
      }
    });
    try {
      if (cancellation.isCancelled) {
        throw const AppFailure(AppFailureKind.cancelled, '保存已取消');
      }
      final result = await _call<Map<Object?, Object?>>('publish', {
        ..._task(task),
        'files': files,
      });
      return result!.cast<String, String>();
    } finally {
      finished = true;
    }
  }

  @override
  Future<void> verify(DownloadTask task) => _call<void>('verify', _task(task));
  @override
  Future<void> delete(DownloadTask task) => _call<void>('delete', _task(task));
}
