import 'dart:async';

import 'package:bili_api/bili_api.dart';

/// Explicit guest-only, receive-only WS validation. Never prints packet bodies,
/// identity, URLs, Cookie, discovery token or device ID.
Future<void> main(List<String> args) async {
  final api = BiliApiClient();
  final client = LiveClient(api);
  var roomId = args.isEmpty ? '7734200' : args.first;
  if (roomId == '--popular') {
    try {
      final data = await api.requestJson(
        Uri.https('api.live.bilibili.com', '/room/v3/Area/getRoomList', {
          'platform': 'web',
          'parent_area_id': '2',
          'area_id': '0',
          'sort_type': 'online',
          'page': '1',
          'page_size': '1',
        }),
        'live_smoke_room',
      );
      final rooms = data['list'];
      if (rooms is! List<Object?> ||
          rooms.isEmpty ||
          rooms.first is! Map<String, Object?>) {
        throw const ApiFailure(ApiFailureCategory.protocol, 'live_smoke_room');
      }
      final first = rooms.first as Map<String, Object?>;
      final id = first['roomid'] ?? first['room_id'];
      roomId =
          id is int
              ? '$id'
              : id is String
              ? id
              : '';
      if (!RegExp(r'^[1-9][0-9]*$').hasMatch(roomId)) {
        throw const ApiFailure(ApiFailureCategory.protocol, 'live_smoke_room');
      }
    } on ApiFailure catch (error) {
      print(
        'live_chat: room_discovery=${error.category.name} code=${error.businessCode}',
      );
      api.close();
      return;
    }
  }
  var connected = false, chats = 0, superChats = 0, heartbeats = 0;
  var linkedChats = 0, emoteChats = 0, stickerChats = 0, viewerUpdates = 0;
  final session = LiveChatSession(
    maxAttempts: 1,
    isCurrent: () => true,
    loadConnectionInfo: (signal) async {
      try {
        return await client.getConnectionInfo(
          roomId,
          context: ApiRequestContext(
            cancellation: signal,
            deadline: DateTime.now().add(const Duration(seconds: 25)),
          ),
        );
      } on ApiFailure catch (error) {
        print(
          'live_chat: discovery=${error.category.name} endpoint=${error.endpointId} code=${error.businessCode}',
        );
        rethrow;
      }
    },
  );
  final done = Completer<void>();
  final subscription = session.events.listen(
    (batch) {
      for (final event in batch) {
        switch (event) {
          case ApiLiveConnectionChanged(:final phase, :final failure):
            print(
              'live_chat: state=${phase.name} failure=${failure?.name ?? 'none'}',
            );
            if (phase == ApiLiveConnectionPhase.connected) connected = true;
          case ApiLiveChatReceived(:final message):
            chats++;
            if (message.userId != null) linkedChats++;
            if (message.emotes.isNotEmpty) emoteChats++;
            if (message.sticker != null) stickerChats++;
          case ApiLiveViewerCountChanged():
            viewerUpdates++;
          case ApiLiveSuperChatReceived():
            superChats++;
          case ApiLivePopularityChanged():
            heartbeats++;
          default:
            break;
        }
      }
    },
    onDone: () {
      if (!done.isCompleted) done.complete();
    },
  );
  try {
    final deadline = Timer(const Duration(seconds: 40), () {
      if (!done.isCompleted) done.complete();
    });
    await done.future;
    deadline.cancel();
    print(
      'live_chat: connected=$connected chat_messages=$chats super_chats=$superChats heartbeats=$heartbeats linked_chats=$linkedChats emote_chats=$emoteChats sticker_chats=$stickerChats viewer_updates=$viewerUpdates',
    );
  } finally {
    await session.close();
    await subscription.cancel();
    api.close();
  }
}
