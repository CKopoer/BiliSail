final class ApiLiveEmoticon {
  const ApiLiveEmoticon({
    required this.unique,
    required this.text,
    required this.imageUrl,
    required this.isSticker,
    required this.allowed,
    required this.unlockHint,
  });
  final String unique, text, unlockHint;
  final Uri? imageUrl;
  final bool isSticker, allowed;
}

final class ApiLiveEmoticonPackage {
  ApiLiveEmoticonPackage(this.name, Iterable<ApiLiveEmoticon> items)
    : items = List.unmodifiable(items);
  final String name;
  final List<ApiLiveEmoticon> items;
}

final class ApiLiveRoom {
  const ApiLiveRoom({
    required this.roomId,
    required this.title,
    required this.anchorName,
    required this.anchorMid,
    required this.anchorAvatarUrl,
    required this.coverUrl,
    required this.description,
    required this.areaName,
    required this.liveStatus,
    required this.popularity,
  });

  final String roomId;
  final String title;
  final String anchorName;
  final String? anchorMid;
  final Uri? anchorAvatarUrl;
  final Uri? coverUrl;
  final String description;
  final String areaName;
  final int liveStatus;
  final int? popularity;
}

final class ApiLivePlayInfo {
  const ApiLivePlayInfo({
    required this.roomId,
    required this.liveStatus,
    required this.streams,
    this.qualities = const [],
    this.qualityLabels = const {},
  });

  final String roomId;
  final int liveStatus;
  final List<ApiLiveStream> streams;
  final List<int> qualities;
  final Map<int, String> qualityLabels;
}

final class ApiLiveStream {
  const ApiLiveStream({
    required this.urls,
    required this.quality,
    required this.qualityLabel,
    required this.format,
    required this.codec,
  });

  /// Signed, short-lived CDN URLs. Do not persist or log these values.
  final List<Uri> urls;
  final int quality;
  final String qualityLabel;
  final String format;
  final String codec;
}

final class ApiLiveChatMessage {
  const ApiLiveChatMessage({
    required this.userName,
    required this.text,
    required this.timestamp,
    this.id,
    this.color = 0xffffffff,
    this.mode = 1,
    this.fontSize = 24,
    this.userId,
    this.emotes = const {},
    this.sticker,
  });

  final String userName;
  final String text;
  final DateTime? timestamp;
  final String? id;
  final int color, mode, fontSize;
  final String? userId;
  final Map<String, ApiLiveChatImage> emotes;
  final ApiLiveChatImage? sticker;
}

final class ApiLiveChatImage {
  const ApiLiveChatImage({
    required this.url,
    this.width = 24,
    this.height = 24,
  });
  final Uri url;
  final int width, height;
}

/// Short-lived connection data. Never persist or log the token or device ID.
final class ApiLiveConnectionInfo {
  ApiLiveConnectionInfo({
    required this.roomId,
    required this.token,
    required this.buvid,
    required this.userId,
    required Iterable<Uri> hosts,
  }) : hosts = List.unmodifiable(hosts);

  final String roomId, token, buvid, userId;
  final List<Uri> hosts;
}

enum ApiLiveConnectionPhase {
  idle,
  fetching,
  connecting,
  authenticating,
  connected,
  reconnecting,
  failed,
  offline,
  closed,
}

sealed class ApiLiveEvent {
  const ApiLiveEvent();
}

final class ApiLiveConnectionChanged extends ApiLiveEvent {
  const ApiLiveConnectionChanged(this.phase, {this.failure});
  final ApiLiveConnectionPhase phase;
  final ApiLiveConnectionFailure? failure;
}

enum ApiLiveConnectionFailure {
  network,
  timeout,
  authentication,
  limited,
  protocol,
}

final class ApiLiveChatReceived extends ApiLiveEvent {
  const ApiLiveChatReceived(this.message);
  final ApiLiveChatMessage message;
}

final class ApiLiveSuperChatReceived extends ApiLiveEvent {
  const ApiLiveSuperChatReceived(this.message);
  final ApiLiveSuperChatMessage message;
}

final class ApiLiveSuperChatDeleted extends ApiLiveEvent {
  ApiLiveSuperChatDeleted(Iterable<String> ids) : ids = List.unmodifiable(ids);
  final List<String> ids;
}

final class ApiLiveRoomStatusChanged extends ApiLiveEvent {
  const ApiLiveRoomStatusChanged(this.isLive);
  final bool isLive;
}

final class ApiLivePopularityChanged extends ApiLiveEvent {
  const ApiLivePopularityChanged(this.popularity);
  final int popularity;
}

/// Server-reported viewer display, distinct from heartbeat popularity.
final class ApiLiveViewerCountChanged extends ApiLiveEvent {
  const ApiLiveViewerCountChanged(this.countText);
  final String countText;
}

final class ApiLiveSuperChatMessage {
  const ApiLiveSuperChatMessage({
    required this.id,
    required this.userName,
    required this.text,
    required this.price,
    this.avatarUrl,
    this.startedAt,
    this.expiresAt,
    this.backgroundColor,
    this.backgroundBottomColor,
    this.textColor,
    this.userId,
  });

  final String id, userName, text;
  final String? userId;
  final int price;
  final Uri? avatarUrl;
  final DateTime? startedAt, expiresAt;

  /// ARGB colors, independent of Flutter's Color type.
  final int? backgroundColor, backgroundBottomColor, textColor;
}
