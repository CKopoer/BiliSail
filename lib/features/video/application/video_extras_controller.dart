import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../domain/video_extras_repository.dart';

final videoExtrasRepositoryProvider = Provider<VideoExtrasRepository>(
  (ref) =>
      throw UnimplementedError('VideoExtrasRepository must be provided by app'),
);
final relatedVideosProvider = FutureProvider.autoDispose
    .family<List<VideoSummary>, VideoId>((ref, id) {
      final cancellation = RequestCancellation();
      ref.onDispose(cancellation.cancel);
      return ref
          .read(videoExtrasRepositoryProvider)
          .loadRelated(id, cancellation: cancellation);
    });
final videoCommentsProvider = FutureProvider.autoDispose
    .family<VideoCommentsPage, ({VideoId id, int page})>((ref, request) {
      final cancellation = RequestCancellation();
      ref.onDispose(cancellation.cancel);
      return ref
          .read(videoExtrasRepositoryProvider)
          .loadComments(
            request.id,
            page: request.page,
            cancellation: cancellation,
          );
    });
