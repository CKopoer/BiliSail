import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Comment links may point to any public HTTP(S) site. No credentials are added.
final webLinkOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => (uri) async {
    if (!isAllowedWebLink(uri)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  },
);

bool isAllowedWebLink(Uri uri) =>
    (uri.scheme == 'https' || uri.scheme == 'http') &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty;

/// Only explicit user gestures open public content; no session data is added.
final externalLinkOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => (uri) async {
    if (!isAllowedExternalLink(uri)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  },
);

bool isAllowedExternalLink(Uri uri) {
  if (uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.port != 443) {
    return false;
  }
  if (const {
    'www.bilibili.com',
    'live.bilibili.com',
    't.bilibili.com',
    'message.bilibili.com',
    'space.bilibili.com',
  }.contains(uri.host)) {
    return true;
  }
  return uri.host == 'github.com' &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      (uri.path == '/CKopoer/BiliSail' ||
          uri.path == '/CKopoer/BiliSail/releases' ||
          (uri.pathSegments.length == 5 &&
              uri.pathSegments.take(4).join('/') ==
                  'CKopoer/BiliSail/releases/tag'));
}
