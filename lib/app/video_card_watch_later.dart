import '../domain/app_failure.dart';
import '../domain/request_cancellation.dart';
import '../domain/video.dart';
import '../features/feed/domain/home_channel.dart';
import '../features/feed/domain/home_repository.dart';
import '../features/video/domain/video_card_interactions.dart';

/// Bridges shared video cards to the account list and its deletion owner.
final class AppVideoCardWatchLaterRepository
    implements VideoCardWatchLaterRepository {
  AppVideoCardWatchLaterRepository(
    this.home,
    this.removeEntry, {
    this.removedIds,
  });

  final HomeRepository home;
  final Future<bool> Function(HomeEntry, RequestCancellation) removeEntry;
  final Set<String> Function()? removedIds;

  @override
  Future<Map<VideoId, String>> load(RequestCancellation cancellation) async {
    final page = await home.load(
      (
        channel: HomeChannel.watchLater,
        section: '全部',
        scope: home.accountScope,
        folderId: null,
      ),
      page: 1,
      cancellation: cancellation,
    );
    // This endpoint returns a complete list; match the queue's 1000-item budget.
    if (page.hasMore || page.items.length > 1000) {
      throw const AppFailure(AppFailureKind.protocol, '稍后再看列表不完整，请刷新');
    }
    final removed = removedIds?.call() ?? const <String>{};
    return {
      for (final entry in page.items)
        if (entry.kind == HomeEntryKind.video &&
            !removed.contains(entry.id) &&
            VideoId(entry.bvid ?? '').isValid &&
            RegExp(r'^[1-9][0-9]*$').hasMatch(entry.aid ?? ''))
          VideoId(entry.bvid ?? ''): entry.aid ?? '',
    };
  }

  @override
  Future<bool> remove(
    VideoId id,
    String aid,
    RequestCancellation cancellation,
  ) => removeEntry(
    HomeEntry(
      id: id.value,
      bvid: id.value,
      aid: aid,
      title: '',
      kind: HomeEntryKind.video,
    ),
    cancellation,
  );
}
