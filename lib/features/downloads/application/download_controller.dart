import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/download_repository.dart';

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
