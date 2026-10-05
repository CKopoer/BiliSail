import '../../../domain/request_cancellation.dart';
import 'live_room.dart';

final class LiveEmoticon {
  const LiveEmoticon({
    required this.unique,
    required this.text,
    this.imageUrl,
    this.isSticker = false,
    this.allowed = false,
    this.unlockHint = '',
  });
  final String unique, text, unlockHint;
  final Uri? imageUrl;
  final bool isSticker, allowed;
}

final class LiveEmoticonPackage {
  LiveEmoticonPackage(this.name, Iterable<LiveEmoticon> items)
    : items = List.unmodifiable(items);
  final String name;
  final List<LiveEmoticon> items;
}

abstract interface class LiveDanmakuRepository {
  String get accountScope;
  int get sessionEpoch;
  Future<List<LiveEmoticonPackage>> loadEmoticons(
    RoomId room, {
    required RequestCancellation cancellation,
  });
  Future<void> send(
    RoomId room,
    String text, {
    String? emoticonUnique,
    required RequestCancellation cancellation,
  });
}

final class LiveDanmakuWriteUncertain implements Exception {
  const LiveDanmakuWriteUncertain();
}
