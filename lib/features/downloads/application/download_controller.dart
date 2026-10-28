import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/download_repository.dart';
import '../domain/public_download_storage.dart';

final publicDownloadStorageProvider = Provider<PublicDownloadStorage?>(
  (ref) => null,
);

final downloadRepositoryProvider = Provider<DownloadRepository>((ref) {
  final repository = _UnavailableDownloadRepository();
  ref.onDispose(() => unawaited(repository.close()));
  return repository;
});

final downloadSourceRepositoryProvider = Provider<DownloadSourceRepository>(
  (ref) => throw UnimplementedError(
    'DownloadSourceRepository must be provided by app',
  ),
);

final downloadControllerProvider =
    NotifierProvider<DownloadController, DownloadQueueState>(
      DownloadController.new,
    );

final downloadQueueIndexProvider =
    NotifierProvider.autoDispose<
      DownloadQueueIndexController,
      DownloadQueueIndex
    >(DownloadQueueIndexController.new);

/// Built in O(N) per snapshot; each visible task then selects its value in O(1).
final class DownloadQueueIndex {
  DownloadQueueIndex._({
    required Map<String, DownloadTask> tasksById,
    required this.structure,
    required this.transferredBytes,
  }) : tasksById = Map.unmodifiable(tasksById);

  final Map<String, DownloadTask> tasksById;
  final DownloadQueueStructure structure;
  final int transferredBytes;
}

/// Stable while only transfer details change, including cached search titles.
final class DownloadQueueStructure {
  DownloadQueueStructure._({
    required List<DownloadTaskEntry> entries,
    required this.activeCount,
    required this.resumableCount,
  }) : entries = List.unmodifiable(entries),
       queued = List.unmodifiable(entries.where((entry) => !entry.completed)),
       completed = List.unmodifiable(entries.where((entry) => entry.completed));

  final List<DownloadTaskEntry> entries, queued, completed;
  final int activeCount, resumableCount;
}

final class DownloadTaskEntry {
  const DownloadTaskEntry._({
    required this.id,
    required this.scope,
    required this.videoTitle,
    required this.partTitle,
    required this.searchText,
    required this.completed,
  });

  final String id, scope, videoTitle, partTitle, searchText;
  final bool completed;
}

final class DownloadQueueIndexController extends Notifier<DownloadQueueIndex> {
  DownloadQueueIndex? _previous;
  Map<String, DownloadTaskEntry> _entriesById = const {};

  @override
  DownloadQueueIndex build() {
    final queue = ref.watch(downloadControllerProvider);
    final previousStructure = _previous?.structure;
    final tasksById = <String, DownloadTask>{};
    final entriesById = <String, DownloadTaskEntry>{};
    final entries = <DownloadTaskEntry>[];
    var unchanged = previousStructure?.entries.length == queue.tasks.length;
    var transferred = 0;
    var active = 0;
    var resumable = 0;
    for (final task in queue.tasks) {
      tasksById[task.id] = task;
      transferred += task.downloadedBytes;
      if (task.active) active++;
      if (task.status == DownloadStatus.paused ||
          task.status == DownloadStatus.failed) {
        resumable++;
      }
      final previous = _entriesById[task.id];
      final sameTitle =
          previous != null &&
          previous.videoTitle == task.item.video.title &&
          previous.partTitle == task.item.part.title;
      final completed = task.status == DownloadStatus.completed;
      final entry =
          sameTitle &&
              previous.scope == task.scope &&
              previous.completed == completed
          ? previous
          : DownloadTaskEntry._(
              id: task.id,
              scope: task.scope,
              videoTitle: task.item.video.title,
              partTitle: task.item.part.title,
              searchText: sameTitle
                  ? previous.searchText
                  : '${task.item.video.title} ${task.item.part.title}'
                        .toLowerCase(),
              completed: completed,
            );
      if (unchanged &&
          !identical(previousStructure?.entries[entries.length], entry)) {
        unchanged = false;
      }
      entries.add(entry);
      entriesById[task.id] = entry;
    }
    final structure =
        previousStructure != null &&
            unchanged &&
            previousStructure.activeCount == active &&
            previousStructure.resumableCount == resumable
        ? previousStructure
        : DownloadQueueStructure._(
            entries: entries,
            activeCount: active,
            resumableCount: resumable,
          );
    _entriesById = entriesById;
    return _previous = DownloadQueueIndex._(
      tasksById: tasksById,
      structure: structure,
      transferredBytes: transferred,
    );
  }
}

