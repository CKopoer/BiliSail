import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/live_danmaku_repository.dart';
import '../domain/live_room.dart';

final class ApiLiveDanmakuRepository implements LiveDanmakuRepository {
  ApiLiveDanmakuRepository(
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
  Future<List<LiveEmoticonPackage>> loadEmoticons(
    RoomId room, {
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    final packages = await client.getEmoticons(room.value, context: context);
    return List.unmodifiable(
      packages.map(
        (package) => LiveEmoticonPackage(
          package.name,
          package.items.map(
            (item) => LiveEmoticon(
              unique: item.unique,
              text: item.text,
              imageUrl: item.imageUrl,
              isSticker: item.isSticker,
              allowed: item.allowed,
              unlockHint: item.unlockHint,
            ),
          ),
        ),
      ),
    );
  }, cancellation: cancellation);

  @override
  Future<void> send(
    RoomId room,
    String text, {
    String? emoticonUnique,
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    try {
      await client.sendDanmaku(
        room.value,
        text,
        emoticonUnique: emoticonUnique,
        context: context,
      );
    } on ApiFailure catch (error) {
      if (context.cancellation?.isCancelled == true) rethrow;
      if (const {
        ApiFailureCategory.network,
        ApiFailureCategory.timeout,
        ApiFailureCategory.protocol,
        ApiFailureCategory.http,
      }.contains(error.category)) {
        throw const LiveDanmakuWriteUncertain();
      }
      rethrow;
    }
  }, cancellation: cancellation);
}
