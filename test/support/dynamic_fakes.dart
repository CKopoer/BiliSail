import 'dart:async';

import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/comments/domain/comments_repository.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_repository.dart';

final class DynamicAuthFake implements AuthRepository {
  DynamicAuthFake({bool signedIn = true})
    : current = AuthState(
        status: signedIn ? AuthStatus.signedIn : AuthStatus.guest,
        mid: signedIn ? '7' : null,
      );
  final stream = StreamController<AuthState>.broadcast(sync: true);
  @override
  AuthState current;
  @override
  Stream<AuthState> get changes => stream.stream;
  void change(AuthState state) {
    current = state;
    stream.add(state);
  }

  @override
  Future<void> restore() async {}
  @override
  Future<void> signIn() async {}
  @override
  void cancelSignIn() {}
  @override
  Future<void> signOut() async => change(const AuthState());
}

final class DynamicRepositoryFake implements DynamicRepository {
  @override
  String accountScope = 'user:7';
  @override
  int sessionEpoch = 1;
  final likes = <(String, bool)>[];
  final reposts = <(String, String)>[];
  RequestCancellation? lastCancellation;
  Completer<void>? pendingLike;
  Completer<String>? pendingRepost;
  Object? error;
  DynamicPost loaded = DynamicPost(id: '100', likeCount: 5, liked: true);
  @override
  Future<DynamicPost> detail(
    String id,
    RequestCancellation cancellation,
  ) async => loaded;
  @override
  Future<void> like(
    String id,
    bool liked,
    RequestCancellation cancellation,
  ) async {
    likes.add((id, liked));
    lastCancellation = cancellation;
    if (error case final Object e) throw e;
    await pendingLike?.future;
  }

  @override
  Future<String> repost(
    String id,
    String text,
    RequestCancellation cancellation,
  ) async {
    reposts.add((id, text));
    lastCancellation = cancellation;
    if (error case final Object e) throw e;
    return pendingRepost?.future ?? '101';
  }
}

final class DynamicCommentsFake
    implements CommentsRepository, CommentEmotesRepository {
  @override
  String accountScope = 'user:7';
  @override
  int sessionEpoch = 1;
  final reads = <String>[];
  final writes = <(String, String, String?, String?)>[];
  final likes = <(String, String, bool)>[];
  List<CommentEntry> items = const [
    CommentEntry(
      id: '50',
      author: '评论作者',
      message: '测试评论',
      replyCount: 1,
      replies: [
        CommentEntry(
          id: '51',
          author: '回复作者',
          message: '楼中楼回复',
          rootId: '50',
          parentId: '50',
        ),
      ],
    ),
  ];
  Completer<CommentEntry>? pendingSend;
  @override
  Future<CommentPage> load(
    String aid,
    int page,
    CommentSort sort,
    RequestCancellation cancellation,
  ) async {
    reads.add(aid);
    return CommentPage(items: items, hasMore: false, totalCount: items.length);
  }

  @override
  Future<CommentPage> replies(
    String aid,
    String rootId,
    int page,
    RequestCancellation cancellation,
  ) async => CommentPage(items: items.first.replies, hasMore: false);
  @override
  Future<void> like(
    String aid,
    String id,
    bool liked,
    RequestCancellation cancellation,
  ) async {
    likes.add((aid, id, liked));
  }

  @override
  Future<CommentEntry> send(
    String aid,
    String message, {
    String? rootId,
    String? parentId,
    required RequestCancellation cancellation,
  }) async {
    writes.add((aid, message, rootId, parentId));
    return pendingSend?.future ??
        CommentEntry(
          id: '52',
          author: '我',
          message: message,
          rootId: rootId,
          parentId: parentId,
        );
  }

  @override
  Future<List<CommentEmotePackage>> emotes(
    RequestCancellation cancellation,
  ) async => const [
    CommentEmotePackage('表情', [CommentEmote('[测试]', null)]),
  ];
}
