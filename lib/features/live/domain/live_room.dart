import '../../../domain/user.dart';

/// Room identifiers stay as decimal text across API and UI boundaries.
final class RoomId {
  const RoomId(this.value);
  final String value;

  bool get isValid => RegExp(r'^[1-9][0-9]*$').hasMatch(value);

  @override
  bool operator ==(Object other) => other is RoomId && other.value == value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => value;
}

final class LiveRoom {
  const LiveRoom({
    required this.id,
    required this.title,
    required this.anchorName,
    this.anchorId,
    this.anchorAvatarUrl,
    this.coverUrl,
    this.description = '',
    this.areaName = '',
    required this.isLive,
    this.popularity,
  });

  final RoomId id;
  final String title;
  final String anchorName;
  final UserId? anchorId;
  final Uri? anchorAvatarUrl, coverUrl;
  final String description, areaName;
  final bool isLive;
  final int? popularity;
}

final class LiveChatMessage {
  const LiveChatMessage({
    required this.userName,
    required this.text,
    this.timestamp,
    this.id,
    this.color = 0xffffffff,
    this.mode = 1,
    this.fontSize = 24,
    this.userId,
    this.emotes = const {},
    this.sticker,
  });

  final String userName, text;
  final DateTime? timestamp;
  final String? id;
  final int color, mode, fontSize;
  final UserId? userId;
  final Map<String, LiveChatImage> emotes;
  final LiveChatImage? sticker;

  /// Snapshot and socket overlap; a sparse history record must retain links
  /// and images already supplied by the socket for the same message.
  LiveChatMessage withFallbackMetadata(LiveChatMessage? previous) {
    if (previous == null) return this;
    return LiveChatMessage(
      userName: userName,
      text: text,
      timestamp: timestamp,
      id: id,
      color: color,
      mode: mode,
      fontSize: fontSize,
      userId: userId ?? previous.userId,
      emotes: Map.unmodifiable(
        Map.fromEntries({...previous.emotes, ...emotes}.entries.take(50)),
      ),
      sticker: sticker ?? previous.sticker,
    );
  }

  /// History and WS use different IDs. The shared second-resolution fingerprint
  /// prevents their overlapping snapshots from showing the same chat twice.
  String get deduplicationKey {
    final time = timestamp;
    if (time != null) {
      return '$userName\u0000$text\u0000${time.toUtc().millisecondsSinceEpoch ~/ 1000}';
    }
    return id ?? '$userName\u0000$text';
  }
}

final class LiveChatImage {
  const LiveChatImage({required this.url, this.width = 24, this.height = 24});
  final Uri url;
  final int width, height;
}

final class LiveSuperChatMessage {
  const LiveSuperChatMessage({
    required this.id,
    required this.userName,
    required this.text,
    required this.price,
    this.avatarUrl,
    this.startedAt,
    this.expiresAt,
    this.displayDuration,
    this.remainingDuration,
    this.backgroundColor,
    this.backgroundBottomColor,
    this.textColor,
    this.userId,
  });

  final String id, userName, text;
  final UserId? userId;
  final int price;
  final Uri? avatarUrl;
  final DateTime? startedAt, expiresAt;

  /// Total display lifetime; HTTP remaining seconds are kept separately.
  final Duration? displayDuration;

  /// Fallback remaining time when an HTTP snapshot has no absolute expiry.
  final Duration? remainingDuration;

  /// ARGB values are kept free of any Flutter UI dependency.
  final int? backgroundColor, backgroundBottomColor, textColor;

  LiveSuperChatMessage withTiming(DateTime? start, DateTime end) =>
      LiveSuperChatMessage(
        id: id,
        userName: userName,
        userId: userId,
        text: text,
        price: price,
        avatarUrl: avatarUrl,
        startedAt: start,
        expiresAt: end,
        displayDuration: displayDuration,
        remainingDuration: remainingDuration,
        backgroundColor: backgroundColor,
        backgroundBottomColor: backgroundBottomColor,
        textColor: textColor,
      );
}

final class LivePlayInfo {
  const LivePlayInfo({
    required this.roomId,
    required this.isLive,
    required this.streams,
    this.qualities = const [],
    this.qualityLabels = const {},
  });

  final RoomId roomId;
  final bool isLive;
  final List<LiveStream> streams;
  final List<int> qualities;
  final Map<int, String> qualityLabels;
}

final class LiveStream {
  const LiveStream({
    required this.urls,
    required this.quality,
    required this.qualityLabel,
    required this.format,
    required this.codec,
  });

  final List<Uri> urls;
  final int quality;
  final String qualityLabel, format, codec;
}
