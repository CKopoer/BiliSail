import '../../../domain/request_cancellation.dart';

/// Only consumes verified, application-owned local files. No network/player.
abstract interface class DownloadMuxer {
  bool get available;
  Future<void> merge({
    required String videoPath,
    required String audioPath,
    required String outputPath,
    required RequestCancellation cancellation,
    required void Function(double progress) onProgress,
  });
}
