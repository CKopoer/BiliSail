import 'dart:async';

import 'package:bili_api/bili_api.dart';

/// Explicit guest-only, receive-only check. Outputs audience counters, never
/// chat content, identity, URLs, device identifiers, cookies or discovery tokens.
Future<void> main(List<String> args) async {
  final api = BiliApiClient();
  LiveChatSession? session;
  StreamSubscription<List<ApiLiveEvent>>? subscription;
  try {
    final client = LiveClient(api);
    final room = await client.getRoom(args.isEmpty ? '7777' : args.first);
    final anchor = room.anchorMid;
    if (anchor == null) {
      throw const ApiFailure(ApiFailureCategory.protocol, 'live_viewer_count');
    }
    final count = await client.getViewerCount(
      room.roomId,
      anchor,
      context: ApiRequestContext(
        deadline: DateTime.now().add(const Duration(seconds: 20)),
      ),
    );
    print('viewer_snapshot=$count');
    session = LiveChatSession(
      maxAttempts: 1,
      isCurrent: () => true,
      loadConnectionInfo: (signal) => client.getConnectionInfo(
        room.roomId,
        context: ApiRequestContext(
          cancellation: signal,
          deadline: DateTime.now().add(const Duration(seconds: 20)),
        ),
      ),
    );
    var updates = 0;
    subscription = session.events.listen((batch) {
      for (final event in batch) {
        switch (event) {
          case ApiLiveConnectionChanged(:final phase):
            print('connection=${phase.name}');
          case ApiLiveViewerCountChanged(:final countText):
            updates++;
            print('viewer_realtime=$countText');
          default:
            break;
        }
      }
    });
    await Future<void>.delayed(const Duration(seconds: 35));
    print('viewer_updates=$updates');
  } on ApiFailure catch (error) {
    print(
      'failure=${error.category.name} endpoint=${error.endpointId} code=${error.businessCode}',
    );
  } finally {
    await session?.close();
    await subscription?.cancel();
    api.close();
  }
}
