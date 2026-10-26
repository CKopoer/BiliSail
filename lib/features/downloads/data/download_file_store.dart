import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

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
    final digest = await _sha256File(part.path);
    if (await finalFile.exists()) await finalFile.delete();
    await part.rename(finalFile.path);
    return track.copyWith(sha256: digest);
  }

  Future<bool> verifyTrack(
    DownloadTask task,
    DownloadTrackProgress track, {
    bool verifyHash = true,
  }) async {
    if (!track.complete ||
        track.fileName !=
            (track.kind == DownloadTrackKind.video
                ? 'video.m4s'
                : 'audio.m4s')) {
      return false;
    }
    final file = await taskFile(task, track.fileName);
    if (!await file.exists() || await file.length() != track.totalBytes) {
      return false;
    }
    return !verifyHash || await _sha256File(file.path) == track.sha256;
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

  Future<bool> verifyCompleted(
    DownloadTask task, {
    bool verifyHashes = true,
  }) async {
    if (task.tracks.length != 2) return false;
    final manifest = await taskFile(task, 'manifest.json');
    if (!await manifest.exists()) return false;
    try {
      final Object? decoded = jsonDecode(await manifest.readAsString());
      if (decoded is! Map ||
          decoded['version'] != (task.selection.output.isMerged ? 2 : 1) ||
          decoded['id'] != task.id ||
          decoded['scope'] != task.scope ||
          decoded['itemKey'] != task.item.key ||
          decoded['quality'] != task.selection.quality ||
          decoded['codec'] != task.selection.codec.name) {
        return false;
      }
      final listed = decoded['tracks'];
      if (listed is! List || listed.length != 2) return false;
      for (final track in task.tracks) {
        if (!listed.any(
          (entry) =>
              entry is Map &&
              entry['fileName'] == track.fileName &&
              entry['sha256'] == track.sha256 &&
              entry['bytes'] == track.bytes,
        )) {
          return false;
        }
        if (task.selection.output == DownloadOutput.separate &&
            !await verifyTrack(task, track, verifyHash: verifyHashes)) {
          return false;
        }
      }
      if (task.selection.output.isMerged) {
        final output = task.mergedMedia;
        final merged = decoded['merged'];
        if (output == null ||
            merged is! Map ||
            merged['fileName'] != output.fileName ||
            merged['bytes'] != output.bytes ||
            merged['sha256'] != output.sha256 ||
            !await verifyMerged(task, verifyHash: verifyHashes)) {
          return false;
        }
      }
      return true;
    } on FormatException {
      return false;
    }
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
    final digest = await _sha256File(part.path);
    final output = await taskFile(task, task.selection.output.fileName);
    if (await output.exists()) await output.delete();
    await part.rename(output.path);
    return DownloadMergedMedia(
      bytes: length,
      sha256: digest,
      output: task.selection.output,
    );
  }

  Future<bool> verifyMerged(DownloadTask task, {bool verifyHash = true}) async {
    final media = task.mergedMedia;
    if (media == null ||
        !task.selection.output.isMerged ||
        media.output != task.selection.output ||
        media.bytes <= 0 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(media.sha256)) {
      return false;
    }
    final file = await taskFile(task, media.fileName);
    if (!await file.exists() || await file.length() != media.bytes) {
      return false;
    }
    return !verifyHash || await _sha256File(file.path) == media.sha256;
  }

  /// Call only after the merged file, manifest and SQLite commit succeeded.
  Future<void> removeSourceTracks(
    DownloadTask task, {
    bool verifyHashes = true,
  }) async {
    if (!task.selection.output.isMerged) return;
    final sources = [
      await taskFile(task, 'video.m4s'),
      await taskFile(task, 'audio.m4s'),
    ];
    if (!await sources[0].exists() && !await sources[1].exists()) return;
    if (!await verifyCompleted(task, verifyHashes: verifyHashes)) {
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

  static Future<String> _sha256File(String path) => Isolate.run(
    () async => (await sha256.bind(File(path).openRead()).first).toString(),
  );

  Future<Directory> _rootDirectory(String path, {bool create = false}) async {
    if (!p.isAbsolute(path) || p.split(path).contains('..')) {
      throw const AppFailure(AppFailureKind.storage, '下载目录无效');
    }
    var root = p.normalize(path);
    final documents = await trustedDocumentsDirectory?.call();
    String? boundary;
    if (documents != null) {
      // Only the established Android layout is accepted. Resolve the platform
      // anchor (and an old spelling of that SAME anchor), never its children.
      // This supports /data/user/... aliases without trusting arbitrary DB roots.
      if (!p.isAbsolute(documents) ||
          p.basename(root) != 'offline' ||
          p.basename(p.dirname(root)) != 'BiliSail') {
        throw const AppFailure(AppFailureKind.storage, '下载目录不在应用离线目录内');
      }
      try {
        boundary = await Directory(documents).resolveSymbolicLinks();
        final recordedAnchor = await Directory(
          p.dirname(p.dirname(root)),
        ).resolveSymbolicLinks();
        if (!p.equals(recordedAnchor, boundary)) {
          throw const AppFailure(AppFailureKind.storage, '下载目录不在应用离线目录内');
        }
      } on FileSystemException {
        throw const AppFailure(AppFailureKind.storage, '无法解析应用下载目录');
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
    while (true) {
      directories.add(current);
      final parent = p.dirname(current);
      if (current == boundary || parent == current) break;
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
