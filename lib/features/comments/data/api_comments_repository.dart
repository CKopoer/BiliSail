import '../../../domain/user.dart';
import '../../../domain/comment_target.dart';

import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/comments_repository.dart';

final class ApiCommentsRepository
    implements CommentsRepository, CommentEmotesRepository {
  ApiCommentsRepository(
    this.api,
    this.requests, {
    required String Function() accountScope,
    this.type = CommentTargetType.video,
  }) : _scope = accountScope;
  final BiliApiClient api;
  final CommentTargetType type;
  final ApiRequests requests;
  final String Function() _scope;
  @override
  String get accountScope => _scope();
  @override
  int get sessionEpoch => requests.sessionEpoch;
  static CommentEntry _entry(ApiVideoComment v) => CommentEntry(
    id: v.id,
    author: v.author,
    authorId: UserId.tryParse(v.authorMid),
    message: v.message,
    level: v.level,
    verifyType: v.verifyType,
    vipLabel: v.vipLabel,
    medalName: v.medalName,
    medalLevel: v.medalLevel,
    decorationImageUrl: v.decorationImageUrl,
    decorationName: v.decorationName,
    decorationFanNumber: v.decorationFanNumber,
    decorationFanColor: v.decorationFanColor,
    emotes: v.emotes,
    mentionedUsers: Map.unmodifiable({
      for (final entry in v.mentionedUsers.entries)
        entry.key: ?UserId.tryParse(entry.value),
    }),
    pictures: v.pictures,
    avatarUrl: v.avatarUrl,
    publishedAt: v.publishedAt,
    ipLocation: v.ipLocation,
    likeCount: v.likeCount,
    liked: v.liked,
    replyCount: v.replyCount,
    rootId: v.rootId,
    parentId: v.parentId,
    replies: List.unmodifiable(v.replies.map(_entry)),
  );
  static CommentPage _page(ApiPage<ApiVideoComment> p) => CommentPage(
    items: List.unmodifiable(p.items.map(_entry)),
    hasMore: p.hasMore,
    totalCount: p.totalCount,
  );
  @override
  Future<List<CommentEmotePackage>> emotes(RequestCancellation cancellation) =>
      requests.run(
        (ctx) async => List.unmodifiable(
          (await api.getCommentEmotes(context: ctx)).map(
            (p) => CommentEmotePackage(
              p.name,
              List.unmodifiable(
                p.items.map((e) => CommentEmote(e.text, e.imageUrl)),
              ),
            ),
          ),
        ),
        cancellation: cancellation,
      );
  @override
  Future<CommentPage> load(
    String oid,
    int page,
    CommentSort sort,
    RequestCancellation cancellation,
  ) => requests.run(
    (ctx) async => _page(
      await api.getVideoComments(
        oid,
        commentType: type.value,
        page: page,
        sort: sort == CommentSort.hot
            ? ApiCommentSort.hot
            : ApiCommentSort.latest,
        context: ctx,
      ),
    ),
    cancellation: cancellation,
  );
  @override
  Future<CommentPage> replies(
    String oid,
    String rootId,
    int page,
    RequestCancellation cancellation,
  ) => requests.run(
    (ctx) async => _page(
      await api.getVideoReplies(
        oid,
        rootId,
        page: page,
        commentType: type.value,
        context: ctx,
      ),
    ),
    cancellation: cancellation,
  );
  Future<T> _write<T>(
    Future<T> Function(ApiRequestContext) operation,
    RequestCancellation c,
  ) => requests.run((ctx) async {
    try {
      return await operation(ctx);
    } on ApiFailure catch (e) {
      if (ctx.cancellation?.isCancelled == true) rethrow;
      if ([
        ApiFailureCategory.network,
        ApiFailureCategory.timeout,
        ApiFailureCategory.protocol,
        ApiFailureCategory.http,
      ].contains(e.category)) {
        throw const CommentWriteUncertain();
      }
      rethrow;
    }
  }, cancellation: c);
  @override
  Future<void> like(
    String oid,
    String id,
    bool liked,
    RequestCancellation cancellation,
  ) => _write(
    (ctx) => api.likeVideoComment(
      oid,
      id,
      liked,
      commentType: type.value,
      context: ctx,
    ),
    cancellation,
  );
  @override
  Future<CommentEntry> send(
    String oid,
    String message, {
    String? rootId,
    String? parentId,
    required RequestCancellation cancellation,
  }) => _write(
    (ctx) async => _entry(
      await api.addVideoComment(
        oid,
        message,
        commentType: type.value,
        rootId: rootId,
        parentId: parentId,
        context: ctx,
      ),
    ),
    cancellation,
  );
}
