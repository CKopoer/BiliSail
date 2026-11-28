import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/video.dart';
import 'video_controller.dart';

typedef PrepareFeaturedPlayInfo = void Function() Function(
  VideoId video,
  String cid, {
  required bool neighbor,
});

final featuredPlayInfoPreparationProvider = Provider<PrepareFeaturedPlayInfo?>(
  (ref) => null,
);

final _preparedPlayInfo = Provider.autoDispose
    .family<void, ({VideoId id, String cid, bool neighbor})>((ref, part) {
      final prepare = ref.watch(featuredPlayInfoPreparationProvider);
      if (prepare != null) {
        ref.onDispose(prepare(part.id, part.cid, neighbor: part.neighbor));
      }
    });

/// Keep both neighbors ready to become current without restarting their
/// detail or playurl requests when the swipe settles.
void watchFeaturedVideoPreparation(
  WidgetRef ref, {
  required VideoSummary? current,
  required VideoSummary? next,
  required VideoSummary? previous,
  bool Function(VideoId video, String cid)? hasReusableMedia,
}) {
  if (ref.watch(featuredPlayInfoPreparationProvider) == null) return;
  for (final video in [?current, ?next, ?previous]) {
    final parts = ref.watch(videoDetailProvider(video.id)).value?.parts;
    final cid = video.previewCid ?? parts?.singleOrNull?.cid;
    if (cid != null && hasReusableMedia?.call(video.id, cid) != true) {
      ref.watch(
        _preparedPlayInfo((id: video.id, cid: cid, neighbor: video != current)),
      );
    }
  }
}
