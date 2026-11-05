import '../../../domain/request_cancellation.dart';
import 'message_repository.dart';

abstract interface class MessageManagementRepository {
  Future<void> setPinned(
    InboxEntry entry,
    bool pinned, {
    required RequestCancellation cancellation,
  });
  Future<void> setMuted(
    InboxEntry entry,
    bool muted, {
    required RequestCancellation cancellation,
  });
  Future<void> removeConversation(
    InboxEntry entry, {
    required RequestCancellation cancellation,
  });
}
