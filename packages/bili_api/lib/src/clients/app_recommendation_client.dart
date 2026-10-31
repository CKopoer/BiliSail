import '../api_client.dart';
import '../models.dart';
import '../models/app_recommendation_models.dart';
import '../video_identifiers.dart';

final class AppRecommendationClient {
  AppRecommendationClient(this.api);
  final BiliApiClient api;

  Future<ApiPage<ApiAppRecommendation>> load({
    required int page,
    required String buvid,
    String? accessToken,
    String? appAccountMid,
    ApiRequestContext? context,
  }) async {
    if (page < 1) throw ArgumentError.value(page, 'page');
    final data = await api.requestAppJson(
      '/x/v2/feed/index',
      {
        'build': '8430300',
        'mobi_app': 'android_i',
        'platform': 'android',
        'c_locale': 'zh_CN',
        's_locale': 'zh_CN',
        'splash_id': '',
        'channel': 'master',
        'column': '2',
        'device': 'phone',
        'device_name': 'android',
        'device_type': '0',
        'disable_rcmd': '0',
        'flush': '8',
        'idx': '${page - 1}',
        'pull': page == 1 ? 'true' : 'false',
        'fnval': '976',
        'fnver': '0',
        'force_host': '2',
        'fourk': '1',
        'guidance': '1',
        'https_url_req': '1',
        'network': 'wifi',
        'player_net': '1',
        'qn': '32',
        'recsys_mode': '0',
        'voice_balance': '0',
        'statistics': '{"appId":1,"platform":3,"version":"8.43.0","abtest":""}',
      },
      endpoint: 'app_recommended',
      buvid: buvid,
      accessToken: accessToken,
      appAccountMid: appAccountMid,
      context: context,
    );
    final entries = data['items'];
    if (entries is! List || entries.length > 100) {
      throw const ApiFailure(ApiFailureCategory.protocol, 'app_recommended');
    }
    final items = <ApiAppRecommendation>[];
    for (final entry in entries) {
      if (entry is! Map<String, Object?> ||
          entry['card_goto'] == 'ad_av' ||
          entry['card_goto'] == 'ad_web_s' ||
          entry['ad_info'] != null ||
          entry['can_play'] != 1) {
        continue;
      }
      final item = _parse(entry);
      if (item != null) items.add(item);
    }
    return ApiPage(
      List.unmodifiable(items),
      hasMore: entries.isNotEmpty,
      nextCursor: entries.isEmpty ? null : '${page + 1}',
    );
  }

