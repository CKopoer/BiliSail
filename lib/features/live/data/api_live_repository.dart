import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import '../domain/live_repository.dart';
import '../domain/live_chat_repository.dart';
import '../domain/live_room.dart';

class ApiLiveRepository implements LiveRepository, LiveChatRepository {
  ApiLiveRepository(
    this.client,
    this.requests, {
    required String Function() accountScope,
  }) : _scope = accountScope;

  final LiveClient client;
  final ApiRequests requests;
  final String Function() _scope;

  @override
  String get accountScope => _scope();
  @override
  int get sessionEpoch => requests.sessionEpoch;

  @override
  Stream<List<LiveRealtimeEvent>> watchRoom(
    RoomId id, {
    required RequestCancellation cancellation,
  }) async* {
    _validate(id);
    final unregister = requests.trackLifetime(cancellation);
    final scope = accountScope, epoch = sessionEpoch;
    bool current() =>
        !cancellation.isCancelled &&
        scope == accountScope &&
        epoch == sessionEpoch;
    final session = LiveChatSession(
      isCurrent: current,
      loadConnectionInfo: (signal) {
        final read = RequestCancellation();
        cancellation.onCancel(read.cancel);
        signal.whenCancelled.then((_) => read.cancel());
        return requests
            .run(
              (context) => client.getConnectionInfo(id.value, context: context),
              cancellation: read,
            )
            .catchError((Object error) {
              if (error is AppFailure) {
                throw ApiFailure(switch (error.kind) {
                  AppFailureKind.cancelled => ApiFailureCategory.cancelled,
                  AppFailureKind.authentication =>
                    ApiFailureCategory.authentication,
                  AppFailureKind.permission => ApiFailureCategory.permission,
                  AppFailureKind.rateLimited => ApiFailureCategory.rateLimited,
                  AppFailureKind.protocol => ApiFailureCategory.protocol,
                  AppFailureKind.timeout => ApiFailureCategory.timeout,
                  _ => ApiFailureCategory.network,
                }, 'live_danmaku_info');
              }
              throw error;
            });
      },
    );
    cancellation.onCancel(() {
      session.close();
    });
    try {
      await for (final batch in session.events) {
        if (!current()) break;
        yield List.unmodifiable(batch.map(_mapLiveEvent));
      }
    } finally {
      unregister();
      await session.close();
    }
  }

  static LiveRealtimeEvent _mapLiveEvent(ApiLiveEvent event) => switch (event) {
    ApiLiveConnectionChanged(:final phase, :final failure) =>
      LiveConnectionChanged(
        LiveConnectionPhase.values[phase.index],
        message: switch (failure) {
          ApiLiveConnectionFailure.authentication => '实时弹幕鉴权失败，请刷新或重新登录',
          ApiLiveConnectionFailure.limited => '实时弹幕请求受到限制，请稍后重试',
          ApiLiveConnectionFailure.protocol => '实时弹幕数据暂不兼容，请重试',
          ApiLiveConnectionFailure.timeout => '实时弹幕连接超时',
          ApiLiveConnectionFailure.network => '实时弹幕连接暂时中断',
          null => null,
        },
      ),
    ApiLiveChatReceived(:final message) => LiveChatReceived(_mapChat(message)),
    ApiLiveSuperChatReceived(:final message) => LiveSuperChatReceived(
      _mapSuperChat(message),
    ),
    ApiLiveSuperChatDeleted(:final ids) => LiveSuperChatDeleted(ids),
    ApiLiveRoomStatusChanged(:final isLive) => LiveRoomStatusChanged(isLive),
    ApiLivePopularityChanged(:final popularity) => LivePopularityChanged(
      popularity,
    ),
    ApiLiveViewerCountChanged(:final countText) => LiveViewerCountChanged(
      countText,
    ),
    ApiLiveWatchedCountChanged(:final countText) => LiveWatchedCountChanged(
      countText,
    ),
  };

  static LiveChatImage _mapImage(ApiLiveChatImage image) =>
      LiveChatImage(url: image.url, width: image.width, height: image.height);

  static LiveChatImage? _mapOptionalImage(ApiLiveChatImage? image) =>
      image == null ? null : _mapImage(image);

  static LiveChatMessage _mapChat(ApiLiveChatMessage message) =>
      LiveChatMessage(
        userName: message.userName,
        userId: UserId.tryParse(message.userId),
        text: message.text,
        timestamp: message.timestamp,
        id: message.id,
        color: message.color,
        mode: message.mode,
        fontSize: message.fontSize,
        emotes: Map.unmodifiable(
          message.emotes.map(
            (token, image) => MapEntry(token, _mapImage(image)),
          ),
        ),
        sticker: _mapOptionalImage(message.sticker),
      );

  static LiveSuperChatMessage _mapSuperChat(ApiLiveSuperChatMessage message) =>
      LiveSuperChatMessage(
        id: message.id,
        userName: message.userName,
        userId: UserId.tryParse(message.userId),
        text: message.text,
        price: message.price,
        avatarUrl: message.avatarUrl,
        startedAt: message.startedAt,
        expiresAt: message.expiresAt,
        backgroundColor: message.backgroundColor,
        backgroundBottomColor: message.backgroundBottomColor,
        textColor: message.textColor,
      );

  @override
  Future<LiveRoom> loadRoom(
    RoomId id, {
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    _validate(id);
    final room = await client.getRoom(id.value, context: context);
    return LiveRoom(
      id: RoomId(room.roomId),
      title: room.title,
      anchorName: room.anchorName,
      anchorId: UserId.tryParse(room.anchorMid),
      anchorAvatarUrl: room.anchorAvatarUrl,
      coverUrl: room.coverUrl,
      description: room.description,
      areaName: room.areaName,
      isLive: room.liveStatus == 1,
      popularity: room.popularity,
    );
  }, cancellation: cancellation);

  @override
  Future<LivePlayInfo> loadPlayInfo(
    RoomId id, {
    int quality = 10000,
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    _validate(id);
    final info = await client.getPlayInfo(
      id.value,
      qn: quality,
      context: context,
    );
    return LivePlayInfo(
      roomId: RoomId(info.roomId),
      isLive: info.liveStatus == 1,
      qualities: List.unmodifiable(info.qualities),
      qualityLabels: Map.unmodifiable(info.qualityLabels),
      streams: List.unmodifiable(
        info.streams.map(
          (stream) => LiveStream(
            urls: List.unmodifiable(stream.urls),
            quality: stream.quality,
            qualityLabel: stream.qualityLabel,
            format: stream.format,
            codec: stream.codec,
          ),
        ),
      ),
    );
  }, cancellation: cancellation);

  @override
  Future<List<LiveChatMessage>> loadChatHistory(
    RoomId id, {
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    _validate(id);
    final messages = await client.getChatHistory(id.value, context: context);
    return List.unmodifiable(messages.map(_mapChat));
  }, cancellation: cancellation);

  @override
  Future<List<LiveSuperChatMessage>> loadSuperChats(
    RoomId id, {
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    _validate(id);
    final messages = await client.getSuperChats(id.value, context: context);
    return List.unmodifiable(messages.map(_mapSuperChat));
  }, cancellation: cancellation);

  static void _validate(RoomId id) {
    if (!id.isValid) {
      throw const AppFailure(AppFailureKind.notFound, '直播间号无效');
    }
  }
}
