import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';

typedef VideoActionTarget = ({VideoId id, String aid});

final class VideoInteraction {
  const VideoInteraction({
    this.liked = false,
    this.coins = 0,
    this.favorited = false,
  });
  final bool liked;
  final int coins;
  final bool favorited;
  VideoInteraction copyWith({bool? liked, int? coins, bool? favorited}) =>
      VideoInteraction(
        liked: liked ?? this.liked,
        coins: coins ?? this.coins,
        favorited: favorited ?? this.favorited,
      );
}

final class FavoriteFolder {
  const FavoriteFolder({
    required this.id,
    required this.title,
    required this.containsVideo,
  });
  final String id;
  final String title;
  final bool containsVideo;
}

final class UnknownWriteOutcome implements Exception {
  const UnknownWriteOutcome();
}

abstract interface class VideoActionsRepository {
  String get accountScope;
  Future<VideoInteraction> load(
    VideoActionTarget target,
    RequestCancellation cancellation,
  );
  Future<List<FavoriteFolder>> folders(
    VideoActionTarget target,
    RequestCancellation cancellation,
  );
  Future<void> like(
    VideoActionTarget target,
    bool liked,
    RequestCancellation cancellation,
  );
  Future<void> coin(
    VideoActionTarget target,
    int count,
    RequestCancellation cancellation,
  );
  Future<void> favorite(
    VideoActionTarget target,
    List<String> add,
    List<String> remove,
    RequestCancellation cancellation,
  );
  Future<void> watchLater(
    VideoActionTarget target,
    RequestCancellation cancellation,
  );
  Future<void> sendDanmaku(
    VideoActionTarget target,
    String cid,
    String message,
    Duration position,
    int mode,
    int color,
    RequestCancellation cancellation,
  );
}
