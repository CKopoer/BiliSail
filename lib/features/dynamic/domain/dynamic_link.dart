import '../../live/domain/live_room.dart';

RoomId? dynamicLiveRoom(Uri target) {
  if (target.scheme != 'https' ||
      target.host != 'live.bilibili.com' ||
      target.port != 443 ||
      target.userInfo.isNotEmpty) {
    return null;
  }
  final parts = target.pathSegments.where((part) => part.isNotEmpty);
  if (parts.length != 1) return null;
  final room = RoomId(parts.single);
  return room.isValid ? room : null;
}
