import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';

final class SponsorSegment {
  const SponsorSegment({
    required this.id,
    required this.category,
    required this.start,
    required this.end,
    required this.videoDuration,
  });
  final String id;
  final String category;
  final Duration start;
  final Duration end;
  final Duration videoDuration;

  bool matches(Duration duration) =>
      duration > Duration.zero &&
      start >= Duration.zero &&
      end > start &&
      end <= duration &&
      (videoDuration == Duration.zero ||
          (videoDuration - duration).abs() <= const Duration(seconds: 2));
}

abstract interface class SponsorRepository {
  Future<List<SponsorSegment>> segments(
    VideoId video,
    String cid, {
    required List<String> categories,
    required RequestCancellation cancellation,
  });
}
