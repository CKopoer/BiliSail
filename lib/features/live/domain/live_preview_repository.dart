import '../../../domain/request_cancellation.dart';
import 'live_room.dart';

/// Read-only homepage preview, independent of room entry and chat reporting.
abstract interface class LivePreviewRepository {
  String get accountScope;
  int get sessionEpoch;

  Future<LivePlayInfo> loadPreview(
    RoomId id, {
    required RequestCancellation cancellation,
  });
}
