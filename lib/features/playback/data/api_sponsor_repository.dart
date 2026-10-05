import 'package:bili_api/bili_api.dart';

import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../domain/sponsor_repository.dart';

final class ApiSponsorRepository implements SponsorRepository {
  const ApiSponsorRepository(this.client);
  final SponsorBlockClient client;

  @override
  Future<List<SponsorSegment>> segments(
    VideoId video,
    String cid, {
    required List<String> categories,
    required RequestCancellation cancellation,
  }) async {
    final token = ApiCancellation();
    cancellation.onCancel(token.cancel);
    final result = await client.segments(
      video.value,
      cid,
      categories: categories,
      cancellation: token,
    );
    return result
        .map(
          (item) => SponsorSegment(
            id: item.id,
            category: item.category,
            start: item.start,
            end: item.end,
            videoDuration: item.videoDuration,
          ),
        )
        .toList(growable: false);
  }
}
