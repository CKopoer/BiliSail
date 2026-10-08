import 'dart:async';

enum ApiFailureCategory {
  cancelled,
  timeout,
  network,
  http,
  rateLimited,
  authentication,
  permission,
  notFound,
  protocol,
  unavailable,
}

final class ApiFailure implements Exception {
  const ApiFailure(
    this.category,
    this.endpointId, {
    this.httpStatus,
    this.businessCode,
    this.retryAfter,
  });

  final ApiFailureCategory category;
  final String endpointId;
  final int? httpStatus;
  final int? businessCode;
  final Duration? retryAfter;

  @override
  String toString() =>
      'ApiFailure($category, $endpointId, '
      'httpStatus: $httpStatus, businessCode: $businessCode)';
}

final class ApiCancellation {
  final Completer<void> _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

final class ApiRequestContext {
  const ApiRequestContext({
    this.cancellation,
    this.deadline,
    this.sessionEpoch,
  });
  final ApiCancellation? cancellation;
  final DateTime? deadline;
  final int? sessionEpoch;
}

final class ApiPage<T> {
  const ApiPage(
    this.items, {
    required this.hasMore,
    this.nextCursor,
    this.totalCount,
  });
  final List<T> items;
  final bool hasMore;
  final String? nextCursor;
  final int? totalCount;
}

final class ApiVideoSummary {
  const ApiVideoSummary({
    required this.bvid,
    required this.title,
    required this.coverUrl,
    required this.ownerName,
    required this.duration,
    this.playCount,
    this.danmakuCount,
    this.publishedAt,
    this.ownerAvatarUrl,
    this.ownerMid,
    this.recommendationReason,
    this.recommendationFeedback,
    this.previewCid,
  });
  final String bvid;
  final String title;
  final Uri? coverUrl;
  final String ownerName;
  final Duration duration;
  final int? playCount;
  final int? danmakuCount;
  final DateTime? publishedAt;
  final Uri? ownerAvatarUrl;
  final String? ownerMid;
  final String? recommendationReason;
  final ApiRecommendationFeedback? recommendationFeedback;
  final String? previewCid;
}

final class ApiRecommendationFeedback {
  const ApiRecommendationFeedback({
    required this.aid,
    required this.goto,
    required this.trackId,
    required this.ownerMid,
  });
  final String aid, goto, trackId, ownerMid;
}

final class ApiVideoPage {
  const ApiVideoPage({
    required this.cid,
    required this.page,
    required this.title,
    required this.duration,
  });
  final String cid;
  final int page;
  final String title;
  final Duration duration;
}

enum ApiCommentSort { hot, latest }

final class ApiVideoComment {
  const ApiVideoComment({
    required this.id,
    required this.author,
    required this.avatarUrl,
    required this.message,
    required this.likeCount,
    required this.publishedAt,
    this.ipLocation,
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
    this.authorMid,
  });
  final int? level, verifyType, medalLevel;
  final String? vipLabel, medalName;
  final Uri? decorationImageUrl;
  final String? decorationName, decorationFanNumber;

  /// Optional 24-bit RGB color of the decoration's fan serial number.
  final int? decorationFanColor;
  final Map<String, Uri> emotes;

  /// Server-supplied mention names mapped to decimal user IDs.
  final Map<String, String> mentionedUsers;
  final List<Uri> pictures;
  final bool liked;
  final int replyCount;
  final String? rootId;
  final String? parentId;
  final List<ApiVideoComment> replies;
  final String id;
  final String author;
  final String? authorMid;
  final Uri? avatarUrl;
  final String message;
  final int likeCount;
  final DateTime? publishedAt;

  /// Server-supplied display text from reply_control.location.
  final String? ipLocation;
}

final class ApiVideoCollection {
  const ApiVideoCollection({
    required this.id,
    required this.title,
    required this.entries,
    this.playCount,
  });
  final String id;
  final String title;
  final List<ApiVideoCollectionEntry> entries;
  final int? playCount;
}

final class ApiVideoCollectionEntry {
  const ApiVideoCollectionEntry({
    required this.bvid,
    required this.title,
    this.pages = const [],
    this.duration,
  });
  final String bvid;
  final String title;
  final Duration? duration;

  /// Empty when the collection response omits parts; load video detail lazily.
  final List<ApiVideoPage> pages;
}

final class ApiVideoDetail {
  const ApiVideoDetail({
    required this.aid,
    required this.bvid,
    required this.title,
    required this.description,
    required this.coverUrl,
    required this.ownerName,
    required this.pages,
    this.playCount,
    this.danmakuCount,
    this.publishedAt,
    this.ownerAvatarUrl,
    this.ownerMid,
    this.likeCount,
    this.coinCount,
    this.favoriteCount,
    this.collection,
    this.replyCount,
  });
  final String aid;
  final String bvid;
  final String title;
  final String description;
  final Uri? coverUrl;
  final String ownerName;
  final List<ApiVideoPage> pages;
  final int? playCount;
  final int? danmakuCount;
  final DateTime? publishedAt;
  final Uri? ownerAvatarUrl;
  final String? ownerMid;
  final int? likeCount;
  final int? coinCount;
  final int? favoriteCount;
  final ApiVideoCollection? collection;
  final int? replyCount;
}

final class ApiMediaTrack {
  const ApiMediaTrack({
    required this.id,
    required this.url,
    required this.backupUrls,
    required this.bandwidth,
    required this.mimeType,
    required this.codecs,
  });
  final int id;
  final Uri url;
  final List<Uri> backupUrls;
  final int bandwidth;
  final String mimeType;
  final String codecs;
}

final class ApiPlayInfo {
  const ApiPlayInfo({
    required this.duration,
    required this.dashVideo,
    required this.dashAudio,
    required this.acceptQuality,
    this.isPreview = false,
  });
  final Duration duration;
  final List<ApiMediaTrack> dashVideo;
  final List<ApiMediaTrack> dashAudio;
  final List<int> acceptQuality;

  /// The server supplied only a preview clip, not a complete episode.
  final bool isPreview;
}

final class ApiSubtitleTrack {
  const ApiSubtitleTrack({
    required this.languageCode,
    required this.label,
    required this.url,
  });
  final String languageCode;
  final String label;
  final Uri url;
}

final class ApiSubtitleCue {
  const ApiSubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });
  final Duration start;
  final Duration end;
  final String text;
}

final class ApiDanmakuItem {
  const ApiDanmakuItem({
    required this.id,
    required this.progress,
    required this.mode,
    required this.fontSize,
    required this.color,
    required this.content,
    this.weight = 0,
  });
  final String id;
  final Duration progress;
  final int mode;
  final int fontSize;
  final int color;
  final String content;
  final int weight;
}

final class ApiQrCode {
  const ApiQrCode({required this.url, required this.key});
  final Uri url;
  final String key;
}

enum ApiQrStatus { waitingScan, waitingConfirm, expired, confirmed }

final class ApiQrPollResult {
  const ApiQrPollResult(this.status);
  final ApiQrStatus status;
}

final class ApiNavInfo {
  const ApiNavInfo({
    required this.isLogin,
    this.mid,
    this.name,
    this.avatarUrl,
  });
  final bool isLogin;
  final String? mid;
  final String? name;
  final Uri? avatarUrl;
}

final class ApiCommentEmotePackage {
  const ApiCommentEmotePackage(this.name, this.items);
  final String name;
  final List<ApiCommentEmote> items;
}

final class ApiCommentEmote {
  const ApiCommentEmote(this.text, this.imageUrl);
  final String text;
  final Uri? imageUrl;
}
