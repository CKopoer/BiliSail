enum VideoAccessKind { normal, chargingExclusive, paid }

final class VideoAccess {
  const VideoAccess({
    this.kind = VideoAccessKind.normal,
    this.canWatch,
    this.canPreview = false,
  });

  final VideoAccessKind kind;
  final bool? canWatch;
  final bool canPreview;

  String? get label => switch (kind) {
    VideoAccessKind.normal => null,
    VideoAccessKind.chargingExclusive => '充电专属',
    VideoAccessKind.paid => '付费视频',
  };
}
