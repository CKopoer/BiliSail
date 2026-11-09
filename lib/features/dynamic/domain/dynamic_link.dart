import '../../live/domain/live_room.dart';
import '../../../domain/video.dart';

String? dynamicSearchQuery(Uri target) {
  if (target.scheme != 'https' ||
      target.port != 443 ||
      target.userInfo.isNotEmpty ||
      target.host != 'search.bilibili.com' ||
      !const {'/all', '/all/'}.contains(target.path)) {
    return null;
  }
  final keyword = target.queryParameters['keyword']?.trim();
  return keyword != null && keyword.isNotEmpty && keyword.length <= 512
      ? keyword
      : null;
}

String? dynamicTopicId(Uri target) {
  if (target.scheme != 'https' ||
      target.port != 443 ||
      target.userInfo.isNotEmpty ||
      !const {'www.bilibili.com', 'm.bilibili.com'}.contains(target.host) ||
      !const {'/v/topic/detail', '/v/topic/detail/'}.contains(target.path)) {
    return null;
  }
  final id = target.queryParameters['topic_id'];
  return id != null && id.length <= 128 && RegExp(r'^[1-9][0-9]*$').hasMatch(id)
      ? id
      : null;
}

VideoId? dynamicVideo(Uri target) {
  if (!_bilibiliTarget(target)) return null;
  final parts = target.pathSegments;
  if (parts.length != 2 || parts.first != 'video') return null;
  final id = VideoId(parts.last);
  return id.isValid ? id : null;
}

/// A route understood by the existing PGC workspace, preserving ep/ss identity.
String? dynamicPgcRoute(Uri target) {
  if (!_bilibiliTarget(target)) return null;
  final match = RegExp(r'^/bangumi/play/(ep|ss)([1-9][0-9]*)/?$')
      .firstMatch(target.path);
  if (match == null) return null;
  return match[1] == 'ep'
      ? '/pgc/episode/${match[2]}'
      : '/pgc/season/${match[2]}';
}

bool _bilibiliTarget(Uri target) =>
    target.scheme == 'https' &&
    target.host == 'www.bilibili.com' &&
    target.port == 443 &&
    target.userInfo.isEmpty;

RoomId? dynamicLiveRoom(Uri target) {
  if (target.scheme != 'https' ||
      target.host != 'live.bilibili.com' ||
      target.port != 443 ||
      target.userInfo.isNotEmpty) {
    return null;
  }
  final parts = target.pathSegments.where((part) => part.isNotEmpty);
  if (parts.length != 1) return null;
  final room = RoomId(parts.single);
  return room.isValid ? room : null;
}
