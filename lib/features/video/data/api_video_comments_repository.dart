import '../../../domain/user.dart';

import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/video_comments_repository.dart';

final class ApiVideoCommentsRepository
    implements VideoCommentsRepository, CommentEmotesRepository {
  ApiVideoCommentsRepository(
    this.api,
    this.requests, {
    required String Function() accountScope,
  }) : _scope = accountScope;
  final BiliApiClient api;
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
    pictures: v.pictures,
    avatarUrl: v.avatarUrl,
    publishedAt: v.publishedAt,
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
    String aid,
    int page,
    CommentSort sort,
    RequestCancellation cancellation,
  ) => requests.run(
    (ctx) async => _page(
      await api.getVideoComments(
        aid,
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
    String aid,
    String rootId,
    int page,
    RequestCancellation cancellation,
  ) => requests.run(
    (ctx) async =>
        _page(await api.getVideoReplies(aid, rootId, page: page, context: ctx)),
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
    String aid,
    String id,
    bool liked,
    RequestCancellation cancellation,
  ) => _write(
    (ctx) => api.likeVideoComment(aid, id, liked, context: ctx),
    cancellation,
  );
  @override
  Future<CommentEntry> send(
    String aid,
    String message, {
    String? rootId,
    String? parentId,
    required RequestCancellation cancellation,
  }) => _write(
    (ctx) async => _entry(
      await api.addVideoComment(
        aid,
        message,
        rootId: rootId,
        parentId: parentId,
        context: ctx,
      ),
    ),
    cancellation,
  );
}
