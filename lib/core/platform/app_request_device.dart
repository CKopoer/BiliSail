import 'dart:async';

import 'package:bili_api/bili_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reads public Android OS facts without hardware IDs or new plugin dependencies.
final class AppRequestDevice {
  const AppRequestDevice();
  static const _channel = MethodChannel('dev.bilisail/app_request_device');

  Future<AppDeviceInfo> load() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const AppDeviceInfo();
    }
    try {
      final data = await _channel
          .invokeMapMethod<String, Object?>('read')
          .timeout(const Duration(seconds: 2));
      String value(String key, String fallback) {
        final text = data?[key];
        return text is String &&
                text.isNotEmpty &&
                text.length <= 100 &&
                !RegExp(r'[\x00-\x1f\x7f]').hasMatch(text)
            ? text
            : fallback;
      }

      final network = value('network', '');
      return AppDeviceInfo(
        model: value('model', 'android'),
        osVersion: value('osVersion', ''),
        network: const {'wifi', 'mobile'}.contains(network) ? network : '',
      );
    } on MissingPluginException {
      return const AppDeviceInfo(model: 'android', osVersion: '', network: '');
    } on TimeoutException {
      return const AppDeviceInfo(model: 'android', osVersion: '', network: '');
    } on PlatformException {
      return const AppDeviceInfo(model: 'android', osVersion: '', network: '');
    }
  }
}
