import 'package:bili_api/bili_api.dart';

import '../../core/network/api_requests.dart';
import '../../domain/request_cancellation.dart';
import '../../domain/video.dart';
import '../../domain/video_cover_repository.dart';

final class ApiVideoCoverRepository implements VideoCoverRepository {
  const ApiVideoCoverRepository(this.api, this.requests);

  final BiliApiClient api;
  final ApiRequests requests;

  @override
  Duration get cover43Cooldown => api.videoCover43Cooldown;

  @override
  Future<Map<VideoId, Uri>> loadCover43Urls(
    List<VideoId> ids, {
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    final urls = await api.getVideoCover43Urls(
      ids.map((id) => id.value),
      context: context,
    );
    return {for (final entry in urls.entries) VideoId(entry.key): entry.value};
  }, cancellation: cancellation);
}
