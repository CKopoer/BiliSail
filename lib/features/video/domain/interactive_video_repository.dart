import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';

final class InteractiveVideoChoice {
  const InteractiveVideoChoice({
    required this.edgeId,
    required this.cid,
    required this.label,
  });

  final String edgeId;
  final String cid;
  final String label;
}

abstract interface class InteractiveVideoRepository {
  Future<String> loadGraphVersion(
    VideoId id,
    String cid, {
    required RequestCancellation cancellation,
  });

  Future<List<InteractiveVideoChoice>> loadChoices(
    VideoId id,
    String graphVersion, {
    String? edgeId,
    required RequestCancellation cancellation,
  });
}
