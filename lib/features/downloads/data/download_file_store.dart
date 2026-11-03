import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../domain/app_failure.dart';
import '../domain/download_models.dart';

final class DownloadFileStore {
  const DownloadFileStore({this.trustedDocumentsDirectory});

  /// Android supplies its app-private documents directory, never a DB path.
  /// Other platforms retain the strict filesystem-root boundary.
  final Future<String?> Function()? trustedDocumentsDirectory;

  Future<String> createTaskDirectory(
    String rootPath,
    String scope,
    String id,
  ) async {
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) {
      throw const AppFailure(AppFailureKind.storage, '下载任务标识无效');
    }
    final root = await _rootDirectory(rootPath, create: true);
    final scopeName = sha256
        .convert(utf8.encode(scope))
        .toString()
        .substring(0, 16);
    final scopeDirectory = Directory(p.join(root.path, scopeName));
    await _requireDirectory(scopeDirectory.path, create: true);
    final taskDirectory = Directory(p.join(scopeDirectory.path, id));
    await _requireDirectory(taskDirectory.path, create: true);
    await _atomicWrite(
      File(p.join(taskDirectory.path, '.bilisail-task')),
      utf8.encode(jsonEncode({'id': id, 'scope': scope})),
    );
    return taskDirectory.path;
  }

  Future<Directory> ownedDirectory(DownloadTask task) async {
    final parent = p.dirname(p.normalize(task.directory));
    final expectedScope = sha256
        .convert(utf8.encode(task.scope))
        .toString()
        .substring(0, 16);
    if (!p.isAbsolute(task.directory) ||
        p.split(task.directory).contains('..') ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(task.id) ||
        p.basename(p.normalize(task.directory)) != task.id ||
        p.basename(parent) != expectedScope) {
      throw const AppFailure(AppFailureKind.storage, '下载目录无效');
    }
    final root = await _rootDirectory(p.dirname(parent));
    final directory = Directory(p.join(root.path, expectedScope, task.id));
    await _requireDirectoryChain(directory.path, boundary: root.path);
    final marker = File(p.join(directory.path, '.bilisail-task'));
    if (await FileSystemEntity.type(marker.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const AppFailure(AppFailureKind.storage, '下载目录缺少归属标记');
    }
    final Object? decoded = jsonDecode(await marker.readAsString());
    if (decoded is! Map ||
        decoded['id'] != task.id ||
        decoded['scope'] != task.scope) {
      throw const AppFailure(AppFailureKind.storage, '下载目录归属不匹配');
    }
    return directory;
  }

  Future<File> taskFile(DownloadTask task, String name) async {
    if (!const {
      'video.m4s',
      'audio.m4s',
      'video.m4s.part',
      'audio.m4s.part',
      'extras.json',
      'cover.img',
      'manifest.json',
      'media.mp4',
      'media.mp4.part',
      'media.mkv',
      'media.mkv.part',
    }.contains(name)) {
      throw const AppFailure(AppFailureKind.storage, '下载文件名无效');
    }
    final directory = await ownedDirectory(task);
    final file = File(p.join(directory.path, name));
    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const AppFailure(AppFailureKind.storage, '下载文件不能是符号链接');
    }
    return file;
  }

  Future<DownloadTrackProgress> completeTrack(
    DownloadTask task,
    DownloadTrackProgress track,
  ) async {
    final part = await taskFile(task, '${track.fileName}.part');
    final finalFile = await taskFile(task, track.fileName);
    if (!await part.exists() ||
        track.totalBytes == null ||
        await part.length() != track.totalBytes) {
      throw const AppFailure(AppFailureKind.storage, '媒体文件长度不完整');
    }
    if (await finalFile.exists()) await finalFile.delete();
    await part.rename(finalFile.path);
    return track.copyWith(committed: true);
  }

  Future<bool> verifyTrack(
    DownloadTask task,
    DownloadTrackProgress track,
  ) async {
    if (!track.complete ||
        track.fileName !=
            (track.kind == DownloadTrackKind.video
                ? 'video.m4s'
                : 'audio.m4s')) {
      return false;
    }
    final file = await taskFile(task, track.fileName);
    return _canOpen(file);
  }

  Future<void> writeExtras(DownloadTask task, DownloadExtras extras) async {
    final comments = extras.comments
        .take(60000)
        .map(
          (comment) => {
            'id': comment.id,
            'positionMs': comment.position.inMilliseconds,
            'text': comment.text,
            'mode': comment.mode,
            'color': comment.color,
            'fontSize': comment.fontSize,
            'weight': comment.weight,
            'colorful': comment.colorful,
          },
        )
        .toList();
    var remainingCues = 100000;
    final subtitles = extras.subtitles.take(16).map((subtitle) {
      final cues = subtitle.cues
          .take(remainingCues.clamp(0, 20000))
          .map(
            (cue) => {
              'startMs': cue.start.inMilliseconds,
              'endMs': cue.end.inMilliseconds,
              'text': cue.text,
            },
          )
          .toList();
      remainingCues -= cues.length;
      return {'label': subtitle.label, 'cues': cues};
    }).toList();
    final body = utf8.encode(
      jsonEncode({
        'version': 1,
        'comments': comments,
        'subtitles': subtitles,
        'warnings': extras.warnings.take(100).toList(),
      }),
    );
    if (body.length > 32 * 1024 * 1024) {
      throw const AppFailure(AppFailureKind.storage, '离线附属内容超过容量限制');
    }
    await _atomicWrite(await taskFile(task, 'extras.json'), body);
    if (extras.cover case final bytes?) {
      if (bytes.length <= 4 * 1024 * 1024) {
        await _atomicWrite(await taskFile(task, 'cover.img'), bytes);
      }
    }
  }

  Future<void> writeManifest(DownloadTask task) async {
    if (task.tracks.length != 2 ||
        !task.tracks.every((track) => track.complete)) {
      throw const AppFailure(AppFailureKind.storage, '媒体轨道尚未完成');
    }
    if (task.selection.output.isMerged && task.mergedMedia == null) {
      throw const AppFailure(AppFailureKind.storage, '合并文件尚未完成');
    }
    await _atomicWrite(
      await taskFile(task, 'manifest.json'),
      utf8.encode(
        jsonEncode({
          'version': task.selection.output.isMerged ? 2 : 1,
          'id': task.id,
          'scope': task.scope,
          'itemKey': task.item.key,
          'quality': task.selection.quality,
          'codec': task.selection.codec.name,
          if (task.selection.output.isMerged)
            'merged': {
              'fileName': task.mergedMedia?.fileName,
              'bytes': task.mergedMedia?.bytes,
              'sha256': task.mergedMedia?.sha256,
            },
          'tracks': task.tracks
              .map(
                (track) => {
                  'kind': track.kind.name,
                  'identity': track.identity,
                  'fileName': track.fileName,
                  'bytes': track.bytes,
                  'sha256': track.sha256,
                },
              )
              .toList(),
        }),
      ),
    );
  }

  Future<bool> verifyCompleted(DownloadTask task) async {
    await ownedDirectory(task);
    if (task.selection.output.isMerged) {
      if (!await verifyMerged(task)) {
        throw const AppFailure(AppFailureKind.storage, '离线视频文件不存在或无法读取');
      }
      return true;
    }
    for (final kind in DownloadTrackKind.values) {
      final track = task.tracks
          .where((track) => track.kind == kind)
          .firstOrNull;
      if (track == null || !await verifyTrack(task, track)) {
        throw AppFailure(
          AppFailureKind.storage,
          kind == DownloadTrackKind.audio ? '离线音频文件不存在或无法读取' : '离线视频文件不存在或无法读取',
        );
      }
    }
    return true;
  }

  // Check accessibility without reading media bytes or comparing old metadata.
  static Future<bool> _canOpen(File file) async {
    if (!await file.exists()) return false;
    final handle = await file.open();
    await handle.close();
    return true;
  }

  Future<DownloadMergedMedia> completeMerged(DownloadTask task) async {
    final part = await taskFile(task, '${task.selection.output.fileName}.part');
    final length = await part.length();
    if (length <= 0) {
      throw const AppFailure(AppFailureKind.storage, '合并文件为空');
    }
    final handle = await part.open(mode: FileMode.append);
    try {
      await handle.flush();
    } finally {
      await handle.close();
    }
    final output = await taskFile(task, task.selection.output.fileName);
    if (await output.exists()) await output.delete();
    await part.rename(output.path);
    return DownloadMergedMedia(bytes: length, output: task.selection.output);
  }

  Future<bool> verifyMerged(DownloadTask task) async {
    final media = task.mergedMedia;
    if (media == null ||
        !task.selection.output.isMerged ||
        media.output != task.selection.output) {
      return false;
    }
    return _canOpen(await taskFile(task, media.fileName));
  }

  /// Call only after the merged file, manifest and SQLite commit succeeded.
  Future<void> removeSourceTracks(DownloadTask task) async {
    if (!task.selection.output.isMerged) return;
    final sources = [
      await taskFile(task, 'video.m4s'),
      await taskFile(task, 'audio.m4s'),
    ];
    if (!await sources[0].exists() && !await sources[1].exists()) return;
    if (!await verifyCompleted(task)) {
      return;
    }
    for (final file in sources) {
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> deleteOwned(DownloadTask task) async {
    final directory = await ownedDirectory(task);
    // Refuse recursion if a child has been replaced by a symlink.
    await for (final child in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (await FileSystemEntity.type(child.path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const AppFailure(AppFailureKind.storage, '下载目录包含符号链接');
      }
    }
    await directory.delete(recursive: true);
  }

  Future<void> resetMedia(DownloadTask task) async {
    for (final name in const [
      'video.m4s',
      'audio.m4s',
      'video.m4s.part',
      'audio.m4s.part',
      'manifest.json',
      'media.mp4',
      'media.mp4.part',
      'media.mkv',
      'media.mkv.part',
    ]) {
      final file = await taskFile(task, name);
      if (await file.exists()) await file.delete();
    }
  }

  static Future<void> _atomicWrite(File file, List<int> bytes) async {
    final temp = File('${file.path}.tmp');
    if (await FileSystemEntity.type(temp.path, followLinks: false) ==
            FileSystemEntityType.link ||
        await FileSystemEntity.type(file.path, followLinks: false) ==
            FileSystemEntityType.link) {
      throw const AppFailure(AppFailureKind.storage, '下载文件不能是符号链接');
    }
    final handle = await temp.open(mode: FileMode.write);
    try {
      await handle.writeFrom(bytes);
      await handle.flush();
    } finally {
      await handle.close();
    }
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  Future<Directory> _rootDirectory(String path, {bool create = false}) async {
    if (!p.isAbsolute(path) || p.split(path).contains('..')) {
      throw const AppFailure(AppFailureKind.storage, '下载目录无效');
    }
    var root = p.normalize(path);
    final documents = await trustedDocumentsDirectory?.call();
    String? boundary;
    if (documents != null) {
      // Use the platform spelling directly: resolving it can itself require
      // inspecting system ancestors that Android does not allow us to inspect.
      // Only a DIFFERENT legacy spelling needs canonical identity verification.
      if (!p.isAbsolute(documents) ||
          p.basename(root) != 'offline' ||
          p.basename(p.dirname(root)) != 'BiliSail') {
        throw const AppFailure(AppFailureKind.storage, '下载目录不在应用离线目录内');
      }
      boundary = p.normalize(documents);
      final recordedAnchor = p.dirname(p.dirname(root));
      if (!p.equals(recordedAnchor, boundary)) {
        try {
          final expected = await Directory(boundary).resolveSymbolicLinks();
          final recorded = await Directory(recordedAnchor)
              .resolveSymbolicLinks();
          if (!p.equals(recorded, expected)) {
            throw const AppFailure(AppFailureKind.storage, '下载目录不在应用离线目录内');
          }
        } on FileSystemException {
          throw const AppFailure(AppFailureKind.storage, '无法验证旧下载目录归属');
        }
      }
      // This one platform-owned entry may be a system alias; its children may
      // not. Never use a DB path as the traversal boundary or the I/O prefix.
      if (await FileSystemEntity.type(boundary) !=
          FileSystemEntityType.directory) {
        throw const AppFailure(AppFailureKind.storage, '应用下载目录不存在或无法访问');
      }
      root = p.join(boundary, 'BiliSail', 'offline');
    }
    await _requireDirectoryChain(root, boundary: boundary, create: create);
    return Directory(root);
  }

  static Future<void> _requireDirectoryChain(
    String path, {
    String? boundary,
    bool create = false,
  }) async {
    final directories = <String>[];
    var current = p.normalize(path);
    if (boundary != null &&
        !p.equals(current, boundary) &&
        !p.isWithin(boundary, current)) {
      throw const AppFailure(AppFailureKind.storage, '下载目录超出安全边界');
    }
    while (current != boundary) {
      directories.add(current);
      final parent = p.dirname(current);
      if (parent == current) break;
      current = parent;
    }
    // Check each existing parent before creating anything below it.
    for (final directory in directories.reversed) {
      await _requireDirectory(directory, create: create);
    }
  }

  static Future<void> _requireDirectory(
    String path, {
    bool create = false,
  }) async {
    var type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound && create) {
      try {
        await Directory(path).create();
      } on FileSystemException {
        throw const AppFailure(AppFailureKind.storage, '无法访问或创建下载目录');
      }
      type = await FileSystemEntity.type(path, followLinks: false);
    }
    if (type == FileSystemEntityType.directory) return;
    if (type == FileSystemEntityType.link) {
      throw const AppFailure(AppFailureKind.storage, '下载路径不能穿过符号链接');
    }
    if (type == FileSystemEntityType.notFound) {
      // Dart also returns notFound for lookup errors (including access denial).
      throw const AppFailure(AppFailureKind.storage, '下载目录不存在或无法访问');
    }
    throw const AppFailure(AppFailureKind.storage, '下载路径包含非目录节点');
  }
}
