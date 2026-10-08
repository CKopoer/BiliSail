import 'package:bili_mux/bili_mux.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/download_muxer.dart';

final class NativeDownloadMuxer implements DownloadMuxer {
  NativeDownloadMuxer({NativeMuxer? native})
    : _native = native ?? NativeMuxer();
  final NativeMuxer _native;
  @override
  bool get available => _native.available;
  @override
  Future<void> merge({
    required String videoPath,
    required String audioPath,
    required String outputPath,
    required RequestCancellation cancellation,
    required void Function(double) onProgress,
  }) async {
    final token = MuxCancellation();
    var active = true;
    // RequestCancellation is shared by queue stages; detach logically after
    // completion so a later pause cannot touch a freed native job.
    cancellation.onCancel(() {
      if (active) token.cancel();
    });
    try {
      await _native.merge(
        videoPath: videoPath,
        audioPath: audioPath,
        outputPath: outputPath,
        cancellation: token,
        onProgress: onProgress,
      );
    } on MuxException catch (error) {
      throw switch (error.failure) {
        MuxFailure.cancelled => const AppFailure(
          AppFailureKind.cancelled,
          '合并已取消',
        ),
        MuxFailure.timeout => const AppFailure(
          AppFailureKind.timeout,
          '合并超时，请重试',
        ),
        MuxFailure.unavailable => const AppFailure(
          AppFailureKind.storage,
          '当前无法合并音视频',
        ),
        MuxFailure.input => const AppFailure(
          AppFailureKind.protocol,
          '音视频格式不支持或文件不完整',
        ),
        MuxFailure.verification => const AppFailure(
          AppFailureKind.storage,
          '合并文件校验失败，原分轨已保留',
        ),
        MuxFailure.output => const AppFailure(
          AppFailureKind.storage,
          '合并文件写入失败，请检查剩余空间',
        ),
        MuxFailure.internal => const AppFailure(
          AppFailureKind.storage,
          '合并失败，原分轨已保留，可重试',
        ),
      };
    } finally {
      active = false;
    }
  }
}
