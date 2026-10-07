import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
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

/// Optional current-audience snapshots, independent of media and chat reads.
abstract interface class LiveViewerRepository {
  Future<int?> loadViewerCount(
    RoomId id,
    UserId anchorId, {
    required RequestCancellation cancellation,
  });
}

final class UnavailableLiveViewerRepository implements LiveViewerRepository {
  const UnavailableLiveViewerRepository();
  @override
  Future<int?> loadViewerCount(
    RoomId id,
    UserId anchorId, {
    required RequestCancellation cancellation,
  }) async => null;
}
