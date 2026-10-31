import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Public client profile, separate from a user's App access token.
abstract final class AppProfile {
  static const appKey = 'dfca71928277209b';
  static const _signingSalt = 'b5475a8825547a4fc26c7d518eaaa02e';
  static const userAgent =
      'Mozilla/5.0 BiliDroid/2.0.1 (bbcallen@gmail.com) os/android '
      'model/android_hd mobi_app/android_hd build/2001100 channel/master '
      'innerVer/2001100 osVer/15 network/2';

  // Fixed feed compatibility fields, not hardware fingerprints or live tracing.
  static const _recommendationHeaders = {
    'app-key': 'android64',
    'fp_local':
        '1111111111111111111111111111111111111111111111111111111111111111',
    'fp_remote':
        '1111111111111111111111111111111111111111111111111111111111111111',
    'session_id': '11111111',
    'x-bili-trace-id': '11111111111111111111111111111111:1111111111111111:0:0',
    'x-bili-aurora-eid': '',
    'x-bili-aurora-zone': 'sh001',
    'bili-http-engine': 'cronet',
    'referer': 'https://www.bilibili.com',
  };

  static Map<String, String> recommendationHeaders(String? accountMid) => {
    ..._recommendationHeaders,
    if (accountMid != null) ...{
      'x-bili-mid': accountMid,
      'x-bili-aurora-eid': _auroraEid(accountMid),
    },
  };

  static String _auroraEid(String accountMid) {
    const mask = 'ad1va46a7lza';
    final bytes = [
      for (var index = 0; index < accountMid.length; index++)
        accountMid.codeUnitAt(index) ^ mask.codeUnitAt(index % mask.length),
    ];
    return base64Encode(bytes).replaceAll('=', '');
  }

  static Map<String, String> sign(
    Map<String, String> parameters,
    DateTime now,
  ) {
    final values = {...parameters}..remove('sign');
    values['appkey'] = appKey;
    values['ts'] = '${now.millisecondsSinceEpoch ~/ 1000}';
    final keys = values.keys.toList()..sort();
    final query = keys
        .map(
          (key) => values[key]!.isEmpty
              ? Uri.encodeComponent(key)
              : '${Uri.encodeComponent(key)}=${Uri.encodeComponent(values[key]!)}',
        )
        .join('&');
    return {
      ...values,
      'sign': md5.convert(utf8.encode('$query$_signingSalt')).toString(),
    };
  }
}
