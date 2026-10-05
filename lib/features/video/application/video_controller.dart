import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../domain/video_repository.dart';

final videoRepositoryProvider = Provider<VideoRepository>(
  (ref) => throw UnimplementedError('VideoRepository must be provided by app'),
);

final videoDetailProvider = FutureProvider.autoDispose
    .family<VideoDetail, VideoId>((ref, id) {
      final cancellation = RequestCancellation();
      ref.onDispose(cancellation.cancel);
      return ref
          .read(videoRepositoryProvider)
          .loadDetail(id, cancellation: cancellation);
    });
