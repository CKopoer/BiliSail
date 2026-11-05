import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../domain/log_export_repository.dart';

final logExportRepositoryProvider = Provider<LogExportRepository>(
  (ref) =>
      throw UnimplementedError('LogExportRepository must be provided by app'),
);
final logExportControllerProvider =
    NotifierProvider<LogExportController, AsyncValue<String?>>(
      LogExportController.new,
    );

final class LogExportController extends Notifier<AsyncValue<String?>> {
  @override
  AsyncValue<String?> build() => const AsyncData(null);

  Future<void> export() async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    try {
      final path = await ref.read(logExportRepositoryProvider).export();
      if (ref.mounted) state = AsyncData(path);
    } catch (error, stack) {
      if (ref.mounted) {
        state = AsyncError(
          error is AppFailure
              ? error
              : const AppFailure(AppFailureKind.storage, '日志导出失败，请稍后重试'),
          stack,
        );
      }
    }
  }
}
