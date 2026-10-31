import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../auth/domain/app_session_credentials.dart';
import '../domain/casting.dart';

final class ApiCastMediaRepository implements CastMediaRepository {
  const ApiCastMediaRepository(
    this.api,
    this.requests, {
    required this.credentials,
  });
  final BiliApiClient api;
  final ApiRequests requests;
  final AppSessionCredentials? Function() credentials;

  @override
  Future<Uri> resolve(
    CastMediaRequest request, {
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    var objectId = request.episodeId ?? request.aid;
    if (objectId == null && request.bvid != null) {
      objectId = (await api.getVideoDetail(
        request.bvid!,
        context: context,
      )).aid;
    }
    if (objectId == null) {
      throw const AppFailure(AppFailureKind.playback, '当前内容暂不支持投屏');
    }
    final credential = credentials();
    final token =
        credential != null &&
            !credential.invalid &&
            credential.expiresAt.isAfter(DateTime.now())
        ? credential.accessToken
        : null;
    try {
      return await CastClient(api).playUrl(
        objectId: objectId,
        cid: request.cid,
        episode: request.episodeId != null,
        quality: request.quality,
        accessToken: token,
        context: context,
      );
    } on ApiFailure catch (error) {
      if (error.category == ApiFailureCategory.unavailable) {
        throw const AppFailure(
          AppFailureKind.playback,
          '当前内容没有可投屏的完整音视频地址，请尝试其他视频',
        );
      }
      rethrow;
    }
  }, cancellation: cancellation);
}