final class DownloadController extends Notifier<DownloadQueueState> {
  StreamSubscription<DownloadQueueState>? _subscription;

  DownloadRepository get _repository => ref.read(downloadRepositoryProvider);

  @override
  DownloadQueueState build() {
    final repository = ref.watch(downloadRepositoryProvider);
    _subscription?.cancel();
    _subscription = repository.changes.listen((next) {
      if (ref.mounted) state = next;
    });
    ref.onDispose(() => _subscription?.cancel());
    unawaited(
      repository.initialize().catchError((Object error) {
        if (!ref.mounted) return;
        state = DownloadQueueState(
          tasks: repository.current.tasks,
          preferences: repository.current.preferences,
          initialized: false,
          failure: error is AppFailure
              ? error
              : const AppFailure(AppFailureKind.storage, '下载索引初始化失败'),
        );
      }),
    );
    return repository.current;
  }

  Future<List<int>> qualities(
    DownloadItem item, {
    required RequestCancellation cancellation,
  }) => ref
      .read(downloadSourceRepositoryProvider)
      .qualities(item, cancellation: cancellation);

  Future<bool> hasDestination() async =>
      await ref.read(publicDownloadStorageProvider)?.hasDestination() ?? true;

  PublicDownloadStorage get _publicStorage =>
      ref.read(publicDownloadStorageProvider) ??
      (throw const AppFailure(AppFailureKind.storage, '文件夹选择不可用'));

  Future<bool> requestDirectoryAccess() =>
      _publicStorage.requestDirectoryAccess();
  Future<DownloadFolderListing> listDirectories(String? directory) =>
      _publicStorage.listDirectories(directory);
  Future<void> chooseDestination(String directory) =>
      _publicStorage.chooseDestination(directory);

  Future<void> enqueue(List<DownloadItem> items, DownloadSelection selection) =>
      _repository.enqueue(items, selection);
  Future<void> pause(String id) => _repository.pause(id);
  Future<void> resume(String id) => _repository.resume(id);
  Future<void> pauseAll() => _repository.pauseAll();
  Future<void> resumeAll() => _repository.resumeAll();
  Future<void> remove(String id, {required bool deleteFiles}) =>
      _repository.remove(id, deleteFiles: deleteFiles);
  Future<void> refresh() => _repository.refresh();
  Future<void> updatePreferences(DownloadPreferences preferences) =>
      _repository.updatePreferences(preferences);
}

final class _UnavailableDownloadRepository implements DownloadRepository {
  final _changes = StreamController<DownloadQueueState>.broadcast();
  DownloadQueueState _state = DownloadQueueState(initialized: true);

  @override
  DownloadQueueState get current => _state;
  @override
  Stream<DownloadQueueState> get changes => _changes.stream;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> enqueue(
    List<DownloadItem> items,
    DownloadSelection selection,
  ) async {
    throw const AppFailure(AppFailureKind.storage, '下载服务尚未初始化');
  }

  @override
  Future<void> pause(String id) async {}
  @override
  Future<void> resume(String id) async {}
  @override
  Future<void> pauseAll() async {}
  @override
  Future<void> resumeAll() async {}
  @override
  Future<void> remove(String id, {required bool deleteFiles}) async {}
  @override
  Future<void> refresh() async {}
  @override
  Future<void> updatePreferences(DownloadPreferences preferences) async {
    _state = DownloadQueueState(preferences: preferences, initialized: true);
    _changes.add(_state);
  }

  @override
  Future<void> sessionChanged() async {}
  @override
  Future<DownloadTask> offlineTask(String id) async =>
      throw const AppFailure(AppFailureKind.notFound, '离线下载不存在');
  @override
  Future<void> close() => _changes.close();
}
