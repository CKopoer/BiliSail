import '../../../domain/dynamic_post.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';

final class DynamicTopicDetail {
  const DynamicTopicDetail({
    required this.id,
    required this.name,
    this.description = '',
    this.viewCount = 0,
    this.discussCount = 0,
    this.creatorId,
    this.creatorName = '',
    this.creatorAvatar,
    this.favoriteCount = 0,
    this.isFavorite = false,
  });
  final String id, name, description, creatorName;
  final int viewCount, discussCount;
  final UserId? creatorId;
  final Uri? creatorAvatar;
  final int favoriteCount;
  final bool isFavorite;

  DynamicTopicDetail withFavorite(bool value) => DynamicTopicDetail(
    id: id,
    name: name,
    description: description,
    viewCount: viewCount,
    discussCount: discussCount,
    creatorId: creatorId,
    creatorName: creatorName,
    creatorAvatar: creatorAvatar,
    isFavorite: value,
    favoriteCount:
        (favoriteCount +
                (value == isFavorite
                    ? 0
                    : value
                    ? 1
                    : -1))
            .clamp(0, 0x7fffffffffffffff),
  );
}

final class DynamicTopicSort {
  const DynamicTopicSort(this.id, this.name);
  final int id;
  final String name;
}

final class DynamicTopicPage {
  DynamicTopicPage({
    required List<DynamicPost> posts,
    required this.hasMore,
    this.nextCursor,
    List<DynamicTopicSort> sorts = const [],
    this.selectedSort,
    this.foldDescription = '',
  }) : posts = List.unmodifiable(posts),
       sorts = List.unmodifiable(sorts);
  final List<DynamicPost> posts;
  final bool hasMore;
  final String? nextCursor;
  final List<DynamicTopicSort> sorts;
  final int? selectedSort;
  final String foldDescription;
}

abstract interface class DynamicTopicRepository {
  String get accountScope;
  int get sessionEpoch;
  Future<DynamicTopicDetail> detail(
    String id,
    RequestCancellation cancellation,
  );
  Future<DynamicTopicPage> feed(
    String id, {
    required int sort,
    String? cursor,
    bool folded = false,
    required RequestCancellation cancellation,
  });
  Future<void> favorite(
    String id,
    bool value,
    RequestCancellation cancellation,
  );
  Future<void> report(
    String id,
    String reason,
    RequestCancellation cancellation,
  );
}
