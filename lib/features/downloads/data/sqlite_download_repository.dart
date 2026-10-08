// The public constructor keeps the `defaultDirectory` named parameter.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../../core/storage/app_database.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../../../domain/video_codec.dart';
import '../domain/download_repository.dart';
import '../domain/download_muxer.dart';
import 'download_file_store.dart';
import 'http_download_transfer.dart';

/// Process-owned download queue; closing a UI listener never stops a transfer.
final class SqliteDownloadRepository implements DownloadRepository {
  SqliteDownloadRepository(
    this.db,
    this.sources, {
    required Future<String> Function() defaultDirectory,
    HttpDownloadTransfer? transfer,
    DownloadFileStore? files,
    DownloadMuxer? muxer,
    DateTime Function()? clock,
  }) : _defaultDirectory = defaultDirectory,
       _transfer = transfer ?? const HttpDownloadTransfer(),
       _files = files ?? const DownloadFileStore(),
       _muxer = muxer ?? const _UnavailableDownloadMuxer(),
       _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final DownloadSourceRepository sources;
  final Future<String> Function() _defaultDirectory;
  final HttpDownloadTransfer _transfer;
  final DownloadFileStore _files;
  final DownloadMuxer _muxer;
  final DateTime Function() _clock;
  final _changes = StreamController<DownloadQueueState>.broadcast();
  final Map<String, DownloadTask> _tasks = {};
  final Map<String, _Run> _runs = {};
  final Set<String> _removing = {};
  final Set<String> _backgroundFailed = {};
  Future<void> _writes = Future.value();
  Future<void> _enqueueSerial = Future.value();
  Future<void> _sessionSerial = Future.value();
  Future<void>? _closingFuture;
  Future<void>? _initializing;
  DownloadPreferences _preferences = const DownloadPreferences();
  String _scope = '';
  int _epoch = -1;
  int _sessionPending = 0;
  AppFailure? _failure;
  bool _storageFault = false;
  bool _initialized = false,
      _closing = false,
      _closed = false,
      _suspendPump = false;

  @override
  DownloadQueueState get current => DownloadQueueState(
    tasks: _visible(),
    preferences: _preferences,
    initialized: _initialized,
    failure: _failure,
    canMerge: _muxer.available,
  );

  @override
  Stream<DownloadQueueState> get changes => _changes.stream;

  List<DownloadTask> _visible() =>
      _tasks.values.where((task) => task.scope == _scope).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  void _emit() {
    if (!_closed) _changes.add(current);
  }

  @override
  Future<void> initialize() => _initializing ??= _load();

  Future<void> _load() async {
    _scope = sources.accountScope;
    _epoch = sources.sessionEpoch;
    final loadingScope = _scope;
    final loadingEpoch = _epoch;
    final setting = await db.readSetting('downloads.v1');
    if (setting != null) {
      try {
        final decoded = jsonDecode(setting);
        if (decoded is Map) {
          final directory = decoded['directory'];
          final concurrency = decoded['concurrency'];
          _preferences = DownloadPreferences(
            directory: directory is String && p.isAbsolute(directory)
                ? p.normalize(directory)
                : null,
            concurrency: concurrency is int ? concurrency.clamp(1, 3) : 2,
          );
        }
      } on FormatException {
        // A damaged preference does not make the download index inaccessible.
      }
    }
    final rows = await db
        .customSelect(
          'SELECT record_json FROM download_tasks WHERE scope = ?',
          variables: [Variable<String>(loadingScope)],
        )
        .get();
    for (final row in rows) {
      if (loadingScope != sources.accountScope ||
          loadingEpoch != sources.sessionEpoch) {
        return;
      }
      try {
        final task = _decodeTask(row.read<String>('record_json'));
        if (task.scope != _scope) continue;
        var restored = task;
        if (task.active) {
          restored = task.copyWith(
            status: DownloadStatus.paused,
            updatedAt: _clock(),
          );
        }
        restored = await _reconcile(restored);
        if (loadingScope != sources.accountScope ||
            loadingEpoch != sources.sessionEpoch) {
          return;
        }
        _tasks[restored.id] = restored;
        if (!identical(restored, task)) await _save(restored);
        if (restored.status == DownloadStatus.completed) {
          try {
            await _files.removeSourceTracks(restored);
          } on FileSystemException {
            /* Retaining committed originals is safe. */
          }
        }
      } on FormatException {
        // A corrupt record is left on disk for diagnostics, without exposing it.
      }
    }
    if (loadingScope != sources.accountScope ||
        loadingEpoch != sources.sessionEpoch) {
      return;
    }
    _initialized = true;
    _failure = null;
    _storageFault = false;
    _emit();
  }

