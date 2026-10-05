import '../../../domain/request_cancellation.dart';
import 'live_room.dart';

abstract interface class LiveRepository {
  String get accountScope;
  int get sessionEpoch;

  Future<LiveRoom> loadRoom(
    RoomId id, {
    required RequestCancellation cancellation,
  });

  Future<LivePlayInfo> loadPlayInfo(
    RoomId id, {
    int quality = 10000,
    required RequestCancellation cancellation,
  });

  Future<List<LiveChatMessage>> loadChatHistory(
    RoomId id, {
    required RequestCancellation cancellation,
  });

  Future<List<LiveSuperChatMessage>> loadSuperChats(
    RoomId id, {
    required RequestCancellation cancellation,
  });
}
