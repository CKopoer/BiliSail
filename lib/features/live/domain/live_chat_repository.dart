import '../../../domain/request_cancellation.dart';
import 'live_room.dart';

abstract interface class LiveChatRepository {
  Stream<List<LiveRealtimeEvent>> watchRoom(
    RoomId id, {
    required RequestCancellation cancellation,
  });
}

enum LiveConnectionPhase {
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

sealed class LiveRealtimeEvent {
  const LiveRealtimeEvent();
}

final class LiveConnectionChanged extends LiveRealtimeEvent {
  const LiveConnectionChanged(this.phase, {this.message});
  final LiveConnectionPhase phase;
  final String? message;
}

final class LiveChatReceived extends LiveRealtimeEvent {
  const LiveChatReceived(this.message);
  final LiveChatMessage message;
}

final class LiveSuperChatReceived extends LiveRealtimeEvent {
  const LiveSuperChatReceived(this.message);
  final LiveSuperChatMessage message;
}

final class LiveSuperChatDeleted extends LiveRealtimeEvent {
  LiveSuperChatDeleted(Iterable<String> ids) : ids = List.unmodifiable(ids);
  final List<String> ids;
}

final class LiveRoomStatusChanged extends LiveRealtimeEvent {
  const LiveRoomStatusChanged(this.isLive);
  final bool isLive;
}

final class LivePopularityChanged extends LiveRealtimeEvent {
  const LivePopularityChanged(this.popularity);
  final int popularity;
}

final class LiveViewerCountChanged extends LiveRealtimeEvent {
  const LiveViewerCountChanged(this.countText);
  final String countText;
}

/// Optional transport port for screens/tests supplying only HTTP snapshots.
final class UnavailableLiveChatRepository implements LiveChatRepository {
  const UnavailableLiveChatRepository();
  @override
  Stream<List<LiveRealtimeEvent>> watchRoom(
    RoomId id, {
    required RequestCancellation cancellation,
  }) => const Stream.empty();
}
