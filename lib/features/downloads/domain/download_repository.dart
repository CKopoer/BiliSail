import '../../../domain/request_cancellation.dart';
import 'download_models.dart';

export 'download_models.dart';

abstract interface class DownloadSourceRepository {
  String get accountScope;
  int get sessionEpoch;
  Future<List<int>> qualities(
    DownloadItem item, {
    required RequestCancellation cancellation,
  });
  Future<DownloadResolvedSource> resolve(
    DownloadItem item,
    DownloadSelection selection, {
    required RequestCancellation cancellation,
  });
  Future<DownloadExtras> extras(
    DownloadItem item,
    DownloadSelection selection, {
    required RequestCancellation cancellation,
  });
}

/// Process-owned queue. UI/controller disposal must never stop transfers.
abstract interface class DownloadRepository {
  DownloadQueueState get current;
  Stream<DownloadQueueState> get changes;
  Future<void> initialize();
  Future<void> enqueue(List<DownloadItem> items, DownloadSelection selection);
  Future<void> pause(String id);
  Future<void> resume(String id);
  Future<void> pauseAll();
  Future<void> resumeAll();
  Future<void> remove(String id, {required bool deleteFiles});
  Future<void> refresh();
  Future<void> updatePreferences(DownloadPreferences preferences);

  /// Cancel old work synchronously before waiting for file handles to close.
  Future<void> sessionChanged();

  /// Reconcile disk content and scope before an offline player opens it.
  Future<DownloadTask> offlineTask(String id);
  Future<void> close();
}
