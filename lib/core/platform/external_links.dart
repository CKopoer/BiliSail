import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Only explicit user gestures open public content; no session data is added.
final externalLinkOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => (uri) async {
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        !const {
          'www.bilibili.com',
          'live.bilibili.com',
          't.bilibili.com',
          'message.bilibili.com',
          'space.bilibili.com',
        }.contains(uri.host)) {
      return false;
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  },
);
