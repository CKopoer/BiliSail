import 'dart:io';

import '../../domain/app_failure.dart';

/// Desktop file browsing is an explicit gesture; mobile files stay app-owned.
final class FileAccessService {
  const FileAccessService();
  bool get canOpenDirectory => Platform.isWindows || Platform.isMacOS;
  bool get canChooseDownloadDirectory => canOpenDirectory;
  bool get pauseDownloadsInBackground => Platform.isAndroid || Platform.isIOS;

  Future<void> openDirectory(String directory) async {
    if (!canOpenDirectory) return;
    try {
      final folder = Directory(directory);
      if (!await folder.exists()) {
        throw const AppFailure(AppFailureKind.storage, '下载目录已不存在');
      }
      final absolute = folder.absolute.path;
      if (Platform.isWindows) {
        await Process.start('explorer.exe', [
          absolute,
        ], mode: ProcessStartMode.detached);
      } else {
        final result = await Process.run('open', [absolute]);
        if (result.exitCode != 0) {
          throw const AppFailure(AppFailureKind.storage, '无法打开下载目录');
        }
      }
    } on ProcessException {
      throw const AppFailure(AppFailureKind.storage, '无法打开下载目录');
    } on FileSystemException {
      throw const AppFailure(AppFailureKind.storage, '无法访问下载目录');
    }
  }
}
