import '../../live/domain/live_room.dart';
import '../../../domain/video.dart';

String? dynamicPollId(Uri target) {
  if (target.userInfo.isNotEmpty) return null;
  final path = target.path.endsWith('/')
      ? target.path.substring(0, target.path.length - 1)
      : target.path;
  final web =
      target.scheme == 'https' &&
      target.port == 443 &&
      const {
        't.bilibili.com',
        'www.bilibili.com',
        'm.bilibili.com',
      }.contains(target.host) &&
      const {'/vote/h5/index', '/h5/vote'}.contains(path);
  final app =
      target.scheme == 'bilibili' &&
      !target.hasPort &&
      target.host == 'following' &&
      path == '/vote';
  final ids = target.queryParametersAll['vote_id'];
  if (ids == null || ids.length != 1) return null;
  final id = ids.single;
  return (web || app) &&
          RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(id) &&
          int.tryParse(id) != null
      ? id
      : null;
}

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
  if (target.userInfo.isNotEmpty) return null;
  final path = target.path.endsWith('/')
      ? target.path.substring(0, target.path.length - 1)
      : target.path;
  const hosts = {'www.bilibili.com', 'm.bilibili.com'};
  const paths = {'/v/topic/detail', '/topic-detail', '/topic'};
  final web =
      target.scheme == 'https' &&
      target.port == 443 &&
      hosts.contains(target.host) &&
      paths.contains(path);
  final app =
      target.scheme == 'bilibili' &&
      !target.hasPort &&
      ((const {'topic', 'topic-detail'}.contains(target.host) &&
              path.isEmpty) ||
          (hosts.contains(target.host) && paths.contains(path)));
  if (!web && !app) {
    return null;
  }
  final id = target.queryParameters['topic_id'];
  return _validTopicId(id) ? id : null;
}

/// A topic tag's identity takes precedence over tracking or browser jump URLs.
/// Name-only and unrecognised topic links remain inside application search.
Uri? dynamicTopicDestination({String? id, required String name, Uri? url}) {
  final topicId = _validTopicId(id)
      ? id
      : url == null
      ? null
      : dynamicTopicId(url);
  if (topicId != null) {
    return Uri.https('www.bilibili.com', '/v/topic/detail', {
      'topic_id': topicId,
    });
  }
  var keyword = name.trim();
  if (keyword.length > 1 && keyword.startsWith('#') && keyword.endsWith('#')) {
    keyword = keyword.substring(1, keyword.length - 1).trim();
  }
  if (keyword.isEmpty) return null;
  if (keyword.length > 512) keyword = keyword.substring(0, 512);
  return Uri.https('search.bilibili.com', '/all', {'keyword': keyword});
}

bool _validTopicId(String? id) =>
    id != null && id.length <= 128 && RegExp(r'^[1-9][0-9]*$').hasMatch(id);

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
