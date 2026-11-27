import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Public OS/device facts, with a fixed HD reference on non-Android hosts.
final class AppDeviceInfo {
  const AppDeviceInfo({
    this.model = 'android_hd',
    this.osVersion = '15',
    this.network = 'wifi',
  });
  final String model, osVersion, network;
}

/// Public client profile, separate from a user's App access token.
abstract final class AppProfile {
  static const appKey = 'dfca71928277209b';
  static const build = '2001100';
  static const mobiApp = 'android_hd';
  static const _signingSalt = 'b5475a8825547a4fc26c7d518eaaa02e';
  static const userAgent =
      'Mozilla/5.0 BiliDroid/2.0.1 (bbcallen@gmail.com) os/android '
      'model/android_hd mobi_app/android_hd build/2001100 channel/master '
      'innerVer/2001100 osVer/15 network/2';

  static String userAgentFor(AppDeviceInfo device) {
    return 'Mozilla/5.0 BiliDroid/2.0.1 (bbcallen@gmail.com) os/android '
        'model/${_deviceToken(device.model, 'android_hd')} mobi_app/android_hd '
        'build/2001100 channel/master innerVer/2001100 '
        'osVer/${_deviceToken(device.osVersion, '0')} '
        'network/${_networkCode(device.network)}';
  }

  static Map<String, String> sign(
    Map<String, String> parameters,
    DateTime now,
  ) => _signAppRequest(parameters, now, appKey, _signingSalt);
}

/// Android phone profile for the Pegasus home feed.
abstract final class AndroidRecommendationProfile {
  static const _appKey = '1d8b6e7d45233436';
  static const _signingSalt = '560c52ccd288fed045859ed18bffd973';
  static const version = '9.21.0';
  static const build = '9210300';
  static const mobiApp = 'android';
  static const statistics =
      '{"appId":1,"platform":3,"version":"$version","abtest":""}';

  static String deviceName(AppDeviceInfo device) => _deviceToken(
    device.model == AppProfile.mobiApp ? '' : device.model,
    mobiApp,
  );

  static String userAgentFor(AppDeviceInfo device) =>
      'Mozilla/5.0 BiliDroid/$version (bbcallen@gmail.com) os/android '
      'model/${deviceName(device)} mobi_app/$mobiApp '
      'build/$build channel/master innerVer/$build '
      'osVer/${_deviceToken(device.osVersion, '0')} '
      'network/${_networkCode(device.network)}';

  static Map<String, String> sign(
    Map<String, String> parameters,
    DateTime now,
  ) => _signAppRequest(parameters, now, _appKey, _signingSalt);

  // Unavailable SDK fingerprints are omitted.
  static const _recommendationHeaders = {
    'app-key': 'android64',
    'x-bili-aurora-eid': '',
    'x-bili-aurora-zone': 'sh001',
    'referer': 'https://www.bilibili.com',
  };

  static Map<String, String> recommendationHeaders(
    String? accountMid, {
    required String sessionId,
    required String traceId,
  }) => {
    ..._recommendationHeaders,
    'session_id': sessionId,
    'x-bili-trace-id': traceId,
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
}

String _deviceToken(String value, String fallback) =>
    value.isNotEmpty &&
        value.length <= 100 &&
        !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)
    ? value
    : fallback;

String _networkCode(String network) => switch (network) {
  'mobile' => '1',
  'wifi' => '2',
  _ => '0',
};

Map<String, String> _signAppRequest(
  Map<String, String> parameters,
  DateTime now,
  String appKey,
  String signingSalt,
) {
  final values = {...parameters}..remove('sign');
  values['appkey'] = appKey;
  values['ts'] = '${now.millisecondsSinceEpoch ~/ 1000}';
  final keys = values.keys.toList()..sort();
  // Empty values still include '=', notably the feed's splash_id.
  final query = keys
      .map(
        (key) =>
            '${Uri.encodeComponent(key)}=${Uri.encodeComponent(values[key]!)}',
      )
      .join('&');
  return {
    ...values,
    'sign': md5.convert(utf8.encode('$query$signingSalt')).toString(),
  };
}
