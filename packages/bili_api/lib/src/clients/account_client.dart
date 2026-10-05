import '../api_client.dart';
import '../models.dart';
import '../models/message_models.dart';

final class AccountClient {
  const AccountClient(this.api);
  final BiliApiClient api;

  Future<ApiAccountOverview> overview(
    String mid, {
    ApiRequestContext? context,
  }) async {
    final nav = await api.requestJson(
      Uri.https('api.bilibili.com', '/x/web-interface/nav'),
      'account_overview',
      context: context,
    );
    if (nav['isLogin'] != true || '${nav['mid']}' != mid) {
      throw const ApiFailure(
        ApiFailureCategory.authentication,
        'account_overview',
      );
    }
    final stats = await api.requestJson(
      Uri.https('api.bilibili.com', '/x/web-interface/nav/stat'),
      'account_statistics',
      context: context,
    );
    final level = nav['level_info'];
    final info =
        level is Map<String, Object?> ? level : const <String, Object?>{};
    final vip = nav['vip_label'];
    return ApiAccountOverview(
      mid: mid,
      level: _int(info['current_level']),
      currentExperience: _int(info['current_exp']),
      levelExperience: _int(info['current_min']),
      nextExperience: _int(info['next_exp']),
      following: _int(stats['following']),
      followers: _int(stats['follower']),
      dynamics: _int(stats['dynamic_count']),
      vipLabel:
          nav['vipStatus'] == 1 &&
                  vip is Map<String, Object?> &&
                  vip['text'] is String
              ? vip['text'] as String?
              : null,
      coins: nav['money'] is num ? nav['money'] as num : null,
    );
  }

  int? _int(Object? value) => value is int ? value : int.tryParse('$value');
}
