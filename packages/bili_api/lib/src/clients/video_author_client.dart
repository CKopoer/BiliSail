import '../api_client.dart';
import '../models.dart';

final class ApiVideoAuthor {
  const ApiVideoAuthor({
    required this.mid,
    required this.following,
    this.followerCount,
    this.likeCount,
  });
  final String mid;
  final bool following;
  final int? followerCount, likeCount;
}

/// Author totals and the current Web session's relationship to that author.
final class VideoAuthorClient {
  const VideoAuthorClient(this.api);
  final BiliApiClient api;

  Future<ApiVideoAuthor> load(String mid, {ApiRequestContext? context}) async {
    _validateMid(mid);
    const endpoint = 'video_author';
    final data = await api.requestJson(
      Uri.https('api.bilibili.com', '/x/web-interface/card', {'mid': mid}),
      endpoint,
      context: context,
    );
    final card = data['card'];
    if (card is! Map<String, Object?> ||
        (card['mid'] is! int && card['mid'] is! String) ||
        '${card['mid']}' != mid ||
        data['following'] is! bool) {
      throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    return ApiVideoAuthor(
      mid: mid,
      following: data['following'] as bool,
      followerCount: _count(data['follower'] ?? card['fans']),
      likeCount: _count(data['like_num']),
    );
  }

  Future<void> follow(
    String mid,
    bool following, {
    ApiRequestContext? context,
  }) async {
    _validateMid(mid);
    await api.submitForm('/x/relation/modify', 'video_author_follow', {
      'fid': mid,
      'act': following ? '1' : '2',
      're_src': '14',
    }, context: context);
  }

  static int? _count(Object? value) => switch (value) {
    int count when count >= 0 => count,
    String text => switch (int.tryParse(text)) {
      final int count when count >= 0 => count,
      _ => null,
    },
    _ => null,
  };

  static void _validateMid(String mid) {
    if (!RegExp(r'^[1-9]\d*$').hasMatch(mid)) {
      throw ArgumentError('Invalid author ID');
    }
  }
}