  Future<void> feedback({
    required String aid,
    required String buvid,
    required String accessToken,
    String goto = 'av',
    ApiAppFeedbackReason? reason,
    required bool undo,
    ApiRequestContext? context,
  }) async {
    if (!RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(aid) ||
        !RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,63}$').hasMatch(goto) ||
        (!undo && reason == null)) {
      throw ArgumentError('Missing App feedback identity');
    }
    await api.requestAppJson(
      undo ? '/x/feed/dislike/cancel' : '/x/feed/dislike',
      {
        'id': aid,
        'goto': goto,
        'build': '1',
        'mobi_app': 'android',
        if (!undo && reason != null)
          (reason.kind == ApiAppFeedbackKind.dislike
                  ? 'reason_id'
                  : 'feedback_id'):
              reason.id,
      },
      endpoint: undo ? 'app_feedback_undo' : 'app_feedback',
      buvid: buvid,
      accessToken: accessToken,
      context: context,
    );
  }

  static ApiAppRecommendation? _parse(Map<String, Object?> entry) {
    final player = _map(entry['player_args']);
    final args = _map(entry['args']);
    final cardGoto = entry['card_goto'];
    final param = _id(entry['param']);
    if (cardGoto is! String ||
        !RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,63}$').hasMatch(cardGoto) ||
        param == null) {
      return null;
    }
    final isVideo = cardGoto == 'av';
    // Non-video params identify episodes/dynamics, not AV archives.
    final aid = _id(player['aid']) ?? (isVideo ? param : null);
    final suppliedBvid = entry['bvid'];
    final String? bvid;
    if (!isVideo) {
      bvid = '';
    } else if (suppliedBvid is String &&
        RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(suppliedBvid)) {
      bvid = suppliedBvid;
    } else {
      bvid = aid == null ? null : VideoIdentifiers.bvidFromAid(aid);
    }
    final title = entry['title'];
    if (bvid == null || title is! String || title.trim().isEmpty) return null;
    final reason = entry['rcmd_reason'] is String
        ? entry['rcmd_reason'] as String
        : null;
    final followed =
        entry['is_followed'] == 1 ||
        entry['is_followed'] == true ||
        const {'已关注', '新关注'}.contains(reason);
    final reasons = <ApiAppFeedbackReason>[];
    final groups = entry['three_point_v2'];
    if (groups is List) {
      for (final group in groups.take(10)) {
        final map = _map(group);
        final kind = switch (map['type']) {
          'dislike' => ApiAppFeedbackKind.dislike,
          'feedback' => ApiAppFeedbackKind.feedback,
          _ => null,
        };
        final values = map['reasons'];
        if (kind == null || values is! List) continue;
        for (final value in values.take(20)) {
          final item = _map(value), id = _id(_map(value)['id']);
          final name = item['name'];
          if (id != null &&
              name is String &&
              name.trim().isNotEmpty &&
              name.length <= 100 &&
              reasons.length < 40 &&
              !reasons.any((item) => item.id == id && item.kind == kind)) {
            reasons.add(ApiAppFeedbackReason(id: id, name: name, kind: kind));
          }
        }
      }
    }
    final seconds = _integer(player['duration']);
    return ApiAppRecommendation(
      aid: aid,
      cardGoto: cardGoto,
      param: param,
      navigationUri: entry['uri'] is String
          ? Uri.tryParse(entry['uri'] as String)
          : null,
      reasons: List.unmodifiable(reasons),
      video: ApiVideoSummary(
        bvid: bvid,
        title: title,
        coverUrl: _image(entry['cover']),
        ownerName: isVideo
            ? (args['up_name'] is String ? args['up_name'] as String : '')
            : (_map(entry['desc_button'])['text'] is String
                  ? _map(entry['desc_button'])['text'] as String
                  : ''),
        ownerMid: _id(args['up_id']),
        previewCid: _id(player['cid']),
        duration: Duration(
          seconds: seconds != null && seconds >= 0 && seconds <= 604800
              ? seconds
              : 0,
        ),
        playCount: _count(entry['cover_left_text_1']),
        danmakuCount: _count(entry['cover_left_text_2']),
        categoryName: args['tname'] is String ? args['tname'] as String : null,
        isFollowed: followed ? true : null,
        recommendationReason: followed || reason == '竖屏' ? null : reason,
      ),
    );
  }

  static Map<String, Object?> _map(Object? value) =>
      value is Map<String, Object?> ? value : const {};
  static int? _integer(Object? value) => value is int
      ? value
      : value is String
      ? int.tryParse(value)
      : null;
  static String? _id(Object? value) {
    final text = value is int || value is String ? '$value' : '';
    return RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(text) ? text : null;
  }

  static int? _count(Object? value) {
    if (value is int) return value >= 0 ? value : null;
    if (value is! String || value.length > 32) return null;
    final match = RegExp(
      r'^(\d+(?:\.\d+)?)\s*(万|亿)?$',
    ).firstMatch(value.trim());
    if (match == null) return null;
    final parsed = double.tryParse(match[1]!);
    final factor = switch (match[2]) {
      '万' => 10000,
      '亿' => 100000000,
      _ => 1,
    };
    final total = parsed == null ? null : parsed * factor;
    return total != null && total.isFinite && total <= 9007199254740991
        ? total.round()
        : null;
  }

  static Uri? _image(Object? value) {
    if (value is! String) return null;
    final uri = Uri.tryParse(value.startsWith('//') ? 'https:$value' : value);
    if (uri == null ||
        uri.userInfo.isNotEmpty ||
        !const ['http', 'https'].contains(uri.scheme) ||
        !(uri.host == 'hdslb.com' || uri.host.endsWith('.hdslb.com'))) {
      return null;
    }
    return uri.replace(scheme: 'https');
  }
}