  Future<DownloadTask> _reconcile(
    DownloadTask task, {
    bool verifyHashes = false,
  }) async {
    try {
      if (task.selection.output == DownloadOutput.mp4 &&
          task.mergedMedia != null) {
        if (await _files.verifyMerged(task, verifyHash: verifyHashes)) {
          if (await _files.verifyCompleted(task, verifyHashes: verifyHashes)) {
            return task.copyWith(
              status: DownloadStatus.completed,
              clearFailure: true,
              updatedAt: _clock(),
            );
          }
          // Output metadata was committed before the manifest/complete stage.
          // It is reusable without downloading the two original tracks again.
          if (task.status != DownloadStatus.completed) return task;
        } else {
          task = task.copyWith(clearMergedMedia: true);
        }
      }
      if (task.status == DownloadStatus.completed) {
        if (!await _files.verifyCompleted(task, verifyHashes: verifyHashes)) {
          return task.copyWith(
            status: DownloadStatus.failed,
            failure: const AppFailure(AppFailureKind.storage, '离线文件缺失或校验失败'),
            updatedAt: _clock(),
          );
        }
      } else if (task.tracks.isNotEmpty) {
        final tracks = <DownloadTrackProgress>[];
        for (final track in task.tracks) {
          if (track.complete) {
            tracks.add(
              await _files.verifyTrack(task, track, verifyHash: verifyHashes)
                  ? track
                  : _resetTrack(track),
            );
            continue;
          }
          final file = await _files.taskFile(task, '${track.fileName}.part');
          final length = await file.exists() ? await file.length() : 0;
          tracks.add(_withBytes(track, length));
        }
        return task.copyWith(tracks: tracks);
      }
    } catch (_) {
      return task.copyWith(
        status: DownloadStatus.failed,
        failure: const AppFailure(AppFailureKind.storage, '离线目录不可用'),
        updatedAt: _clock(),
      );
    }
    return task;
  }

