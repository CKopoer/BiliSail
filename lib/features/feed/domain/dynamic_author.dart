import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import 'home_repository.dart';

final class DynamicAuthor {
  const DynamicAuthor({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.hasUpdate = false,
  });

  final UserId id;
  final String name;
  final Uri? avatarUrl;
  final bool hasUpdate;
}

final class DynamicAuthorPage {
  const DynamicAuthorPage(this.items, {required this.hasMore, this.nextCursor});

  final List<DynamicAuthor> items;
  final bool hasMore;
  final String? nextCursor;
}

abstract interface class HomeDynamicRepository {
  Future<DynamicAuthorPage> loadDynamicAuthors({
    required String scope,
    String? cursor,
    required RequestCancellation cancellation,
  });

  Future<HomePage> loadAuthorFeed(
    HomeQuery query,
    UserId authorId, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  });
}
