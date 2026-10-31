import '../api_client.dart';
import '../models.dart';

/// TV projection returns a combined stream; DASH video alone has no sound.
final class CastClient {
  const CastClient(this.api);
  final BiliApiClient api;

  Future<Uri> playUrl({
    required String objectId,
    required String cid,
    required bool episode,
    required int quality,
    String? accessToken,
    ApiRequestContext? context,
  }) async {
    if (![
          objectId,
          cid,
        ].every((id) => RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(id)) ||
        quality <= 0) {
      throw ArgumentError('Invalid casting identity or quality');
    }
    final data = await api.requestCastJson({
      'actionKey': 'appkey',
      'cid': cid,
      'object_id': objectId,
      'playurl_type': episode ? '2' : '1',
      'qn': '$quality',
      'fourk': '1',
      'is_proj': '1',
      'mobi_app': 'android',
      'platform': 'android',
      'protocol': '0',
      if (accessToken != null && accessToken.isNotEmpty) ...{
        'access_key': accessToken,
        'mobile_access_key': accessToken,
      },
    }, context: context);
    if (data['is_preview'] == 1 || data['is_preview'] == true) {
      throw const ApiFailure(ApiFailureCategory.permission, 'cast_playurl');
    }
    final durl = data['durl'];
    // Multiple progressive segments cannot be handed off as one complete video.
    if (durl is! List || durl.length != 1) {
      throw const ApiFailure(ApiFailureCategory.unavailable, 'cast_playurl');
    }
    final item = durl.single;
    if (item is! Map<String, Object?>) {
      throw const ApiFailure(ApiFailureCategory.protocol, 'cast_playurl');
    }
    final value = item['url'];
    final uri = value is String ? Uri.tryParse(value) : null;
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const ApiFailure(ApiFailureCategory.protocol, 'cast_playurl');
    }
    return uri;
  }
}