  @override
  Future<void> enqueue(List<DownloadItem> items, DownloadSelection selection) {
    if (_closing || _closed) {
      return Future.error(
        const AppFailure(AppFailureKind.cancelled, '下载服务已关闭'),
      );
    }
    final scope = sources.accountScope;
    final epoch = sources.sessionEpoch;
    final batch = List<DownloadItem>.of(items);
    final operation = _enqueueSerial.then(
      (_) => _enqueueBatch(batch, selection, scope, epoch),
    );
    _enqueueSerial = operation.then(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  bool _batchCurrent(String scope, int epoch) =>
      !_closing &&
      !_closed &&
      _sessionPending == 0 &&
      scope == _scope &&
      epoch == _epoch &&
      scope == sources.accountScope &&
      epoch == sources.sessionEpoch;

  Future<void> _enqueueBatch(
    List<DownloadItem> items,
    DownloadSelection selection,
    String scope,
    int epoch,
  ) async {
    await initialize();
    if (!_batchCurrent(scope, epoch) || items.isEmpty) return;
    if (selection.quality <= 0) {
      throw ArgumentError.value(selection.quality, 'quality');
    }
    if (selection.output == DownloadOutput.mp4 && !_muxer.available) {
      throw const AppFailure(AppFailureKind.storage, '当前无法合并音视频，请选择分轨保存');
    }
    final unique = <String, DownloadItem>{};
    for (final item in items) {
      if (!item.isValid) throw ArgumentError.value(item.key, 'item');
      unique.putIfAbsent(item.key, () => item);
    }
    final pending = unique.values
        .where(
          (item) => !_tasks.values.any(
            (task) =>
                task.scope == scope &&
                task.item.key == item.key &&
                task.selection.quality == selection.quality &&
                task.selection.codec == selection.codec &&
                task.selection.output == selection.output,
          ),
        )
        .toList();
    final occupied = _tasks.values
        .where(
          (task) =>
              task.scope == scope && task.status != DownloadStatus.completed,
        )
        .length;
    if (occupied + pending.length > 500) {
      throw const AppFailure(AppFailureKind.storage, '下载队列最多保留 500 项');
    }
    if (pending.isEmpty) return;
    final root = _preferences.directory ?? await _defaultDirectory();
    if (!p.isAbsolute(root)) {
      throw ArgumentError.value(root, 'defaultDirectory');
    }
    if (!_batchCurrent(scope, epoch)) return;
    for (final item in pending) {
      if (!_batchCurrent(scope, epoch)) return;
      final id = _newId();
      final directory = await _files.createTaskDirectory(root, scope, id);
      final now = _clock();
      final task = DownloadTask(
        id: id,
        scope: scope,
        item: item,
        selection: selection,
        status: DownloadStatus.queued,
        directory: directory,
        createdAt: now,
        updatedAt: now,
      );
      if (!_batchCurrent(scope, epoch)) {
        await _files.deleteOwned(task);
        return;
      }
      _tasks[id] = task;
      await _save(task);
      _emit();
    }
    if (_batchCurrent(scope, epoch)) _pump();
  }

  static String _newId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  void _pump() {
    if (_suspendPump || _storageFault || _closing || _closed || !_initialized) {
      return;
    }
    while (_runs.length < _preferences.concurrency) {
      final queued = _tasks.values
          .where(
            (task) =>
                task.scope == _scope &&
                task.status == DownloadStatus.queued &&
                !_removing.contains(task.id) &&
                !_runs.containsKey(task.id),
          )
          .firstOrNull;
      if (queued == null) return;
      final run = _Run(RequestCancellation(), _scope, _epoch);
      _runs[queued.id] = run;
      run.future = _runTask(queued.id, run)
          .catchError(
            (Object _, StackTrace _) => _backgroundFailure(queued.id, run),
          )
          .whenComplete(() {
            if (identical(_runs[queued.id], run)) _runs.remove(queued.id);
            _pump();
          });
    }
  }

  bool _valid(String id, _Run run) =>
      !_closed &&
      !run.cancel.isCancelled &&
      identical(_runs[id], run) &&
      run.scope == _scope &&
      run.scope == sources.accountScope &&
      run.epoch == _epoch &&
      run.epoch == sources.sessionEpoch;

  Future<void> _runTask(String id, _Run run) async {
    try {
      var task = _tasks[id]!;
      if (task.selection.output == DownloadOutput.mp4 &&
          (await _files.verifyMerged(task) ||
              task.tracks.length == 2 && await _verifiedTracks(task))) {
        if (!_valid(id, run)) return;
        await _finishTask(task, id, run);
        return;
      }
      task = await _stage(task, DownloadStatus.resolving);
      if (!_valid(id, run)) return;
      var resolved = await sources.resolve(
        task.item,
        task.selection,
        cancellation: run.cancel,
      );
      if (!_valid(id, run)) return;
      if (resolved.quality != task.selection.quality ||
          resolved.video.urls.isEmpty ||
          resolved.audio.urls.isEmpty) {
        throw const AppFailure(AppFailureKind.protocol, '所选画质或音视频轨道不可用');
      }
      task = task.copyWith(duration: resolved.duration);
      task = await _resetChangedSources(task, resolved);
      if (!_valid(id, run)) return;
      task = await _stage(task, DownloadStatus.downloading);
      var index = 0;
      var refreshed = false;
      final deadline = DateTime.now().add(const Duration(hours: 3));
      while (index < 2) {
        if (!_valid(id, run)) return;
        final source = index == 0 ? resolved.video : resolved.audio;
        final name = source.kind == DownloadTrackKind.video
            ? 'video.m4s'
            : 'audio.m4s';
        var track =
            task.tracks.where((t) => t.kind == source.kind).firstOrNull ??
            DownloadTrackProgress(
              kind: source.kind,
              identity: source.identity,
              fileName: name,
              codec: source.codec,
              bandwidth: source.bandwidth,
            );
        if (track.complete &&
            track.identity == source.identity &&
            await _files.verifyTrack(task, track)) {
          if (!_valid(id, run)) return;
          index++;
          continue;
        }
        if (track.complete) track = _resetTrack(track);
        final part = await _files.taskFile(task, '$name.part');
        try {
          track = await _transfer.transfer(
            source: source,
            previous: track,
            partFile: part,
            headers: resolved.headers,
            cancellation: run.cancel,
            onProgress: (value) => _progress(id, run, value),
            deadline: deadline,
          );
        } on AppFailure catch (error) {
          if (error.kind != AppFailureKind.permission ||
              refreshed ||
              !_valid(id, run)) {
            rethrow;
          }
          refreshed = true;
          resolved = await sources.resolve(
            task.item,
            task.selection,
            cancellation: run.cancel,
          );
          if (!_valid(id, run)) return;
          if (resolved.quality != task.selection.quality ||
              resolved.video.urls.isEmpty ||
              resolved.audio.urls.isEmpty) {
            throw const AppFailure(AppFailureKind.protocol, '刷新后所选轨道不可用');
          }
          final currentTask = _tasks[id]!;
          final changed = currentTask.tracks.any(
            (saved) =>
                saved.identity !=
                (saved.kind == DownloadTrackKind.video
                    ? resolved.video.identity
                    : resolved.audio.identity),
          );
          task = await _resetChangedSources(currentTask, resolved);
          if (!_valid(id, run)) return;
          if (changed) index = 0;
          continue;
        }
        if (!_valid(id, run)) return;
        task = _tasks[id]!;
        final completed = await _files.completeTrack(task, track);
        if (!_valid(id, run)) return;
        task = task.copyWith(tracks: _replaceTrack(task.tracks, completed));
        _tasks[id] = task;
        await _save(task);
        if (!_valid(id, run)) return;
        _emit();
        index++;
      }
      if (!_valid(id, run)) return;
      await _finishTask(_tasks[id]!, id, run);
    } catch (error) {
      final task = _tasks[id];
      if (task == null || run.scope != _scope || run.epoch != _epoch) return;
      final cancelled =
          !_backgroundFailed.contains(id) &&
          (run.cancel.isCancelled ||
              error is AppFailure && error.kind == AppFailureKind.cancelled);
      final failure = _backgroundFailed.contains(id)
          ? const AppFailure(AppFailureKind.storage, '下载索引写入失败')
          : error is AppFailure
          ? error
          : error is FileSystemException
          ? const AppFailure(AppFailureKind.storage, '离线文件读写失败')
          : const AppFailure(AppFailureKind.unknown, '下载失败，请重试');
      // The transfer has closed its handle before this catch completes. Use the
      // real part length, including a write interrupted between callbacks.
      final reconciled = await _reconcile(task);
      final next = reconciled.copyWith(
        status: cancelled ? DownloadStatus.paused : DownloadStatus.failed,
        failure: cancelled ? null : failure,
        clearFailure: cancelled,
        bytesPerSecond: 0,
        updatedAt: _clock(),
      );
      _tasks[id] = next;
      await _save(next);
      _emit();
    }
  }

  Future<bool> _verifiedTracks(DownloadTask task) async {
    if (task.tracks.length != 2) return false;
    for (final track in task.tracks) {
      if (!await _files.verifyTrack(task, track)) return false;
    }
    return true;
  }

  Future<void> _finishTask(DownloadTask task, String id, _Run run) async {
    task = await _stage(task, DownloadStatus.verifying);
    if (!_valid(id, run)) return;
    final reusedOutput =
        task.selection.output == DownloadOutput.mp4 &&
        await _files.verifyMerged(task);
    if (!reusedOutput && !await _verifiedTracks(task)) {
      throw const AppFailure(AppFailureKind.storage, '媒体文件校验失败');
    }
    if (!_valid(id, run)) return;
    var warnings = task.warnings;
    final extrasFile = await _files.taskFile(task, 'extras.json');
    if (!await extrasFile.exists()) {
      try {
        final extras = await sources.extras(
          task.item,
          task.selection,
          cancellation: run.cancel,
        );
        if (!_valid(id, run)) return;
        await _files.writeExtras(task, extras);
        warnings = extras.warnings;
      } on AppFailure catch (error) {
        if (error.kind == AppFailureKind.cancelled || !_valid(id, run)) return;
        warnings = ['附属内容下载失败：${error.message}'];
      } catch (_) {
        if (!_valid(id, run)) return;
        warnings = ['附属内容下载失败'];
      }
    }
    if (!_valid(id, run)) return;
    task = _tasks[id]!.copyWith(warnings: warnings, updatedAt: _clock());
    if (task.selection.output == DownloadOutput.mp4 && !reusedOutput) {
      task = await _stage(task, DownloadStatus.muxing);
      if (!_valid(id, run)) return;
      final output = await _files.taskFile(task, 'media.mp4.part');
      try {
        if (await output.exists()) await output.delete();
        await _muxer.merge(
          videoPath: (await _files.taskFile(task, 'video.m4s')).path,
          audioPath: (await _files.taskFile(task, 'audio.m4s')).path,
          outputPath: output.path,
          cancellation: run.cancel,
          onProgress: (progress) {
            if (!_valid(id, run)) return;
            _tasks[id] = _tasks[id]!.copyWith(
              muxProgress: progress.clamp(0, 1),
            );
            _emit();
          },
        );
        if (!_valid(id, run)) return;
        final merged = await _files.completeMerged(task);
        if (!_valid(id, run)) return;
        task = _tasks[id]!.copyWith(mergedMedia: merged);
        _tasks[id] = task;
        // Persist output identity before the manifest and completion commit.
        await _save(task);
      } finally {
        // Native merge has closed all handles, including after cancellation.
        if (await output.exists()) await output.delete();
      }
    }
    if (!_valid(id, run)) return;
    await _files.writeManifest(task);
    if (!_valid(id, run)) return;
    task = task.copyWith(
      status: DownloadStatus.completed,
      bytesPerSecond: 0,
      updatedAt: _clock(),
      clearFailure: true,
    );
    // Keep the live state incomplete until the SQLite commit succeeds.
    await _save(task);
    if (!_valid(id, run)) return;
    _tasks[id] = task;
    _emit();
    try {
      await _files.removeSourceTracks(task, verifyHashes: false);
    } on FileSystemException {
      // Retaining originals after a successful commit is safe; retry cleanup
      // on the next reconciliation. Never turn usable media into a failure.
    }
  }

  Future<DownloadTask> _stage(DownloadTask task, DownloadStatus status) async {
    final next = task.copyWith(
      status: status,
      muxProgress: status == DownloadStatus.muxing ? 0 : task.muxProgress,
      updatedAt: _clock(),
      clearFailure: true,
    );
    _tasks[task.id] = next;
    await _save(next);
    _emit();
    return next;
  }

  Future<DownloadTask> _resetChangedSources(
    DownloadTask task,
    DownloadResolvedSource source,
  ) async {
    final changed = task.tracks.any(
      (track) =>
          track.identity !=
          (track.kind == DownloadTrackKind.video
              ? source.video.identity
              : source.audio.identity),
    );
    if (!changed) return task;
    await _files.resetMedia(task);
    final next = task.copyWith(
      tracks: const [],
      clearMergedMedia: true,
      bytesPerSecond: 0,
      updatedAt: _clock(),
    );
    _tasks[task.id] = next;
    await _save(next);
    _emit();
    return next;
  }

  void _progress(String id, _Run run, DownloadTrackProgress track) {
    if (!_valid(id, run) || _removing.contains(id)) return;
    final task = _tasks[id];
    if (task == null) return;
    final now = _clock();
    final tracks = _replaceTrack(task.tracks, track);
    final totalBytes = tracks.fold<int>(0, (sum, value) => sum + value.bytes);
    final next = task.copyWith(
      tracks: tracks,
      bytesPerSecond: run.speed(totalBytes, now),
      updatedAt: now,
    );
    _tasks[id] = next;
    if (now.difference(run.lastUi).inMilliseconds >= 250) {
      run.lastUi = now;
      _emit();
    }
    if (now.difference(run.lastStore).inSeconds >= 1) {
      run.lastStore = now;
      unawaited(
        _save(next).catchError((Object _, StackTrace _) {
          _backgroundFailure(id, run);
        }),
      );
    }
  }

  void _backgroundFailure(String id, _Run run) {
    if (run.scope != _scope ||
        run.epoch != _epoch ||
        run.scope != sources.accountScope ||
        run.epoch != sources.sessionEpoch) {
      return;
    }
    _storageFault = true;
    _failure = const AppFailure(AppFailureKind.storage, '下载索引写入失败');
    _backgroundFailed.add(id);
    _runs[id]?.cancel.cancel();
    final task = _tasks[id];
    if (task != null && task.scope == _scope) {
      _tasks[id] = task.copyWith(
        status: DownloadStatus.failed,
        failure: _failure,
        bytesPerSecond: 0,
        updatedAt: _clock(),
      );
    }
    _emit();
  }

  static List<DownloadTrackProgress> _replaceTrack(
    List<DownloadTrackProgress> tracks,
    DownloadTrackProgress update,
  ) => [
    for (final track in tracks)
      if (track.kind != update.kind) track,
    update,
  ];

  static DownloadTrackProgress _resetTrack(DownloadTrackProgress track) =>
      DownloadTrackProgress(
        kind: track.kind,
        identity: track.identity,
        fileName: track.fileName,
        codec: track.codec,
        bandwidth: track.bandwidth,
      );

  static DownloadTrackProgress _withBytes(
    DownloadTrackProgress track,
    int bytes,
  ) => DownloadTrackProgress(
    kind: track.kind,
    identity: track.identity,
    fileName: track.fileName,
    codec: track.codec,
    bandwidth: track.bandwidth,
    bytes: bytes,
    totalBytes: track.totalBytes,
    etag: track.etag,
  );

  Future<void> _save(DownloadTask task) {
    final next = _writes.then(
      (_) => db.transaction(
        () => db.customStatement(
          '''INSERT INTO download_tasks(id,scope,item_key,record_json) VALUES (?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET scope=excluded.scope,
      item_key=excluded.item_key,record_json=excluded.record_json''',
          [task.id, task.scope, task.item.key, _encodeTask(task)],
        ),
      ),
    );
    _writes = next.then((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  @override
  Future<void> pause(String id) async {
    await initialize();
    final scope = _scope;
    final epoch = _epoch;
    final task = _tasks[id];
    if (task == null ||
        task.scope != _scope ||
        task.status == DownloadStatus.completed) {
      return;
    }
    final run = _runs[id];
    run?.cancel.cancel();
    if (run != null) await run.future;
    final current = _tasks[id];
    if (current == null ||
        current.scope != scope ||
        scope != _scope ||
        epoch != _epoch ||
        scope != sources.accountScope ||
        epoch != sources.sessionEpoch ||
        run != null && _runs[id] != null && !identical(_runs[id], run)) {
      return;
    }
    final next = current.copyWith(
      status: DownloadStatus.paused,
      clearFailure: true,
      bytesPerSecond: 0,
      updatedAt: _clock(),
    );
    _tasks[id] = next;
    await _save(next);
    _emit();
  }

  @override
  Future<void> resume(String id) async {
    await initialize();
    final scope = _scope;
    final epoch = _epoch;
    final task = _tasks[id];
    if (task == null ||
        task.scope != _scope ||
        !{DownloadStatus.paused, DownloadStatus.failed}.contains(task.status)) {
      return;
    }
    final next = (await _reconcile(task)).copyWith(
      status: DownloadStatus.queued,
      clearFailure: true,
      updatedAt: _clock(),
    );
    if (_removing.contains(id) ||
        _sessionPending > 0 ||
        !identical(_tasks[id], task) ||
        scope != _scope ||
        epoch != _epoch ||
        scope != sources.accountScope ||
        epoch != sources.sessionEpoch) {
      return;
    }
    _tasks[id] = next;
    await _save(next);
    _backgroundFailed.remove(id);
    _emit();
    _pump();
  }

  @override
  Future<void> pauseAll() async {
    await initialize();
    _suspendPump = true;
    for (final run in _runs.values) {
      run.cancel.cancel();
    }
    try {
      for (final task in _visible()) {
        if (task.active) await pause(task.id);
      }
    } finally {
      _suspendPump = false;
    }
  }

  @override
  Future<void> resumeAll() async {
    await initialize();
    _suspendPump = true;
    try {
      for (final task in _visible()) {
        if (task.status == DownloadStatus.paused ||
            task.status == DownloadStatus.failed) {
          await resume(task.id);
        }
      }
    } finally {
      _suspendPump = false;
    }
    _pump();
  }

  @override
  Future<void> remove(String id, {required bool deleteFiles}) async {
    await initialize();
    final scope = _scope;
    final epoch = _epoch;
    final task = _tasks[id];
    if (task == null || task.scope != scope || !_removing.add(id)) return;
    try {
      await pause(id);
      final current = _tasks[id];
      if (current == null ||
          current.scope != scope ||
          _sessionPending > 0 ||
          scope != _scope ||
          epoch != _epoch ||
          scope != sources.accountScope ||
          epoch != sources.sessionEpoch) {
        return;
      }
      _tasks.remove(id);
      _emit();
      try {
        if (deleteFiles) await _files.deleteOwned(current);
        await _writes;
        await db.customStatement(
          'DELETE FROM download_tasks WHERE id = ? AND scope = ?',
          [id, scope],
        );
      } catch (_) {
        if (scope == _scope && epoch == _epoch && !_tasks.containsKey(id)) {
          _tasks[id] = current;
          _emit();
        }
        rethrow;
      }
    } finally {
      _removing.remove(id);
    }
  }

  @override
  Future<void> refresh() async {
    await initialize();
    await db.customSelect('SELECT 1').getSingle();
    final scope = _scope;
    final epoch = _epoch;
    for (final task in _visible()) {
      if (_runs.containsKey(task.id) || _removing.contains(task.id)) continue;
      final next = await _reconcile(task);
      if (_sessionPending > 0 ||
          scope != _scope ||
          epoch != _epoch ||
          scope != sources.accountScope ||
          epoch != sources.sessionEpoch ||
          !identical(_tasks[task.id], task) ||
          _removing.contains(task.id)) {
        return;
      }
      _tasks[task.id] = next;
      await _save(next);
    }
    _storageFault = false;
    _failure = null;
    _emit();
    _pump();
  }

  @override
  Future<void> updatePreferences(DownloadPreferences preferences) async {
    await initialize();
    if (preferences.concurrency < 1 ||
        preferences.concurrency > 3 ||
        preferences.directory != null &&
            !p.isAbsolute(preferences.directory!)) {
      throw ArgumentError.value(preferences, 'preferences');
    }
    await db.writeSetting(
      'downloads.v1',
      jsonEncode({
        'version': 1,
        'directory': preferences.directory == null
            ? null
            : p.normalize(preferences.directory!),
        'concurrency': preferences.concurrency,
      }),
    );
    _preferences = preferences;
    _emit();
    _pump();
  }

  @override
  Future<void> sessionChanged() {
    // Cancellation happens synchronously before the first await.
    _sessionPending++;
    _suspendPump = true;
    for (final run in _runs.values) {
      run.cancel.cancel();
    }
    final next = _sessionSerial.then((_) async {
      try {
        await _enqueueSerial;
        await Future.wait(_runs.values.map((run) => run.future).toList());
        await _writes;
        _tasks.clear();
        _backgroundFailed.clear();
        _scope = sources.accountScope;
        _epoch = sources.sessionEpoch;
        _initialized = false;
        _initializing = null;
        await initialize();
      } catch (_) {
        _storageFault = true;
        _failure = const AppFailure(AppFailureKind.storage, '下载索引切换失败');
        _emit();
        rethrow;
      } finally {
        _sessionPending--;
        _suspendPump = _sessionPending > 0;
      }
    });
    _sessionSerial = next.then((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  @override
  Future<DownloadTask> offlineTask(String id) async {
    await initialize();
    final scope = _scope;
    final epoch = _epoch;
    final task = _tasks[id];
    if (task == null ||
        task.scope != _scope ||
        task.status != DownloadStatus.completed) {
      throw const AppFailure(AppFailureKind.notFound, '离线下载不存在');
    }
    final reconciled = await _reconcile(task, verifyHashes: true);
    if (scope != _scope ||
        epoch != _epoch ||
        scope != sources.accountScope ||
        epoch != sources.sessionEpoch ||
        !identical(_tasks[id], task) ||
        _removing.contains(id)) {
      throw const AppFailure(AppFailureKind.cancelled, '账号已切换');
    }
    if (reconciled.status != DownloadStatus.completed) {
      _tasks[id] = reconciled;
      await _save(reconciled);
      _emit();
      throw reconciled.failure ??
          const AppFailure(AppFailureKind.storage, '离线文件校验失败');
    }
    return reconciled;
  }

  @override
  Future<void> close() {
    if (_closingFuture case final future?) return future;
    _closing = true;
    return _closingFuture = _close();
  }

  Future<void> _close() async {
    _suspendPump = true;
    for (final run in _runs.values) {
      run.cancel.cancel();
    }
    await _enqueueSerial;
    await _sessionSerial;
    await Future.wait(_runs.values.map((run) => run.future).toList());
    await _writes;
    _closed = true;
    await _changes.close();
  }
}

final class _Run {
  _Run(this.cancel, this.scope, this.epoch);
  final RequestCancellation cancel;
  final String scope;
  final int epoch;
  late Future<void> future;
  DateTime lastUi = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime lastStore = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _speedAt;
  int _speedBytes = 0;
  int _lastSpeed = 0;
  int speed(int bytes, DateTime now) {
    if (_speedAt == null || bytes < _speedBytes) {
      _speedAt = now;
      _speedBytes = bytes;
      _lastSpeed = 0;
      return 0;
    }
    final elapsed = now.difference(_speedAt!).inMilliseconds;
    if (elapsed < 500) return _lastSpeed;
    final rate = ((bytes - _speedBytes) * 1000 ~/ elapsed).clamp(0, 1 << 30);
    _speedAt = now;
    _speedBytes = bytes;
    _lastSpeed = rate;
    return _lastSpeed;
  }
}

String _encodeTask(DownloadTask task) => jsonEncode({
  'version': 2,
  'id': task.id,
  'scope': task.scope,
  'directory': task.directory,
  'status': task.status.name,
  'createdAtMs': task.createdAt.millisecondsSinceEpoch,
  'updatedAtMs': task.updatedAt.millisecondsSinceEpoch,
  'video': {
    'id': task.item.video.id.value,
    'title': task.item.video.title,
    'author': task.item.video.author,
    'durationMs': task.item.video.duration.inMilliseconds,
  },
  'part': {
    'cid': task.item.part.cid,
    'page': task.item.part.page,
    'title': task.item.part.title,
    'durationMs': task.item.part.duration.inMilliseconds,
  },
  'aid': task.item.aid,
  'episodeId': task.item.episodeId,
  'seasonId': task.item.seasonId,
  'selection': {
    'quality': task.selection.quality,
    'codec': task.selection.codec.name,
    'includeDanmaku': task.selection.includeDanmaku,
    'includeSubtitles': task.selection.includeSubtitles,
    'output': task.selection.output.name,
  },
  if (task.mergedMedia case final media?)
    'mergedMedia': {'bytes': media.bytes, 'sha256': media.sha256},
  'tracks': task.tracks
      .map(
        (track) => {
          'kind': track.kind.name,
          'identity': track.identity,
          'fileName': track.fileName,
          'codec': track.codec,
          'bandwidth': track.bandwidth,
          'bytes': track.bytes,
          'totalBytes': track.totalBytes,
          'etag': track.etag,
          'sha256': track.sha256,
        },
      )
      .toList(),
  'failureKind': task.failure?.kind.name,
  'failureMessage': task.failure?.message,
  'warnings': task.warnings,
  'durationMs': task.duration?.inMilliseconds,
});

DownloadTask _decodeTask(String text) {
  try {
    final value = jsonDecode(text) as Map<String, dynamic>;
    final video = value['video'] as Map<String, dynamic>;
    final part = value['part'] as Map<String, dynamic>;
    final selection = value['selection'] as Map<String, dynamic>;
    final tracks = value['tracks'] as List<dynamic>;
    final merged = value['mergedMedia'] as Map<String, dynamic>?;
    final kind = AppFailureKind.values
        .where((x) => x.name == value['failureKind'])
        .firstOrNull;
    return DownloadTask(
      id: value['id'] as String,
      scope: value['scope'] as String,
      directory: value['directory'] as String,
      status: DownloadStatus.values.byName(value['status'] as String),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        value['createdAtMs'] as int,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        value['updatedAtMs'] as int,
      ),
      item: DownloadItem(
        video: VideoSummary(
          id: VideoId(video['id'] as String),
          title: video['title'] as String,
          coverUrl: '',
          author: video['author'] as String,
          duration: Duration(milliseconds: video['durationMs'] as int),
        ),
        part: VideoPart(
          cid: part['cid'] as String,
          page: part['page'] as int,
          title: part['title'] as String,
          duration: Duration(milliseconds: part['durationMs'] as int),
        ),
        aid: value['aid'] as String?,
        episodeId: value['episodeId'] as String?,
        seasonId: value['seasonId'] as String?,
      ),
      selection: DownloadSelection(
        quality: selection['quality'] as int,
        codec: VideoCodecPreference.values.byName(selection['codec'] as String),
        includeDanmaku: selection['includeDanmaku'] as bool,
        includeSubtitles: selection['includeSubtitles'] as bool,
        output: selection['output'] == null
            ? DownloadOutput.separate
            : DownloadOutput.values.byName(selection['output'] as String),
      ),
      mergedMedia: merged == null
          ? null
          : DownloadMergedMedia(
              bytes: merged['bytes'] as int,
              sha256: merged['sha256'] as String,
            ),
      tracks: tracks.map((raw) {
        final t = raw as Map<String, dynamic>;
        return DownloadTrackProgress(
          kind: DownloadTrackKind.values.byName(t['kind'] as String),
          identity: t['identity'] as String,
          fileName: t['fileName'] as String,
          codec: t['codec'] as String,
          bandwidth: t['bandwidth'] as int,
          bytes: t['bytes'] as int,
          totalBytes: t['totalBytes'] as int?,
          etag: t['etag'] as String?,
          sha256: t['sha256'] as String?,
        );
      }).toList(),
      failure: kind == null
          ? null
          : AppFailure(kind, value['failureMessage'] as String? ?? ''),
      warnings: (value['warnings'] as List<dynamic>).cast<String>(),
      duration: value['durationMs'] is int
          ? Duration(milliseconds: value['durationMs'] as int)
          : null,
    );
  } catch (_) {
    throw const FormatException('Invalid download record');
  }
}

final class _UnavailableDownloadMuxer implements DownloadMuxer {
  const _UnavailableDownloadMuxer();
  @override
  bool get available => false;
  @override
  Future<void> merge({
    required String videoPath,
    required String audioPath,
    required String outputPath,
    required RequestCancellation cancellation,
    required void Function(double) onProgress,
  }) async {
    throw const AppFailure(AppFailureKind.storage, '当前无法合并音视频');
  }
}
