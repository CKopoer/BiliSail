import 'dynamic_models.dart';

final class ApiDynamicTopicDetail {
  const ApiDynamicTopicDetail({
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
  final String? creatorId;
  final Uri? creatorAvatar;
  final int favoriteCount;
  final bool isFavorite;
}

final class ApiDynamicTopicSort {
  const ApiDynamicTopicSort(this.id, this.name);
  final int id;
  final String name;
}

final class ApiDynamicTopicPage {
  ApiDynamicTopicPage({
    required List<ApiDynamicPost> posts,
    required this.hasMore,
    this.nextCursor,
    List<ApiDynamicTopicSort> sorts = const [],
    this.selectedSort,
    this.foldDescription = '',
  }) : posts = List.unmodifiable(posts),
       sorts = List.unmodifiable(sorts);
  final List<ApiDynamicPost> posts;
  final bool hasMore;
  final String? nextCursor;
  final List<ApiDynamicTopicSort> sorts;
  final int? selectedSort;
  final String foldDescription;
}
