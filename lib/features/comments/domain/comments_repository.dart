import '../../../domain/user.dart';
import '../../../domain/request_cancellation.dart';

enum CommentSort { hot, latest }

final class CommentEntry {
  const CommentEntry({
    required this.id,
    required this.author,
    required this.message,
    this.avatarUrl,
    this.authorId,
    this.publishedAt,
    this.ipLocation,
    this.likeCount = 0,
    this.liked = false,
    this.replyCount = 0,
    this.rootId,
    this.parentId,
    this.replies = const [],
    this.level,
    this.verifyType,
    this.vipLabel,
    this.medalName,
    this.medalLevel,
    this.decorationImageUrl,
    this.decorationName,
    this.decorationFanNumber,
    this.decorationFanColor,
    this.emotes = const {},
    this.mentionedUsers = const {},
    this.pictures = const [],
  });
  final int? level, verifyType, medalLevel;
  final String? vipLabel, medalName;
  final Uri? decorationImageUrl;
  final String? decorationName, decorationFanNumber;

  /// 24-bit RGB; Flutter colors are constructed only in presentation.
  final int? decorationFanColor;
  final Map<String, Uri> emotes;
  final Map<String, UserId> mentionedUsers;
  final List<Uri> pictures;
  final String id, author, message;
  final Uri? avatarUrl;
  final UserId? authorId;
  final DateTime? publishedAt;
  final String? ipLocation;
  final int likeCount, replyCount;
  final bool liked;
  final String? rootId, parentId;
  final List<CommentEntry> replies;
  CommentEntry withLike(bool value) => CommentEntry(
    id: id,
    author: author,
    message: message,
    level: level,
    verifyType: verifyType,
    vipLabel: vipLabel,
    medalName: medalName,
    medalLevel: medalLevel,
    decorationImageUrl: decorationImageUrl,
    decorationName: decorationName,
    decorationFanNumber: decorationFanNumber,
    decorationFanColor: decorationFanColor,
    emotes: emotes,
    mentionedUsers: mentionedUsers,
    pictures: pictures,
    avatarUrl: avatarUrl,
    authorId: authorId,
    publishedAt: publishedAt,
    ipLocation: ipLocation,
    likeCount: (likeCount + (value ? 1 : -1)).clamp(0, 1 << 31),
    liked: value,
    replyCount: replyCount,
    rootId: rootId,
    parentId: parentId,
    replies: replies,
  );
  CommentEntry withReplies(List<CommentEntry> value, {int? count}) =>
      CommentEntry(
        id: id,
        author: author,
        message: message,
        level: level,
        verifyType: verifyType,
        vipLabel: vipLabel,
        medalName: medalName,
        medalLevel: medalLevel,
        decorationImageUrl: decorationImageUrl,
        decorationName: decorationName,
        decorationFanNumber: decorationFanNumber,
        decorationFanColor: decorationFanColor,
        emotes: emotes,
        mentionedUsers: mentionedUsers,
        pictures: pictures,
        avatarUrl: avatarUrl,
        authorId: authorId,
        publishedAt: publishedAt,
        ipLocation: ipLocation,
        likeCount: likeCount,
        liked: liked,
        replyCount: count ?? replyCount,
        rootId: rootId,
        parentId: parentId,
        replies: List.unmodifiable(value),
      );
}

final class CommentPage {
  const CommentPage({
    required this.items,
    required this.hasMore,
    this.totalCount,
  });
  final List<CommentEntry> items;
  final bool hasMore;
  final int? totalCount;
}

final class CommentWriteUncertain implements Exception {
  const CommentWriteUncertain();
}

abstract interface class CommentsRepository {
  String get accountScope;
  int get sessionEpoch;
  Future<CommentPage> load(
    String oid,
    int page,
    CommentSort sort,
    RequestCancellation cancellation,
  );
  Future<CommentPage> replies(
    String oid,
    String rootId,
    int page,
    RequestCancellation cancellation,
  );
  Future<void> like(
    String oid,
    String id,
    bool liked,
    RequestCancellation cancellation,
  );
  Future<CommentEntry> send(
    String oid,
    String message, {
    String? rootId,
    String? parentId,
    required RequestCancellation cancellation,
  });
}

final class CommentEmotePackage {
  const CommentEmotePackage(this.name, this.items);
  final String name;
  final List<CommentEmote> items;
}

final class CommentEmote {
  const CommentEmote(this.text, this.imageUrl);
  final String text;
  final Uri? imageUrl;
}

abstract interface class CommentEmotesRepository {
  Future<List<CommentEmotePackage>> emotes(RequestCancellation cancellation);
}
