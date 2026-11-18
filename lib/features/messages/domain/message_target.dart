import '../../../domain/user.dart';
import '../../../domain/video.dart';
import '../../../domain/content_link.dart';

/// Resolves supported public message links without fetching or following them.
String? messageWorkspaceLocation(Uri target) {
  if (target.scheme != 'https' ||
      target.userInfo.isNotEmpty ||
      target.port != 443) {
    return null;
  }
  final parts = target.pathSegments.where((part) => part.isNotEmpty).toList();
  final host = target.host;
  const webHosts = {'www.bilibili.com', 'bilibili.com', 'm.bilibili.com'};
  final dynamicId = switch (parts) {
    [final id] when host == 't.bilibili.com' => id,
    ['dynamic' || 'opus', final id] when webHosts.contains(host) => id,
    ['mobile' || 'h5' || 'v', 'dynamic' || 'opus', final id]
        when webHosts.contains(host) =>
      id,
    _ => null,
  };
  if (dynamicId != null && RegExp(r'^[1-9][0-9]{0,127}$').hasMatch(dynamicId)) {
    final byResourceId = target.queryParameters['type'] == '2';
    final path = byResourceId
        ? '/dynamic/resource/$dynamicId'
        : '/dynamic/$dynamicId';
    return _contentLocation(path, target, playback: false);
  }
  if (host == 'www.bilibili.com' || host == 'bilibili.com') {
    if (parts case ['video', final id] when VideoId(id).isValid) {
      return _contentLocation('/video/$id', target);
    }
    if (parts case ['bangumi', 'play', final id]) {
      final match = RegExp(r'^(ep|ss)([1-9][0-9]*)$').firstMatch(id);
      if (match != null) {
        final kind = match[1] == 'ep' ? 'episode' : 'season';
        return _contentLocation('/pgc/$kind/${match[2]}', target);
      }
    }
  }
  if (parts case [final id] when RegExp(r'^[1-9][0-9]*$').hasMatch(id)) {
    if (host == 'live.bilibili.com') return '/live/$id';
    if (host == 'space.bilibili.com' && UserId(id).isValid) return '/user/$id';
  }
  return null;
}

String _contentLocation(String path, Uri target, {bool playback = true}) {
  final query = target.queryParameters;
  String? id(String? value) =>
      value != null && RegExp(r'^[1-9][0-9]{0,29}$').hasMatch(value)
      ? value
      : null;
  final root =
      id(query['comment_root_id']) ??
      id(query['root']) ??
      id(query['rpid']) ??
      id(RegExp(r'^reply([1-9][0-9]*)$').firstMatch(target.fragment)?[1]);
  final secondary = id(query['comment_secondary_id']);
  final comments = <String, String>{
    'comment_root_id': ?root,
    if (root != null) 'comment_secondary_id': ?secondary,
  };
  String location(Map<String, String> parameters) => parameters.isEmpty
      ? path
      : Uri(path: path, queryParameters: parameters).toString();
  if (!playback) return location(comments);
  int? milliseconds = int.tryParse(query['start_progress'] ?? '');
  if (milliseconds == null) {
    final progress = int.tryParse(query['dm_progress'] ?? '');
    if (progress != null && progress >= 0) {
      milliseconds = (progress - 3000).clamp(0, progress);
    }
  }
  if (milliseconds == null) {
    final seconds = double.tryParse(query['t'] ?? '');
    if (seconds != null &&
        seconds.isFinite &&
        seconds >= 0 &&
        seconds <= 604800) {
      milliseconds = (seconds * 1000).round();
    }
  }
  final parameters = <String, String>{
    'cid': ?id(query['cid']),
    'p': ?id(query['p']),
    ...comments,
    if (milliseconds != null) 'start_progress': '$milliseconds',
  };
  final link = ContentLink.fromUri(Uri(queryParameters: parameters));
  if (link.position == null) parameters.remove('start_progress');
  if (link.page == null) parameters.remove('p');
  return location(parameters);
}
