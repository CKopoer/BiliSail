import '../../../domain/user.dart';
import '../../../domain/video.dart';

/// Resolves supported public message links without fetching or following them.
String? messageWorkspaceLocation(Uri target) {
  if (target.scheme != 'https' ||
      target.userInfo.isNotEmpty ||
      target.port != 443) {
    return null;
  }
  final parts = target.pathSegments.where((part) => part.isNotEmpty).toList();
  final host = target.host;
  if (host == 'www.bilibili.com' || host == 'bilibili.com') {
    if (parts case ['video', final id] when VideoId(id).isValid) {
      return '/video/$id';
    }
    if (parts case ['bangumi', 'play', final id]) {
      final match = RegExp(r'^(ep|ss)([1-9][0-9]*)$').firstMatch(id);
      if (match != null) {
        final kind = match[1] == 'ep' ? 'episode' : 'season';
        return '/pgc/$kind/${match[2]}';
      }
    }
  }
  if (parts case [final id] when RegExp(r'^[1-9][0-9]*$').hasMatch(id)) {
    if (host == 'live.bilibili.com') return '/live/$id';
    if (host == 'space.bilibili.com' && UserId(id).isValid) return '/user/$id';
  }
  return null;
}
